import { Hono } from "hono";
import { z } from "zod";
import type { DbUser } from "../lib/types";
import { nowIso, id } from "../lib/utils";
import { authMiddleware, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";

export const userRoutes = new Hono<AppEnv>();

userRoutes.use("*", authMiddleware);

const profileUpdateSchema = z.object({
  name: z.string().min(2).max(100).optional(),
  phone: z.string().min(6).max(20).optional(),
});

// Deliberately NOT part of profileUpdateSchema. If a client could PATCH an
// arbitrary avatar_url, it could point a rider's photo at any third-party URL —
// which the captain app then renders mid-trip. The only way to set this column
// is POST /user/avatar, so the value is always an object this API stored.
const AVATAR_PREFIX = "avatars/";
const AVATAR_ROUTE = "/user/avatar/";
const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

/// Extension is derived from the declared MIME type, never from the uploaded
/// filename — a filename is attacker-controlled and would let someone stash a
/// `.html` in the bucket that we later serve back.
const AVATAR_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
};

/// `/user/avatar/<userId>/<file>` (what the column stores, and what the app
/// requests) ⇄ `avatars/<userId>/<file>` (the R2 object key).
const keyFromPublicPath = (publicPath: string): string | null => {
  if (!publicPath.startsWith(AVATAR_ROUTE)) return null;
  const rest = publicPath.slice(AVATAR_ROUTE.length);
  if (!rest || rest.includes("..")) return null;
  return `${AVATAR_PREFIX}${rest}`;
};

const savedPlaceSchema = z.object({
  label: z.string().min(1).max(50),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  address: z.string().max(255).optional(),
});

// Partial update for an existing place — the edit screen lets the rider
// change the name, the pin, or both in one save, so every field is optional
// and COALESCE keeps whatever was not sent.
const savedPlaceUpdateSchema = z.object({
  label: z.string().min(1).max(50).optional(),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
  address: z.string().max(255).optional(),
});

userRoutes.get("/profile", async (c) => {
  const user = c.get("user");
  const dbUser = await c.env.DB.prepare(
    `SELECT id, email, name, phone, role, status, avatar_url, created_at FROM users WHERE id = ?`
  )
    .bind(user.id)
    .first<DbUser>();

  const credits = await c.env.DB.prepare(
    `SELECT balance FROM user_credits WHERE user_id = ?`
  )
    .bind(user.id)
    .first<{ balance: number }>();

  return c.json({
    user: dbUser,
    credits: credits?.balance ?? 0,
  });
});

userRoutes.patch("/profile", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, profileUpdateSchema);
  if (isResponse(body)) return body;

  await c.env.DB.prepare(
    `UPDATE users SET name = COALESCE(?, name), phone = COALESCE(?, phone), updated_at = ? WHERE id = ?`
  )
    .bind(body.name ?? null, body.phone ?? null, nowIso(), user.id)
    .run();

  const updated = await c.env.DB.prepare(
    `SELECT id, email, name, phone, role, status, avatar_url, created_at FROM users WHERE id = ?`
  )
    .bind(user.id)
    .first<DbUser>();

  return c.json({ user: updated });
});

// POST /user/avatar — replace the signed-in user's photo (multipart/form-data).
//
// Mirrors POST /captain/upload, but writes under avatars/<userId>/ and updates
// the users row itself, so the client never has to hand us a URL.
//
// This whole block landed in PR #34 and was then clobbered by PR #29's merge
// (that branch was based on a pre-#34 copy of this file), which is why riders
// saw a red "Not found" toast: the app still called POST /user/avatar but the
// deployed Worker had no such route and Hono's app.notFound answered 404.
userRoutes.post("/avatar", async (c) => {
  const user = c.get("user");

  const formData = await c.req.formData();
  const file = formData.get("file") as File | null;
  if (!file) return c.json({ error: "file required", code: "MISSING_FILE" }, 400);
  if (file.size === 0) return c.json({ error: "File is empty", code: "EMPTY_FILE" }, 400);
  if (file.size > MAX_AVATAR_BYTES) {
    return c.json({ error: "Image too large (max 5MB)", code: "FILE_TOO_LARGE" }, 400);
  }

  const contentType = (file.type || "").toLowerCase();
  const ext = AVATAR_TYPES[contentType];
  if (!ext) {
    return c.json(
      { error: "Unsupported image type. Use JPEG, PNG, WebP or HEIC.", code: "UNSUPPORTED_TYPE" },
      400,
    );
  }

  // The timestamp + UUID make every upload a distinct URL, which is what lets
  // the mobile client cache avatars forever and still see a change instantly.
  const fileName = `${Date.now()}_${id("av")}.${ext}`;
  const key = `${AVATAR_PREFIX}${user.id}/${fileName}`;
  const publicPath = `${AVATAR_ROUTE}${user.id}/${fileName}`;

  // Read the outgoing photo before overwriting the column so the old object can
  // be reaped — otherwise every re-upload leaks a file into the bucket forever.
  const previous = await c.env.DB.prepare(`SELECT avatar_url FROM users WHERE id = ?`)
    .bind(user.id)
    .first<{ avatar_url: string | null }>();

  await c.env.FILES.put(key, file.stream(), {
    httpMetadata: { contentType },
  });

  await c.env.DB.prepare(`UPDATE users SET avatar_url = ?, updated_at = ? WHERE id = ?`)
    .bind(publicPath, nowIso(), user.id)
    .run();

  if (previous?.avatar_url) {
    const staleKey = keyFromPublicPath(previous.avatar_url);
    // Best-effort cleanup: the new photo is already live and recorded, so a
    // failure to delete the old blob must not fail the rider's request.
    if (staleKey && staleKey !== key) {
      try {
        await c.env.FILES.delete(staleKey);
      } catch {
        // Orphaned object; harmless.
      }
    }
  }

  return c.json({ ok: true, avatarUrl: publicPath });
});

// GET /user/avatar/<userId>/<file> — serve a photo from R2.
//
// Readable by any authenticated user, not just its owner: a rider needs to see
// their captain's face and vice versa. The bucket is shared with captain
// documents, so the handler pins the key inside the avatars/ namespace — that
// is what stops this route being used to read someone's national ID scan.
userRoutes.get("/avatar/*", async (c) => {
  const key = keyFromPublicPath(c.req.path);
  if (!key) return c.json({ error: "Invalid avatar path", code: "BAD_KEY" }, 400);

  const obj = await c.env.FILES.get(key);
  if (!obj) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);

  const headers = new Headers();
  headers.set("Content-Type", obj.httpMetadata?.contentType ?? "image/jpeg");
  // The key is unique per upload, so a given URL's bytes never change.
  headers.set("Cache-Control", "private, max-age=31536000, immutable");
  return new Response(obj.body, { headers });
});

// DELETE /user/avatar — drop back to the initial-letter placeholder.
userRoutes.delete("/avatar", async (c) => {
  const user = c.get("user");

  const current = await c.env.DB.prepare(`SELECT avatar_url FROM users WHERE id = ?`)
    .bind(user.id)
    .first<{ avatar_url: string | null }>();

  await c.env.DB.prepare(`UPDATE users SET avatar_url = NULL, updated_at = ? WHERE id = ?`)
    .bind(nowIso(), user.id)
    .run();

  if (current?.avatar_url) {
    const key = keyFromPublicPath(current.avatar_url);
    if (key) {
      try {
        await c.env.FILES.delete(key);
      } catch {
        // Column is already cleared; a lingering object is harmless.
      }
    }
  }

  return c.json({ ok: true });
});

userRoutes.get("/saved-places", async (c) => {
  const user = c.get("user");
  const res = await c.env.DB.prepare(
    `SELECT * FROM saved_places WHERE user_id = ? ORDER BY created_at DESC`
  )
    .bind(user.id)
    .all();

  return c.json({ places: res.results ?? [] });
});

userRoutes.post("/saved-places", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, savedPlaceSchema);
  if (isResponse(body)) return body;

  const placeId = id("place");
  await c.env.DB.prepare(
    `INSERT INTO saved_places (id, user_id, label, lat, lng, address, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(placeId, user.id, body.label, body.lat, body.lng, body.address ?? null, nowIso())
    .run();

  const row = await c.env.DB.prepare(`SELECT * FROM saved_places WHERE id = ?`)
    .bind(placeId)
    .first();

  return c.json({ place: row });
});

userRoutes.patch("/saved-places/:id", async (c) => {
  const user = c.get("user");
  const placeId = c.req.param("id");
  const body = await parseBody(c, savedPlaceUpdateSchema);
  if (isResponse(body)) return body;

  // Ownership check first: without it the UPDATE below silently succeeds with
  // zero rows affected when the id belongs to someone else, which reads as
  // success to the client while changing nothing.
  const existing = await c.env.DB.prepare(
    `SELECT id FROM saved_places WHERE id = ? AND user_id = ?`
  )
    .bind(placeId, user.id)
    .first();
  if (!existing) {
    return c.json({ error: "Place not found", code: "NOT_FOUND" }, 404);
  }

  await c.env.DB.prepare(
    `UPDATE saved_places SET
       label = COALESCE(?, label),
       lat = COALESCE(?, lat),
       lng = COALESCE(?, lng),
       address = COALESCE(?, address)
     WHERE id = ? AND user_id = ?`
  )
    .bind(
      body.label ?? null,
      body.lat ?? null,
      body.lng ?? null,
      body.address ?? null,
      placeId,
      user.id,
    )
    .run();

  const row = await c.env.DB.prepare(`SELECT * FROM saved_places WHERE id = ?`)
    .bind(placeId)
    .first();

  return c.json({ place: row });
});

userRoutes.delete("/saved-places/:id", async (c) => {
  const user = c.get("user");
  const placeId = c.req.param("id");

  await c.env.DB.prepare(`DELETE FROM saved_places WHERE id = ? AND user_id = ?`)
    .bind(placeId, user.id)
    .run();

  return c.json({ ok: true });
});
