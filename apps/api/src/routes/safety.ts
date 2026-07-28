import { Hono } from "hono";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";
import { sosSchema, tripShareSchema } from "../lib/schemas";
import { pushToUser } from "../lib/notifications";
import { logAudit } from "../lib/audit";

export const safetyRoutes = new Hono<AppEnv>();

safetyRoutes.use("*", authMiddleware);

// POST /safety/sos — rider/captain triggers an SOS alert. Notifies support +
// (optionally) emergency contacts and logs to sos_alerts.
safetyRoutes.post("/sos", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, sosSchema);
  if (isResponse(body)) return body;

  const alertId = id("sos");
  await c.env.DB.prepare(
    `INSERT INTO sos_alerts (id, user_id, trip_id, lat, lng, reason, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'open', datetime('now'))`,
  )
    .bind(alertId, user.id, body.tripId ?? null, body.lat, body.lng, body.reason ?? null)
    .run();

  // Notify support admins about the SOS alert.
  const admins = await c.env.DB.prepare(`SELECT id FROM users WHERE role = 'admin'`).all<{ id: string }>();
  for (const admin of admins.results ?? []) {
    await pushToUser({
      env: c.env,
      userId: admin.id,
      topic: "sos.new",
      title: "إنذار طوارئ جديد",
      body: `تنبيه SOS من ${user.role} (${user.id.slice(0, 8)}). تحقق فورًا.`,
      data: { alertId, lat: String(body.lat), lng: String(body.lng) },
    });
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "safety.sos",
    entityType: "sos_alert",
    entityId: alertId,
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
  });

  return c.json({ ok: true, alertId, message: "تم استلام تنبيه الطوارئ" });
});

// POST /safety/share — generate a public tracking token the rider can send to
// contacts. Anyone holding the token can view the live trip location without
// authenticating.
safetyRoutes.post("/share", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, tripShareSchema);
  if (isResponse(body)) return body;

  const trip = await c.env.DB.prepare(
    `SELECT id, status, rider_id, captain_id FROM trips WHERE id = ?`,
  )
    .bind(body.tripId)
    .first<{ id: string; status: string; rider_id: string; captain_id: string | null }>();
  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
  if (trip.rider_id !== user.id && trip.captain_id !== user.id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const token = id("sh");
  const expires = new Date(Date.now() + body.ttlMinutes * 60 * 1000).toISOString();
  await c.env.DB.prepare(
    `INSERT INTO trip_share_tokens (token, trip_id, created_by, expires_at, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(token, trip.id, user.id, expires, nowIso())
    .run();

  return c.json({
    ok: true,
    token,
    url: `https://api.synapticstudio.tech/track/${token}`,
    expiresAt: expires,
  });
});

// GET /track/:token — public read-only view for shared trips.
// Returns only the trip status + last path point (lat/lng), no PII.
safetyRoutes.get("/track/:token", async (c) => {
  const token = c.req.param("token");
  const share = await c.env.DB.prepare(
    `SELECT id, trip_id, expires_at, revoked_at FROM trip_share_tokens WHERE token = ?`,
  )
    .bind(token)
    .first<{ id: string; trip_id: string; expires_at: string; revoked_at: string | null }>();
  if (!share) return c.json({ error: "Invalid token", code: "NOT_FOUND" }, 404);
  if (share.revoked_at) return c.json({ error: "Token revoked", code: "REVOKED" }, 410);
  if (new Date(share.expires_at).getTime() < Date.now()) {
    return c.json({ error: "Token expired", code: "EXPIRED" }, 410);
  }

  const trip = await c.env.DB.prepare(
    `SELECT id, status, pickup_address, dropoff_address, vehicle_type_id FROM trips WHERE id = ?`,
  )
    .bind(share.trip_id)
    .first<{ id: string; status: string; pickup_address: string; dropoff_address: string; vehicle_type_id: string | null }>();
  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);

  const lastPoint = await c.env.DB.prepare(
    `SELECT lat, lng, recorded_at FROM trip_path_points WHERE trip_id = ? ORDER BY recorded_at DESC LIMIT 1`,
  )
    .bind(share.trip_id)
    .first<{ lat: number; lng: number; recorded_at: string }>();

  return c.json({
    tripId: trip.id,
    status: trip.status,
    pickup: trip.pickup_address,
    dropoff: trip.dropoff_address,
    lastPoint,
  });
});

// DELETE /safety/share/:token — revoke a previously created share token.
safetyRoutes.delete("/share/:token", authMiddleware, async (c) => {
  const user = c.get("user");
  const token = c.req.param("token");
  const res = await c.env.DB.prepare(
    `UPDATE trip_share_tokens SET revoked_at = ? WHERE token = ? AND created_by = ?`,
  )
    .bind(nowIso(), token, user.id)
    .run();
  if (res.meta.changes === 0) return c.json({ error: "Token not found", code: "NOT_FOUND" }, 404);
  return c.json({ ok: true });
});

// In-call anonymous chat — messages are attached to a trip; no phone numbers
// exchanged. Rider and captain POST a text; both GET history.
safetyRoutes.post("/chat/:tripId", authMiddleware, async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("tripId") ?? "";
  const body = (await c.req.json().catch(() => ({}))) as { body?: string };
  const messageBody: string = (() => {
    const raw = body.body;
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 1000) {
      throw new Error("invalid");
    }
    return raw;
  })();
  if (messageBody.length === 0) {
    return c.json({ error: "Invalid message body", code: "VALIDATION_ERROR" }, 400);
  }
  const trip = await c.env.DB.prepare(
    `SELECT rider_id, captain_id, status FROM trips WHERE id = ?`,
  )
    .bind(tripId)
    .first<{ rider_id: string; captain_id: string | null; status: string }>();
  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
  if (user.id !== trip.rider_id && user.id !== trip.captain_id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }
  const senderRole = user.id === trip.rider_id ? "rider" : "captain";
  const msgId = id("cht");
  const createdAt = nowIso();
  await c.env.DB.prepare(
    `INSERT INTO trip_chat_messages (id, trip_id, sender_id, sender_role, body, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(msgId, tripId, user.id, senderRole, messageBody, createdAt)
    .run();

  // Live fan-out: push the message into the trip's WebSocket room so the
  // other party's app renders it immediately. Both apps subscribe to the
  // room for the active trip; without this the message existed only in D1
  // and the captain (whose app previously had no chat surface at all) saw
  // nothing until a manual refresh — the "رسايل الراكب مش بتظهر" bug.
  try {
    const room = c.env.TRIP_ROOM.get(c.env.TRIP_ROOM.idFromName(tripId));
    await room.fetch("https://room/broadcast", {
      method: "POST",
      body: JSON.stringify({
        type: "chat.message",
        tripId,
        msgId,
        senderId: user.id,
        senderRole,
        body: messageBody,
        at: createdAt,
      }),
    });
  } catch (e) {
    // Chat must never fail because the live channel hiccuped — the message
    // is already persisted and the push below still goes out.
    console.error("chat broadcast failed", tripId, e);
  }

  // Push the other party so they open the chat even with the app closed.
  const recipientIdRaw: string | null | undefined =
    senderRole === "rider" ? trip.captain_id : trip.rider_id;
  if (recipientIdRaw) {
    await pushToUser({
      env: c.env,
      userId: recipientIdRaw as string,
      topic: "trip.chat",
      title: "رسالة جديدة",
      body: messageBody.slice(0, 80),
      data: { tripId, msgId },
    });
  }
  return c.json({ ok: true, id: msgId });
});

safetyRoutes.get("/chat/:tripId", authMiddleware, async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("tripId") ?? "";

  const trip = await c.env.DB.prepare(`SELECT rider_id, captain_id FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<{ rider_id: string; captain_id: string }>();

  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);

  if (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const limit = Math.min(Number(c.req.query("limit") ?? 100), 200);
  const msgs = await c.env.DB.prepare(
    `SELECT id, sender_id, sender_role, body, read_at, created_at
     FROM trip_chat_messages WHERE trip_id = ? ORDER BY created_at DESC LIMIT ?`,
  )
    .bind(tripId, limit)
    .all();
  // Mark as read for this user
  if (msgs.results?.length) {
    await c.env.DB.prepare(
      `UPDATE trip_chat_messages SET read_at = COALESCE(read_at, ?)
       WHERE trip_id = ? AND sender_id != ? AND read_at IS NULL`,
    )
      .bind(nowIso(), tripId, user.id)
      .run();
  }
  return c.json({ messages: msgs.results ?? [] });
});

// POST /safety/chat/:tripId/typing — relay a "جاري الكتابة" (typing) signal
// to the trip's WebSocket room so the other party sees the composer is alive.
//
// Typing is ephemeral by design: nothing is stored, nothing is pushed via
// FCM, and a failed broadcast is swallowed — the indicator self-expires on
// the client after a few seconds, so a lost signal simply means no bubble,
// never a stuck one. The client's own events carry its role, and each app
// suppresses its own role on receipt, so the sender never sees its own
// indicator echoed back.
safetyRoutes.post("/chat/:tripId/typing", authMiddleware, async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("tripId") ?? "";
  const body = (await c.req.json().catch(() => ({}))) as { typing?: unknown };
  const typing = body.typing === true;

  const trip = await c.env.DB.prepare(
    `SELECT rider_id, captain_id FROM trips WHERE id = ?`,
  )
    .bind(tripId)
    .first<{ rider_id: string; captain_id: string | null }>();
  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
  if (user.id !== trip.rider_id && user.id !== trip.captain_id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const senderRole = user.id === trip.rider_id ? "rider" : "captain";
  try {
    const room = c.env.TRIP_ROOM.get(c.env.TRIP_ROOM.idFromName(tripId));
    await room.fetch("https://room/broadcast", {
      method: "POST",
      body: JSON.stringify({
        type: "chat.typing",
        tripId,
        senderId: user.id,
        senderRole,
        typing,
        at: nowIso(),
      }),
    });
  } catch (e) {
    // Best-effort: a typing hint is never worth a failed request.
    console.error("typing broadcast failed", tripId, e);
  }
  return c.json({ ok: true });
});
