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
    `SELECT id, email, name, phone, role, status, created_at FROM users WHERE id = ?`
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
    `SELECT id, email, name, phone, role, status, created_at FROM users WHERE id = ?`
  )
    .bind(user.id)
    .first<DbUser>();

  return c.json({ user: updated });
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
