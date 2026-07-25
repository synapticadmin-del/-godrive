import { Hono } from "hono";
import type { DbPricing, DbTrip, DbUser } from "../lib/types";
import { pricingUpdateSchema } from "../lib/schemas";
import { logAudit } from "../lib/audit";
import { nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";

export const adminRoutes = new Hono<AppEnv>();

adminRoutes.use("*", authMiddleware, requireRole("admin"));

adminRoutes.get("/stats", async (c) => {
  const users = await c.env.DB.prepare(
    `SELECT role, COUNT(*) as count FROM users GROUP BY role`,
  ).all<{ role: string; count: number }>();

  const tripsByStatus = await c.env.DB.prepare(
    `SELECT status, COUNT(*) as count FROM trips GROUP BY status`,
  ).all<{ status: string; count: number }>();

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const todayIso = today.toISOString();

  const todayStats = await c.env.DB.prepare(
    `SELECT COUNT(*) as trips,
            COALESCE(SUM(CASE WHEN status='completed' THEN final_fare ELSE 0 END),0) as gmv,
            COALESCE(SUM(CASE WHEN status='completed' THEN commission ELSE 0 END),0) as commission
     FROM trips WHERE datetime(created_at) >= datetime(?)`,
  )
    .bind(todayIso)
    .first<{ trips: number; gmv: number; commission: number }>();

  const onlineCaptains = await c.env.DB.prepare(
    `SELECT COUNT(*) as count FROM captains WHERE is_online = 1 AND approval_status = 'approved'`,
  ).first<{ count: number }>();

  const pendingCaptains = await c.env.DB.prepare(
    `SELECT COUNT(*) as count FROM captains WHERE approval_status = 'pending'`,
  ).first<{ count: number }>();

  return c.json({
    users: users.results ?? [],
    tripsByStatus: tripsByStatus.results ?? [],
    today: todayStats,
    onlineCaptains: onlineCaptains?.count ?? 0,
    pendingCaptains: pendingCaptains?.count ?? 0,
  });
});

adminRoutes.get("/live-trips", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT id, status, city, rider_id, captain_id,
            pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
            captain_lat, captain_lng, estimated_fare, created_at, updated_at
     FROM trips
     WHERE status NOT IN ('completed', 'cancelled')
     ORDER BY created_at DESC LIMIT 200`,
  ).all();
  return c.json({ trips: res.results ?? [] });
});

adminRoutes.get("/analytics", async (c) => {
  const from = c.req.query("from") || new Date(Date.now() - 30 * 864e5).toISOString();
  const to = c.req.query("to") || nowIso();

  // The admin UI sends date-only bounds ("2026-07-25"), while stored timestamps
  // carry a time component. Comparing "2026-07-25 14:03:00" <= "2026-07-25" is
  // false, which silently dropped the whole final day of every range.
  // For a date-only upper bound, move to the start of the NEXT day and compare
  // exclusively so the selected end date is fully included. A full timestamp is
  // already precise, so it is used as-is (shifting it would over-extend by a day).
  // The '+1 day' shift is applied by SQLite, so the bound value is passed
  // through unchanged; only the comparison form differs.
  const isDateOnly = /^\d{4}-\d{2}-\d{2}$/.test(to);
  const upperBound = isDateOnly
    ? `datetime(created_at) < datetime(?, '+1 day')`
    : `datetime(created_at) <= datetime(?)`;
  const upperBoundCompleted = isDateOnly
    ? `datetime(t.completed_at) < datetime(?, '+1 day')`
    : `datetime(t.completed_at) <= datetime(?)`;

  const daily = await c.env.DB.prepare(
    `SELECT date(created_at) as day,
            COUNT(*) as trips,
            SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed,
            COALESCE(SUM(CASE WHEN status='completed' THEN final_fare ELSE 0 END),0) as gmv,
            COALESCE(SUM(CASE WHEN status='completed' THEN commission ELSE 0 END),0) as commission
     FROM trips
     WHERE datetime(created_at) >= datetime(?) AND ${upperBound}
     GROUP BY date(created_at)
     ORDER BY day ASC`,
  )
    .bind(from, to)
    .all();

  const topCaptains = await c.env.DB.prepare(
    `SELECT t.captain_id as captain_id, u.name, u.email,
            COUNT(*) as trips,
            COALESCE(SUM(t.final_fare),0) as gmv
     FROM trips t
     JOIN users u ON u.id = t.captain_id
     WHERE t.status = 'completed' AND datetime(t.completed_at) >= datetime(?) AND ${upperBoundCompleted}
     GROUP BY t.captain_id
     ORDER BY trips DESC
     LIMIT 10`,
  )
    .bind(from, to)
    .all();

  const totals = await c.env.DB.prepare(
    `SELECT COUNT(*) as trips,
            SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed,
            SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) as cancelled,
            COALESCE(SUM(CASE WHEN status='completed' THEN final_fare ELSE 0 END),0) as gmv
     FROM trips WHERE datetime(created_at) >= datetime(?) AND ${upperBound}`,
  )
    .bind(from, to)
    .first<{ trips: number; completed: number; cancelled: number; gmv: number }>();

  const completionRate =
    totals && totals.trips > 0
      ? Math.round(((totals.completed ?? 0) / totals.trips) * 1000) / 10
      : 0;

  return c.json({
    from,
    to,
    totals: { ...totals, completionRate },
    daily: daily.results ?? [],
    topCaptains: topCaptains.results ?? [],
  });
});

adminRoutes.get("/audit-log", async (c) => {
  const limit = Math.min(Number(c.req.query("limit") || 100), 500);
  const res = await c.env.DB.prepare(
    `SELECT * FROM audit_log ORDER BY created_at DESC LIMIT ?`,
  )
    .bind(limit)
    .all();
  return c.json({ logs: res.results ?? [] });
});

adminRoutes.get("/captains", async (c) => {
  const status = c.req.query("status");
  // Clean stale online sessions older than 5 minutes.
  // last_seen_at is written via nowIso() ("2026-07-25T21:00:00.000Z") while
  // datetime('now', ...) yields "2026-07-25 21:00:00". A bytewise TEXT compare
  // put every ISO value above the threshold ('T' 0x54 > ' ' 0x20), so no stale
  // session was ever cleared. datetime() on both sides normalises the encodings.
  await c.env.DB.prepare(
    `UPDATE captains SET is_online = 0 WHERE is_online = 1 AND (last_seen_at IS NULL OR datetime(last_seen_at) < datetime('now', '-5 minutes'))`
  ).run();

  let sql = `
    SELECT c.*,
           CASE
             WHEN c.is_online = 1 AND (c.last_seen_at IS NOT NULL AND datetime(c.last_seen_at) >= datetime('now', '-5 minutes')) THEN 1
             ELSE 0
           END as is_online,
           u.email, u.name, u.phone, u.status as user_status, u.created_at as user_created_at
    FROM captains c JOIN users u ON u.id = c.user_id
  `;
  const binds: string[] = [];
  if (status) {
    sql += ` WHERE c.approval_status = ?`;
    binds.push(status);
  }
  sql += ` ORDER BY c.created_at DESC LIMIT 200`;

  const stmt = c.env.DB.prepare(sql);
  const res = binds.length ? await stmt.bind(...binds).all() : await stmt.all();
  return c.json({ captains: res.results ?? [] });
});

adminRoutes.post("/captains/:id/approve", async (c) => {
  const user = c.get("user");
  const userId = c.req.param("id");
  await c.env.DB.prepare(
    `UPDATE captains SET approval_status = 'approved', updated_at = ? WHERE user_id = ?`,
  )
    .bind(nowIso(), userId)
    .run();
  await c.env.DB.prepare(`UPDATE users SET status = 'active', updated_at = ? WHERE id = ?`)
    .bind(nowIso(), userId)
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "captain.approve",
    entityType: "captain",
    entityId: userId,
    ip: c.req.header("cf-connecting-ip"),
  });

  const captain = await c.env.DB.prepare(
    `SELECT c.*, u.email, u.name FROM captains c JOIN users u ON u.id = c.user_id WHERE c.user_id = ?`,
  )
    .bind(userId)
    .first();
  return c.json({ captain });
});

adminRoutes.post("/captains/:id/suspend", async (c) => {
  const user = c.get("user");
  const userId = c.req.param("id");
  await c.env.DB.prepare(
    `UPDATE captains SET approval_status = 'suspended', is_online = 0, updated_at = ? WHERE user_id = ?`,
  )
    .bind(nowIso(), userId)
    .run();
  await c.env.DB.prepare(`UPDATE users SET status = 'suspended', updated_at = ? WHERE id = ?`)
    .bind(nowIso(), userId)
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "captain.suspend",
    entityType: "captain",
    entityId: userId,
    ip: c.req.header("cf-connecting-ip"),
  });

  return c.json({ ok: true });
});

adminRoutes.get("/trips", async (c) => {
  const status = c.req.query("status");
  let sql = `SELECT * FROM trips`;
  const binds: string[] = [];
  if (status) {
    sql += ` WHERE status = ?`;
    binds.push(status);
  }
  sql += ` ORDER BY created_at DESC LIMIT 200`;
  const stmt = c.env.DB.prepare(sql);
  const res = binds.length ? await stmt.bind(...binds).all<DbTrip>() : await stmt.all<DbTrip>();
  return c.json({ trips: res.results ?? [] });
});

adminRoutes.get("/users", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT id, email, name, phone, role, status, created_at FROM users ORDER BY created_at DESC LIMIT 200`,
  ).all<DbUser>();
  return c.json({ users: res.results ?? [] });
});

adminRoutes.get("/pricing", async (c) => {
  const res = await c.env.DB.prepare(`SELECT * FROM pricing_rules ORDER BY city`).all<DbPricing>();
  return c.json({ pricing: res.results ?? [] });
});

adminRoutes.put("/pricing/:city", async (c) => {
  const user = c.get("user");
  const city = c.req.param("city").toLowerCase();
  const body = await parseBody(c, pricingUpdateSchema);
  if (isResponse(body)) return body;

  const existing = await c.env.DB.prepare(`SELECT * FROM pricing_rules WHERE city = ?`)
    .bind(city)
    .first<DbPricing>();

  if (!existing) {
    await c.env.DB.prepare(
      `INSERT INTO pricing_rules (city, currency, base_fare, per_km, per_min, booking_fee, min_fare, commission_rate)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        city,
        body.currency ?? "EGP",
        body.baseFare ?? 12,
        body.perKm ?? 4.5,
        body.perMin ?? 0.5,
        body.bookingFee ?? 3,
        body.minFare ?? 25,
        body.commissionRate ?? 0.2,
      )
      .run();
  } else {
    await c.env.DB.prepare(
      `UPDATE pricing_rules SET
        currency = COALESCE(?, currency),
        base_fare = COALESCE(?, base_fare),
        per_km = COALESCE(?, per_km),
        per_min = COALESCE(?, per_min),
        booking_fee = COALESCE(?, booking_fee),
        min_fare = COALESCE(?, min_fare),
        commission_rate = COALESCE(?, commission_rate),
        updated_at = ?
       WHERE city = ?`,
    )
      .bind(
        body.currency ?? null,
        body.baseFare ?? null,
        body.perKm ?? null,
        body.perMin ?? null,
        body.bookingFee ?? null,
        body.minFare ?? null,
        body.commissionRate ?? null,
        nowIso(),
        city,
      )
      .run();
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "pricing.update",
    entityType: "pricing_rules",
    entityId: city,
    payload: body,
    ip: c.req.header("cf-connecting-ip"),
  });

  const row = await c.env.DB.prepare(`SELECT * FROM pricing_rules WHERE city = ?`)
    .bind(city)
    .first<DbPricing>();
  return c.json({ pricing: row });
});

adminRoutes.get("/documents", async (c) => {
  const status = c.req.query("status");
  let sql = `
    SELECT d.*, u.name as captain_name, u.email as captain_email, u.phone as captain_phone
    FROM driver_documents d
    JOIN users u ON u.id = d.captain_id
  `;
  const binds: string[] = [];
  if (status) {
    sql += ` WHERE d.status = ?`;
    binds.push(status);
  }
  sql += ` ORDER BY d.created_at DESC LIMIT 200`;

  const stmt = c.env.DB.prepare(sql);
  const res = binds.length ? await stmt.bind(...binds).all() : await stmt.all();
  return c.json({ documents: res.results ?? [] });
});

adminRoutes.post("/documents/:id/review", async (c) => {
  const user = c.get("user");
  const docId = c.req.param("id");
  const body = await c.req.json().catch(() => ({}));
  const status = body.status === "approved" ? "approved" : "rejected";

  await c.env.DB.prepare(
    `UPDATE driver_documents SET status = ?, reviewed_by = ?, reviewed_at = ? WHERE id = ?`
  )
    .bind(status, user.id, nowIso(), docId)
    .run();

  const doc = await c.env.DB.prepare(`SELECT * FROM driver_documents WHERE id = ?`)
    .bind(docId)
    .first<{ captain_id: string }>();

  if (doc?.captain_id && status === "approved") {
    const pendingCount = await c.env.DB.prepare(
      `SELECT COUNT(*) as count FROM driver_documents WHERE captain_id = ? AND status != 'approved'`
    )
      .bind(doc.captain_id)
      .first<{ count: number }>();

    if ((pendingCount?.count ?? 0) === 0) {
      await c.env.DB.prepare(
        `UPDATE captains SET approval_status = 'approved', updated_at = ? WHERE user_id = ?`
      )
        .bind(nowIso(), doc.captain_id)
        .run();
    }
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: `document.${status}`,
    entityType: "driver_document",
    entityId: docId,
    ip: c.req.header("cf-connecting-ip"),
  });

  return c.json({ ok: true, status });
});


// GET /admin/documents/:id/file — serve the document file from R2 for admin review
adminRoutes.get("/documents/:id/file", async (c) => {
  const docId = c.req.param("id");
  const doc = await c.env.DB.prepare(`SELECT r2_key FROM driver_documents WHERE id = ?`)
    .bind(docId)
    .first<{ r2_key: string }>();
  if (!doc) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  const obj = await c.env.FILES.get(doc.r2_key);
  if (!obj) return c.json({ error: "File not found", code: "FILE_NOT_FOUND" }, 404);
  const headers = new Headers();
  headers.set("Content-Type", obj.httpMetadata?.contentType ?? "image/jpeg");
  headers.set("Cache-Control", "public, max-age=3600");
  return new Response(obj.body, { headers });
});

// GET /admin/online-captains — list online captains with live locations
adminRoutes.get("/online-captains", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT u.id, u.name, u.email, u.phone, c.is_online, c.last_lat, c.last_lng,
            c.vehicle_make, c.vehicle_model, c.vehicle_plate, c.rating_avg, c.approval_status,
            c.last_seen_at
     FROM captains c
     JOIN users u ON u.id = c.user_id
     WHERE c.is_online = 1 AND c.approval_status = 'approved'
       AND c.last_lat IS NOT NULL AND c.last_lng IS NOT NULL
     ORDER BY c.last_seen_at DESC LIMIT 200`,
  ).all();
  return c.json({ captains: res.results ?? [] });
});
