import { Hono } from "hono";
import type { Context } from "hono";
import { z } from "zod";
import {
  FILE_EXT_CONTENT_TYPE,
  isImageFileExt,
  isIsoBmffContainer,
  SNIFF_HEAD_BYTES,
  sniffFileExt,
  type StoredFileExt,
} from "@synaptic-go/shared";
import type { DbUser } from "../lib/types";
import { nowIso, id } from "../lib/utils";
import { logAudit } from "../lib/audit";
import { authMiddleware, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody, rateLimit } from "../middleware/rateLimit";

export const userRoutes = new Hono<AppEnv>();

userRoutes.use("*", authMiddleware);

/// The version a client agrees to when it posts consent, and the version served
/// by the public policy page. Bump this whenever the substance of
/// `docs/legal/privacy-policy.*.md` changes: consent is recorded against a
/// version, and "the user agreed" is worthless without "to what".
export const PRIVACY_POLICY_VERSION = "2026-08-01";

/// Trip states in which a trip is still live. Erasing one party mid-trip strands
/// the other, so deletion is refused until these clear. Taken from the status
/// literals actually present in routes/trips.ts on main — 'searching','offered'
/// and 'assigned','arrived','in_progress' are the two live sets there;
/// 'completed' and 'cancelled' are the terminal pair.
const ACTIVE_TRIP_STATUSES = ["searching", "offered", "assigned", "arrived", "in_progress"];

/// After erasure the users row survives so the ledger keeps balancing, but
/// `email` is NOT NULL UNIQUE (0001_init.sql:5) and so cannot simply be nulled
/// the way name and phone are. It is replaced by a value that is unique, is not
/// a routable address, and cannot collide with a real sign-up. That is also what
/// stops the erased person being found by their old address at login
/// (routes/auth.ts:392 looks users up by email) and what lets them register
/// again from scratch with the same address.
const tombstoneEmail = (userId: string) => `deleted+${userId}@deleted.invalid`;

/// Erasure is only erasure if the next request cannot undo it. The access token
/// is a stateless JWT — middleware/auth.ts never reads the database — so a token
/// minted seconds before deletion stays syntactically valid until it expires,
/// and PATCH /user/profile would happily write a fresh name onto the tombstone.
/// The delete handler revokes every refresh token, so the session cannot be
/// extended; this guard closes the remaining access-token window.
///
/// GET /user/avatar/* is exempt: it serves other people's photos mid-trip, tells
/// the caller nothing about themselves, and is on the hot path.
userRoutes.use("*", async (c, next) => {
  if (c.req.method === "GET" && c.req.path.startsWith("/user/avatar/")) return next();

  const user = c.get("user");
  const row = await c.env.DB.prepare(`SELECT deleted_at FROM users WHERE id = ?`)
    .bind(user.id)
    .first<{ deleted_at: string | null }>();

  // A token for a row that no longer exists is not a valid session either.
  if (!row || row.deleted_at) {
    return c.json({ error: "Account deleted", code: "ACCOUNT_DELETED" }, 401);
  }
  return next();
});

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

/// An avatar is a photograph. The accepted set, the byte signatures and the
/// canonical Content-Type all live in @synaptic-go/shared alongside their tests,
/// shared with POST /captain/upload — this sniffer used to be a second, untested
/// copy of that logic. The document route additionally accepts PDF; an avatar
/// does not, which is enforced with isImageFileExt below.
///
/// Only HEIC/HEIF may fall back to the declared type, and only when the bytes
/// present a genuine ISO-BMFF container.
const AVATAR_HEIC_DECLARED: Record<string, StoredFileExt> = {
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

  // The bytes decide the type. The previous order checked the declared type
  // first, skipped sniffing on a hit, and then stored that same client-supplied
  // string as the object's Content-Type — so a client could label anything
  // `image/png` and have it stored and served back under that type. The stored
  // extension was never taken from the filename, but the declared type was just
  // as much the client's choice.
  const declaredType = (file.type || "").toLowerCase();
  const head = new Uint8Array(await file.slice(0, SNIFF_HEAD_BYTES).arrayBuffer());
  let ext: StoredFileExt | null = sniffFileExt(head);

  if (!ext && isIsoBmffContainer(head)) {
    // Genuine ISO-BMFF container with a brand the sniffer does not name: honour
    // an explicit HEIC/HEIF declaration, since that registry is open-ended.
    ext = AVATAR_HEIC_DECLARED[declaredType] ?? null;
  }

  // An avatar must be a photograph. PDF is a valid captain document but is not
  // a face, and this column feeds an <img>/Image.network in both apps.
  if (!ext || !isImageFileExt(ext)) {
    return c.json(
      { error: "Unsupported image type. Use JPEG, PNG, WebP or HEIC.", code: "UNSUPPORTED_TYPE" },
      400,
    );
  }

  // Canonical, derived from the verified bytes — never the client's string.
  const contentType = FILE_EXT_CONTENT_TYPE[ext];

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
  // Every avatar is a byte-verified image, so nothing here should ever be
  // content-sniffed into something executable. Matches the two document routes.
  headers.set("X-Content-Type-Options", "nosniff");
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

// ===========================================================================
// Privacy: consent, export, erasure.  E16 — launch-gate item 12.
//
// Closes F-25-02 (consent never recorded) and F-25-03 (no access, export,
// correction or erasure path). F-25-01 (no policy) is closed by docs/legal/
// plus the public policy page at the bottom of this file.
// ===========================================================================

const consentSchema = z.object({
  document: z.enum(["privacy_policy", "terms_of_service"]),
  version: z.string().min(1).max(40),
  action: z.enum(["granted", "withdrawn"]),
  source: z.enum(["rider_app", "captain_app", "web"]),
  locale: z.string().min(2).max(10).optional(),
});

// POST /user/consent — record an agreement or a withdrawal.
//
// Append-only: a withdrawal is a new row. The table's triggers reject UPDATE and
// DELETE outright, so this handler cannot "fix" a previous row even by mistake.
userRoutes.post("/consent", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, consentSchema);
  if (isResponse(body)) return body;

  const consentId = id("cns");
  await c.env.DB.prepare(
    `INSERT INTO user_consents (id, user_id, document, version, action, source, locale, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      consentId,
      user.id,
      body.document,
      body.version,
      body.action,
      body.source,
      body.locale ?? null,
      nowIso(),
    )
    .run();

  // The request metadata lives here rather than on the consent row, because
  // user_consents forbids the UPDATE that redacting an IP after erasure needs.
  await logAudit(c.env.DB, {
    actorId: user.id,
    action: `consent.${body.action}`,
    entityType: "user_consent",
    entityId: consentId,
    payload: { document: body.document, version: body.version, source: body.source },
    ip: c.req.header("cf-connecting-ip") ?? null,
    userAgent: c.req.header("user-agent") ?? null,
  });

  return c.json({ ok: true, consentId, recordedAt: nowIso() });
});

// GET /user/consent — the user's own consent history, plus the current state per
// document. "Current" is the newest row, which is why this can be a plain
// ordered read rather than a status column that could drift from the history.
userRoutes.get("/consent", async (c) => {
  const user = c.get("user");

  const res = await c.env.DB.prepare(
    `SELECT id, document, version, action, source, locale, created_at
       FROM user_consents WHERE user_id = ? ORDER BY created_at DESC, id DESC`
  )
    .bind(user.id)
    .all<{ document: string; version: string; action: string; created_at: string }>();

  const records = res.results ?? [];
  const current: Record<string, unknown> = {};
  for (const row of records) {
    // First occurrence wins: the list is already newest-first.
    if (!current[row.document]) {
      current[row.document] = {
        action: row.action,
        version: row.version,
        at: row.created_at,
        // A user who agreed to an older version has not agreed to this one.
        currentVersion: row.version === PRIVACY_POLICY_VERSION,
      };
    }
  }

  return c.json({ policyVersion: PRIVACY_POLICY_VERSION, current, records });
});

// GET /user/export — everything this API holds about the caller, as JSON.
//
// Secrets are excluded rather than exported: password_hash, refresh token
// hashes, stored card tokens and push tokens are credentials, not personal data
// the subject needs, and putting them in a file the user emails to themselves is
// how a data-subject request turns into an account takeover. What is left is
// theirs: profile, consent, places, ledger, trips, ratings, messages, documents.
userRoutes.get("/export", async (c) => {
  const user = c.get("user");
  const db = c.env.DB;

  const [
    profile,
    captain,
    consents,
    places,
    cards,
    devices,
    credits,
    ledger,
    trips,
    ratingsGiven,
    ratingsReceived,
    referrals,
    sos,
    messages,
    documents,
  ] = await db.batch([
    db.prepare(
      `SELECT id, email, name, phone, role, status, avatar_url, created_at, updated_at,
              wallet_balance, deleted_at FROM users WHERE id = ?`
    ).bind(user.id),
    db.prepare(`SELECT * FROM captains WHERE user_id = ?`).bind(user.id),
    db.prepare(
      `SELECT document, version, action, source, locale, created_at
         FROM user_consents WHERE user_id = ? ORDER BY created_at`
    ).bind(user.id),
    db.prepare(`SELECT id, label, lat, lng, address, created_at FROM saved_places WHERE user_id = ?`)
      .bind(user.id),
    // last4 only — the provider token is a payment credential.
    db.prepare(
      `SELECT id, type, provider, last4, active, created_at FROM payment_methods WHERE user_id = ?`
    ).bind(user.id),
    // Platform and recency only — the push token identifies the device to FCM.
    db.prepare(
      `SELECT id, platform, app_role, last_seen_at, created_at FROM device_tokens WHERE user_id = ?`
    ).bind(user.id),
    db.prepare(`SELECT balance, updated_at FROM user_credits WHERE user_id = ?`).bind(user.id),
    db.prepare(
      `SELECT id, type, direction, amount, currency, trip_id, note, status, created_at
         FROM wallet_transactions WHERE user_id = ? ORDER BY created_at`
    ).bind(user.id),
    db.prepare(
      `SELECT id, status, city, pickup_address, dropoff_address, distance_km, duration_min,
              currency, estimated_fare, final_fare, payment_method, created_at, completed_at,
              cancelled_at, cancel_reason,
              CASE WHEN rider_id = ? THEN 'rider' ELSE 'captain' END AS party
         FROM trips WHERE rider_id = ? OR captain_id = ? ORDER BY created_at`
    ).bind(user.id, user.id, user.id),
    db.prepare(
      `SELECT id, trip_id, to_user_id, score, comment, created_at FROM ratings WHERE from_user_id = ?`
    ).bind(user.id),
    db.prepare(
      `SELECT id, trip_id, score, comment, created_at FROM ratings WHERE to_user_id = ?`
    ).bind(user.id),
    db.prepare(
      `SELECT id, referrer_id, referred_id, reward_type, reward_value, status, created_at
         FROM referrals WHERE referrer_id = ? OR referred_id = ?`
    ).bind(user.id, user.id),
    db.prepare(
      `SELECT id, trip_id, lat, lng, reason, status, created_at, resolved_at
         FROM sos_alerts WHERE user_id = ?`
    ).bind(user.id),
    db.prepare(
      `SELECT id, trip_id, sender_role, body, created_at FROM trip_chat_messages WHERE sender_id = ?`
    ).bind(user.id),
    // Metadata only. The scans themselves are R2 objects and are served by the
    // admin document route; an export is a JSON document, not an archive.
    db.prepare(
      `SELECT id, type, status, holder_full_name, national_id_number, expires_at, created_at
         FROM driver_documents WHERE captain_id = ?`
    ).bind(user.id),
  ]);

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "user.data_exported",
    entityType: "user",
    entityId: user.id,
    ip: c.req.header("cf-connecting-ip") ?? null,
    userAgent: c.req.header("user-agent") ?? null,
  });

  const filename = `godrive-data-${user.id}-${nowIso().slice(0, 10)}.json`;
  // Content-Disposition so the apps and a browser both land a file rather than
  // rendering a wall of JSON.
  c.header("Content-Disposition", `attachment; filename="${filename}"`);
  return c.json({
    exportedAt: nowIso(),
    policyVersion: PRIVACY_POLICY_VERSION,
    subject: profile.results?.[0] ?? null,
    captainProfile: captain.results?.[0] ?? null,
    consents: consents.results ?? [],
    savedPlaces: places.results ?? [],
    paymentMethods: cards.results ?? [],
    devices: devices.results ?? [],
    credits: credits.results?.[0] ?? null,
    walletTransactions: ledger.results ?? [],
    trips: trips.results ?? [],
    ratingsGiven: ratingsGiven.results ?? [],
    ratingsReceived: ratingsReceived.results ?? [],
    referrals: referrals.results ?? [],
    sosAlerts: sos.results ?? [],
    chatMessages: messages.results ?? [],
    documents: documents.results ?? [],
    notIncluded: [
      "password_hash, refresh tokens, stored card tokens and push tokens — credentials, not subject data",
      "document image bytes — request them from support; the metadata is above",
    ],
  });
});

const deleteAccountSchema = z.object({
  reason: z.string().max(500).optional(),
});

// DELETE /user/account — erase the caller.
//
// Soft delete with identifier tombstoning, not a row delete: wallet_transactions,
// user_credits and trips all reference users(id), and four of those references
// are NOT NULL. Removing the row would either fail or cascade the ledger away,
// and the ledger has to keep balancing after an erasure. So the row survives and
// every identifier on it does not.
userRoutes.delete("/account", async (c) => {
  const user = c.get("user");
  const db = c.env.DB;

  // Body is optional here: a DELETE with no body is normal, and an absent body
  // must not read as a validation failure.
  let reason: string | null = null;
  if ((c.req.header("content-type") ?? "").includes("application/json")) {
    const body = await parseBody(c, deleteAccountSchema);
    if (isResponse(body)) return body;
    reason = body.reason ?? null;
  }

  // 1. Refuse mid-trip. Erasing a party while a trip is live strands the other.
  const placeholders = ACTIVE_TRIP_STATUSES.map(() => "?").join(",");
  const live = await db
    .prepare(
      `SELECT id FROM trips
        WHERE (rider_id = ? OR captain_id = ?) AND status IN (${placeholders}) LIMIT 1`
    )
    .bind(user.id, user.id, ...ACTIVE_TRIP_STATUSES)
    .first<{ id: string }>();
  if (live) {
    return c.json(
      { error: "Finish or cancel your active trip first", code: "ACTIVE_TRIP" },
      409,
    );
  }

  // 2. Refuse while money is owed in either direction. Deleting an account with
  //    a positive balance destroys the user's claim to it.
  //    `wallet_balance` is the live column: wallet.ts reads it at :20 and :105
  //    and writes it at :114. `wallet_balance_piastres` was backfilled once by
  //    0005 and is not maintained, so it is deliberately not consulted here — if
  //    a later task makes piastres authoritative, this guard has to move with it.
  const balanceRow = await db
    .prepare(`SELECT COALESCE(wallet_balance, 0) AS balance FROM users WHERE id = ?`)
    .bind(user.id)
    .first<{ balance: number }>();
  if ((balanceRow?.balance ?? 0) > 0) {
    return c.json(
      {
        error: "Withdraw your remaining balance before deleting your account",
        code: "BALANCE_OUTSTANDING",
        balance: balanceRow?.balance ?? 0,
      },
      409,
    );
  }

  // 3. Read every R2 key BEFORE the rows that name them are deleted. This is the
  //    step whose absence is F-25-04: FILES.delete existed only on the two avatar
  //    paths (:186 and :235 of this file), so identity documents were left in the
  //    bucket forever even when their rows went.
  const avatarRow = await db
    .prepare(`SELECT avatar_url FROM users WHERE id = ?`)
    .bind(user.id)
    .first<{ avatar_url: string | null }>();
  const docRows = await db
    .prepare(`SELECT r2_key FROM driver_documents WHERE captain_id = ?`)
    .bind(user.id)
    .all<{ r2_key: string }>();

  const r2Keys: string[] = [];
  if (avatarRow?.avatar_url) {
    const k = keyFromPublicPath(avatarRow.avatar_url);
    if (k) r2Keys.push(k);
  }
  for (const row of docRows.results ?? []) {
    if (row.r2_key) r2Keys.push(row.r2_key);
  }

  const ts = nowIso();

  // 4. One batch, so a partial erasure cannot be left behind by a mid-way error.
  await db.batch([
    // Identifiers off the users row. email is NOT NULL UNIQUE, so it is
    // tombstoned rather than nulled; password_hash goes so the credential dies
    // with the account.
    db.prepare(
      `UPDATE users
          SET email = ?, name = NULL, phone = NULL, avatar_url = NULL, password_hash = NULL,
              status = 'suspended', deleted_at = ?, deletion_reason = ?, updated_at = ?
        WHERE id = ?`
    ).bind(tombstoneEmail(user.id), ts, reason, ts, user.id),

    // The captain profile carries the heaviest identifiers in the schema: the
    // four-part legal name and national ID from 0015, the licence, and the last
    // known position. Approval state and ratings stay — they are not identifiers
    // and the trips that reference them still have to make sense.
    db.prepare(
      `UPDATE captains
          SET first_name = NULL, father_name = NULL, grandfather_name = NULL, family_name = NULL,
              birth_date = NULL, national_id_number = NULL, license_number = NULL,
              license_expiry = NULL, vehicle_plate = NULL,
              last_lat = NULL, last_lng = NULL, is_online = 0, updated_at = ?
        WHERE user_id = ?`
    ).bind(ts, user.id),

    // Home and work pins are among the most sensitive rows a rider owns.
    db.prepare(`DELETE FROM saved_places WHERE user_id = ?`).bind(user.id),
    // Stored payment credentials.
    db.prepare(`DELETE FROM payment_methods WHERE user_id = ?`).bind(user.id),
    // Stop every future push to this person's devices.
    db.prepare(`DELETE FROM device_tokens WHERE user_id = ?`).bind(user.id),
    // Identity scans: the rows go here, the R2 objects go below.
    db.prepare(`DELETE FROM driver_documents WHERE captain_id = ?`).bind(user.id),
    // End every live session. routes/auth.ts:285 refuses a refresh whose row has
    // revoked_at set, so this is what makes the erasure stick beyond the current
    // access token's lifetime.
    db.prepare(
      `UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL`
    ).bind(ts, user.id),

    // Any pending public request for this address is now satisfied.
    db.prepare(
      `UPDATE account_deletion_requests
          SET status = 'completed', completed_at = ?, user_id = COALESCE(user_id, ?)
        WHERE user_id = ? AND status = 'pending'`
    ).bind(ts, user.id, user.id),
  ]);

  // 5. Now the blobs. After the commit and best-effort: the personal data is
  //    already unreachable through the API, and a bucket hiccup must not leave
  //    the caller thinking their deletion failed. Anything that fails here is a
  //    reconcilable orphan — the procedure is in
  //    docs/legal/data-retention-and-erasure.md.
  for (const key of r2Keys) {
    try {
      await c.env.FILES.delete(key);
    } catch {
      // Orphaned object; the reconciliation sweep collects it.
    }
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "user.account_deleted",
    entityType: "user",
    entityId: user.id,
    payload: { reason, r2ObjectsDeleted: r2Keys.length, source: "in_app" },
    ip: c.req.header("cf-connecting-ip") ?? null,
    userAgent: c.req.header("user-agent") ?? null,
  });

  return c.json({
    ok: true,
    deletedAt: ts,
    // Named so the client can tell the user the truth rather than "all data
    // erased", which would not be true of the ledger.
    retained: [
      "financial ledger entries, attached to an anonymous id, for tax and audit obligations",
      "consent records, which are the evidence that this deletion was lawful",
      "safety reports and trip records shared with another party",
    ],
  });
});

// ===========================================================================
// Public, unauthenticated.  Mounted by E02 as:
//
//     app.route("/user", publicUserRoutes);   // BEFORE app.route("/user", userRoutes)
//
// Order matters: userRoutes applies authMiddleware to "*", so this app has to be
// matched first or the two routes below become 401s. Everything else under
// /user falls through to userRoutes because nothing here matches it.
//
// E02's brief names `POST /user/deletion-request`. The GET on the same path is
// the page a human can actually visit, which is what the stores ask for — one
// mount covers both, and index.ts freezes after E02.
// ===========================================================================

export const publicUserRoutes = new Hono<AppEnv>();

/// An HTML form posts urlencoded; the two apps post JSON. Accept both rather
/// than forcing a no-JS browser through a fetch() the page would have to carry.
async function readEmailField(
  c: Context<AppEnv>,
): Promise<{ email: string | null; note: string | null }> {
  const ctype = (c.req.header("content-type") ?? "").toLowerCase();
  try {
    if (ctype.includes("application/json")) {
      const raw = (await c.req.json()) as Record<string, unknown>;
      return {
        email: typeof raw.email === "string" ? raw.email : null,
        note: typeof raw.note === "string" ? raw.note : null,
      };
    }
    const form = await c.req.formData();
    const email = form.get("email");
    const note = form.get("note");
    return {
      email: typeof email === "string" ? email : null,
      note: typeof note === "string" ? note : null,
    };
  } catch {
    return { email: null, note: null };
  }
}

const EMAIL_RE = /^[^@\s]+@[^@\s.]+\.[^@\s]+$/;

// POST /user/deletion-request — record an erasure request from outside the app.
//
// This endpoint does NOT delete. It is unauthenticated, so acting on it directly
// would let anyone erase any account by typing an address. It records the intent
// for an operator, and answers identically whether or not the address matches an
// account — an endpoint that says "no such user" is an account-enumeration
// oracle sitting on the public internet.
publicUserRoutes.post(
  "/deletion-request",
  rateLimit({ prefix: "deletion-request", limit: 5, windowSec: 3600 }),
  async (c) => {
    const { email, note } = await readEmailField(c);
    const normalised = (email ?? "").trim().toLowerCase();

    const accepted = { ok: true, status: "received" as const };

    // Malformed input is answered like everything else. A 400 here would still
    // distinguish "valid address, no account" from "invalid address".
    if (!normalised || normalised.length > 254 || !EMAIL_RE.test(normalised)) {
      return c.json(accepted);
    }

    const match = await c.env.DB.prepare(`SELECT id FROM users WHERE email = ? AND deleted_at IS NULL`)
      .bind(normalised)
      .first<{ id: string }>();

    await c.env.DB.prepare(
      `INSERT INTO account_deletion_requests
         (id, email, user_id, status, source, note, ip, user_agent, requested_at)
       VALUES (?, ?, ?, 'pending', 'web', ?, ?, ?, ?)`
    )
      .bind(
        id("adr"),
        normalised,
        match?.id ?? null,
        note && note.length <= 500 ? note : null,
        c.req.header("cf-connecting-ip") ?? null,
        c.req.header("user-agent") ?? null,
        nowIso(),
      )
      .run();

    return c.json(accepted);
  },
);

/// The page a store reviewer opens. Self-contained: no CDN, no fonts, no
/// analytics — a privacy page that phones a third party on load is its own
/// finding. RTL first, with the English underneath.
const DELETION_PAGE_HTML = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>حذف حساب GoDrive · Delete your GoDrive account</title>
<style>
  :root { color-scheme: light dark; }
  body { margin:0; padding:2rem 1.25rem; font-family: system-ui, -apple-system, "Segoe UI", Tahoma, sans-serif;
         line-height:1.7; background:#f6f7f9; color:#14181f; }
  @media (prefers-color-scheme: dark) { body { background:#0f1216; color:#e8eaed; } .card { background:#171b21 !important; border-color:#2a2f37 !important; } input, textarea { background:#0f1216 !important; color:#e8eaed !important; border-color:#2a2f37 !important; } }
  .card { max-width:640px; margin:0 auto; background:#fff; border:1px solid #e3e6ea; border-radius:14px; padding:1.75rem; }
  h1 { font-size:1.4rem; margin:0 0 .25rem; }
  h2 { font-size:1.05rem; margin:1.75rem 0 .5rem; }
  p, li { font-size:.97rem; }
  ul { padding-inline-start:1.25rem; }
  label { display:block; font-weight:600; margin:1rem 0 .35rem; font-size:.95rem; }
  input, textarea { width:100%; box-sizing:border-box; padding:.7rem .8rem; border:1px solid #ccd2d9;
                    border-radius:9px; font:inherit; }
  button { margin-top:1.1rem; width:100%; padding:.8rem; border:0; border-radius:9px; background:#c62828;
           color:#fff; font:inherit; font-weight:700; cursor:pointer; }
  .en { margin-top:2rem; padding-top:1.5rem; border-top:1px solid #e3e6ea; direction:ltr; text-align:left; }
  .muted { opacity:.75; font-size:.88rem; }
</style>
</head>
<body>
<div class="card">
  <h1>حذف حساب GoDrive</h1>
  <p class="muted">يمكنك أيضًا الحذف من داخل التطبيق: الإعدادات ← الخصوصية والبيانات ← حذف الحساب.</p>

  <h2>ما الذي يُحذف</h2>
  <ul>
    <li>الاسم ورقم الهاتف والبريد الإلكتروني والصورة الشخصية.</li>
    <li>الأماكن المحفوظة ووسائل الدفع وإشعارات الأجهزة.</li>
    <li>صور الوثائق ورقم الرقم القومي (للكباتن).</li>
  </ul>

  <h2>ما الذي يُحتفظ به ولماذا</h2>
  <ul>
    <li>سجلات المحاسبة والرحلات المرتبطة بها — التزام ضريبي ومحاسبي، ومرتبطة بمُعرِّف مجهول بعد الحذف.</li>
    <li>سجل الموافقة — هو الدليل على أن الحذف تم بشكل قانوني.</li>
    <li>بلاغات الأمان والرحلات المشتركة مع طرف آخر.</li>
  </ul>

  <form method="POST" action="/user/deletion-request">
    <label for="email">البريد الإلكتروني المسجَّل</label>
    <input id="email" name="email" type="email" required autocomplete="email" placeholder="you@example.com">
    <label for="note">ملاحظة (اختياري)</label>
    <textarea id="note" name="note" rows="3" maxlength="500"></textarea>
    <button type="submit">إرسال طلب الحذف</button>
  </form>
  <p class="muted">سنؤكد الطلب على البريد المسجَّل قبل التنفيذ. لا تكشف هذه الصفحة ما إذا كان البريد مسجَّلًا لدينا.</p>

  <div class="en">
    <h1>Delete your GoDrive account</h1>
    <p class="muted">You can also delete in-app: Settings → Privacy &amp; data → Delete account.</p>
    <p><strong>Deleted:</strong> name, phone, email, photo, saved places, payment methods, device
       notification tokens, and (for captains) document images and national ID number.</p>
    <p><strong>Retained:</strong> financial ledger entries and their trips, attached to an anonymous id,
       for tax and audit obligations; consent records, which evidence that the deletion was lawful; and
       safety reports shared with another party.</p>
    <p class="muted">Submit the form above with your registered email. We confirm by email before acting.
       This page deliberately gives the same answer whether or not the address is registered.</p>
  </div>
</div>
</body>
</html>`;

// GET /user/deletion-request — the visitable page behind the store listing's
// "account deletion" URL. A POST-only endpoint satisfies neither a reviewer nor
// a user with a browser.
publicUserRoutes.get("/deletion-request", (c) =>
  c.html(DELETION_PAGE_HTML, 200, {
    "Cache-Control": "public, max-age=3600",
    "X-Content-Type-Options": "nosniff",
  }),
);
