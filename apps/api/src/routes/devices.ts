import { Hono } from "hono";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";
import { deviceTokenSchema } from "../lib/schemas";

export const deviceRoutes = new Hono<AppEnv>();

deviceRoutes.use("*", authMiddleware);

// POST /user/device — register or refresh an FCM token for this user.
// Upsert on token (unique) so a re-install doesn't pile up duplicates.
deviceRoutes.post("/device", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, deviceTokenSchema);
  if (isResponse(body)) return body;

  await c.env.DB.prepare(
    `INSERT INTO device_tokens (id, user_id, token, platform, app_role, last_seen_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET
       user_id = excluded.user_id,
       platform = excluded.platform,
       app_role = excluded.app_role,
       last_seen_at = excluded.last_seen_at`,
  )
    .bind(id("dev"), user.id, body.token, body.platform, body.appRole ?? user.role, nowIso(), nowIso())
    .run();

  return c.json({ ok: true });
});

// DELETE /user/device — remove this device token (logout / app uninstall)
deviceRoutes.delete("/device", async (c) => {
  const user = c.get("user");
  const token = c.req.query("token");
  if (!token) return c.json({ error: "token required", code: "MISSING_TOKEN" }, 400);
  await c.env.DB.prepare(`DELETE FROM device_tokens WHERE token = ? AND user_id = ?`)
    .bind(token, user.id)
    .run();
  return c.json({ ok: true });
});