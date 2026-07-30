import { Hono } from "hono";
import type { DbPricing, DbTrip, DbUser } from "../lib/types";
import { pricingUpdateSchema, systemConfigUpdateSchema } from "../lib/schemas";
import { logAudit } from "../lib/audit";
import { intParam, jsonError, nowIso, pctDelta, previousPeriod } from "../lib/utils";
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

  const totalsSql = `SELECT COUNT(*) as trips,
            SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed,
            SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) as cancelled,
            COALESCE(SUM(CASE WHEN status='completed' THEN final_fare ELSE 0 END),0) as gmv,
            COALESCE(SUM(CASE WHEN status='completed' THEN commission ELSE 0 END),0) as commission
     FROM trips WHERE datetime(created_at) >= datetime(?) AND ${upperBound}`;

  const totals = await c.env.DB.prepare(totalsSql)
    .bind(from, to)
    .first<{
      trips: number;
      completed: number;
      cancelled: number;
      gmv: number;
      commission: number;
    }>();

  const completionRate =
    totals && totals.trips > 0
      ? Math.round(((totals.completed ?? 0) / totals.trips) * 1000) / 10
      : 0;

  // --- Previous-period comparison -----------------------------------------
  // The KPI cards previously rendered hard-coded literals ("+14.2%", "+8.5%",
  // "+3.1%") beneath the label "مقارنة بالفترة السابقة" (compared to the
  // previous period). No comparison was ever computed. These are the real
  // numbers behind that label.
  //
  // The comparison window must be the SAME LENGTH as the selected one and must
  // end exactly where it begins, otherwise the two are not comparable and the
  // delta is meaningless. Date-only bounds include the whole end day, so the
  // effective span is (to + 1 day) - from; a full timestamp is already exact.
  const prev = previousPeriod(from, to);

  let previousTotals: {
    trips: number;
    completed: number;
    cancelled: number;
    gmv: number;
    commission: number;
  } | null = null;

  if (prev) {
    // The previous window's upper bound is an exclusive instant (it is the
    // current window's start), so it always uses the `<` form regardless of
    // how the caller expressed `to`.
    previousTotals = await c.env.DB.prepare(
      `SELECT COUNT(*) as trips,
              SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed,
              SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) as cancelled,
              COALESCE(SUM(CASE WHEN status='completed' THEN final_fare ELSE 0 END),0) as gmv,
              COALESCE(SUM(CASE WHEN status='completed' THEN commission ELSE 0 END),0) as commission
       FROM trips
       WHERE datetime(created_at) >= datetime(?) AND datetime(created_at) < datetime(?)`,
    )
      .bind(prev.prevFrom, prev.prevToExclusive)
      .first<{
        trips: number;
        completed: number;
        cancelled: number;
        gmv: number;
        commission: number;
      }>();
  }

  const prevCompletionRate =
    previousTotals && previousTotals.trips > 0
      ? Math.round(((previousTotals.completed ?? 0) / previousTotals.trips) * 1000) / 10
      : 0;

  // pctDelta returns null when the baseline is zero and the current value is
  // not. A jump from nothing is not "infinity percent" — the UI renders those
  // as "جديد" (new) rather than inventing a number.
  const deltas = {
    trips: pctDelta(totals?.trips, previousTotals?.trips),
    completed: pctDelta(totals?.completed, previousTotals?.completed),
    gmv: pctDelta(totals?.gmv, previousTotals?.gmv),
    commission: pctDelta(totals?.commission, previousTotals?.commission),
    // Completion rate is already a percentage, so its change is reported in
    // percentage POINTS, not as a percentage-of-a-percentage. Mixing those two
    // is a classic dashboard lie.
    completionRatePoints:
      previousTotals === null
        ? null
        : Math.round((completionRate - prevCompletionRate) * 10) / 10,
  };

  return c.json({
    from,
    to,
    totals: { ...totals, completionRate },
    daily: daily.results ?? [],
    topCaptains: topCaptains.results ?? [],
    // `previous` is null when the range is unparseable or inverted. The UI must
    // treat null as "no comparison available" and show no delta at all, rather
    // than falling back to a placeholder figure.
    previous: prev
      ? {
          from: prev.prevFrom,
          to: prev.prevToExclusive,
          totals: { ...previousTotals, completionRate: prevCompletionRate },
        }
      : null,
    deltas,
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
           u.email, u.name, u.phone, u.avatar_url as avatar_url, u.status as user_status, u.created_at as user_created_at
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
    `SELECT c.*, u.email, u.name, u.phone, u.avatar_url as avatar_url FROM captains c JOIN users u ON u.id = c.user_id WHERE c.user_id = ?`,
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
    `SELECT id, email, name, phone, role, status, avatar_url, created_at FROM users ORDER BY created_at DESC LIMIT 200`,
  ).all<DbUser>();
  return c.json({ users: res.results ?? [] });
});

adminRoutes.get("/pricing", async (c) => {
  const res = await c.env.DB.prepare(`SELECT * FROM pricing_rules ORDER BY city`).all<DbPricing>();
  return c.json({ pricing: res.results ?? [] });
});

// Vehicle categories and their fare multipliers. The admin pricing screen used
// to hard-code a three-way economy/standard/comfort toggle that matched neither
// this table (economy/comfort/xl) nor any request it sent. Exposing the real
// rows lets that screen show the categories that actually affect fares.
adminRoutes.get("/vehicle-types", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT id, name, multiplier, active FROM vehicle_types WHERE active = 1 ORDER BY multiplier`,
  ).all<{ id: string; name: string; multiplier: number; active: number }>();
  return c.json({ vehicleTypes: res.results ?? [] });
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

// --- Platform system configuration -----------------------------------------
//
// Backs the "إعدادات وقواعد المنصة" tab in the admin dashboard. That form
// existed for several releases with a submit handler that only set a success
// message and never called the API, so the values never left the browser.
//
// Storage is the key/value system_config table (migration 0016). The API speaks
// camelCase to the client and snake_case to the database; SYSTEM_CONFIG_KEYS is
// the single place that mapping lives.
const SYSTEM_CONFIG_KEYS = {
  defaultCommissionPct: "default_commission_pct",
  searchRadiusKm: "search_radius_km",
  freeCancelMin: "free_cancel_min",
  cancelFeeEgp: "cancel_fee_egp",
  supportPhone: "support_phone",
  supportWhatsapp: "support_whatsapp",
  autoAssign: "auto_assign",
} as const;

type SystemConfigField = keyof typeof SYSTEM_CONFIG_KEYS;

interface DbSystemConfig {
  key: string;
  value: string;
  type: "string" | "number" | "boolean";
  description: string;
  updated_by: string | null;
  updated_at: string;
}

// system_config.value is TEXT for every setting; `type` tells us how to hand it
// back so the client gets a real number/boolean instead of a string it has to
// coerce (the old local-state form was typed, and the UI should not regress).
function coerceConfigValue(row: DbSystemConfig): string | number | boolean {
  if (row.type === "number") {
    const n = Number(row.value);
    return Number.isFinite(n) ? n : 0;
  }
  if (row.type === "boolean") return row.value === "true" || row.value === "1";
  return row.value;
}

function serialiseConfigValue(value: string | number | boolean): string {
  return typeof value === "boolean" ? String(value) : String(value);
}

adminRoutes.get("/system-config", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT key, value, type, description, updated_by, updated_at FROM system_config`,
  ).all<DbSystemConfig>();

  const rows = res.results ?? [];
  const byKey = new Map(rows.map((r) => [r.key, r]));

  // Always return the full set of known fields. A key missing from the table
  // (fresh database, or a setting added in code before its seed lands) would
  // otherwise leave the form field undefined and React would flip the input to
  // uncontrolled mid-edit.
  const config: Partial<Record<SystemConfigField, string | number | boolean>> = {};
  const meta: Record<string, { description: string; updatedAt: string | null }> = {};

  for (const [field, key] of Object.entries(SYSTEM_CONFIG_KEYS) as [SystemConfigField, string][]) {
    const row = byKey.get(key);
    if (!row) continue;
    config[field] = coerceConfigValue(row);
    meta[field] = { description: row.description, updatedAt: row.updated_at };
  }

  return c.json({ config, meta });
});

adminRoutes.put("/system-config", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, systemConfigUpdateSchema);
  if (isResponse(body)) return body;

  const entries = (Object.entries(SYSTEM_CONFIG_KEYS) as [SystemConfigField, string][]).filter(
    ([field]) => body[field] !== undefined,
  );

  if (entries.length === 0) {
    return jsonError("no recognised settings in request body", 400);
  }

  const now = nowIso();

  // Upsert rather than update: a setting introduced in code before its seed
  // migration ships should still be writable. The type is derived from the
  // validated value so a fresh row is coerced correctly on the next read.
  await c.env.DB.batch(
    entries.map(([field, key]) => {
      const value = body[field] as string | number | boolean;
      const type = typeof value === "number" ? "number" : typeof value === "boolean" ? "boolean" : "string";
      return c.env.DB.prepare(
        `INSERT INTO system_config (key, value, type, updated_by, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET
           value = excluded.value,
           type = excluded.type,
           updated_by = excluded.updated_by,
           updated_at = excluded.updated_at`,
      ).bind(key, serialiseConfigValue(value), type, user.id, now);
    }),
  );

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "system_config.update",
    entityType: "system_config",
    // The changed keys are the useful audit subject; there is no single row id.
    entityId: entries.map(([, key]) => key).join(","),
    payload: body,
    ip: c.req.header("cf-connecting-ip"),
  });

  const res = await c.env.DB.prepare(
    `SELECT key, value, type, description, updated_by, updated_at FROM system_config`,
  ).all<DbSystemConfig>();
  const byKey = new Map((res.results ?? []).map((r) => [r.key, r]));
  const config: Partial<Record<SystemConfigField, string | number | boolean>> = {};
  for (const [field, key] of Object.entries(SYSTEM_CONFIG_KEYS) as [SystemConfigField, string][]) {
    const row = byKey.get(key);
    if (row) config[field] = coerceConfigValue(row);
  }

  return c.json({ config, updated: entries.map(([field]) => field) });
});

// --- Global quick search ----------------------------------------------------
//
// The admin dashboard shipped a QuickSearchModal component that calls this path,
// but the endpoint was never implemented and the modal was never rendered, so
// the whole feature was dead on both ends. Implemented here to match the shape
// the existing component already expects: { results: { captains, riders, trips } }.
adminRoutes.get("/search", async (c) => {
  const q = (c.req.query("q") ?? "").trim();

  // Two characters is the floor where a LIKE scan is worth running at all; below
  // that every row matches and the response is noise.
  if (q.length < 2) {
    return c.json({ results: { captains: [], riders: [], trips: [] } });
  }

  // Bind the wildcards as part of the value so the pattern stays parameterised.
  const like = `%${q.replace(/[%_]/g, (ch) => `\\${ch}`)}%`;
  const PER_GROUP = 8;

  const [captains, riders, trips] = await Promise.all([
    c.env.DB.prepare(
      `SELECT u.id, u.name, u.email, u.phone, cp.vehicle_plate
         FROM users u
         JOIN captains cp ON cp.user_id = u.id
        WHERE u.role = 'captain'
          AND (u.name LIKE ? ESCAPE '\\' OR u.email LIKE ? ESCAPE '\\'
               OR u.phone LIKE ? ESCAPE '\\' OR cp.vehicle_plate LIKE ? ESCAPE '\\')
        ORDER BY u.created_at DESC
        LIMIT ?`,
    )
      .bind(like, like, like, like, PER_GROUP)
      .all<{ id: string; name: string | null; email: string; phone: string | null; vehicle_plate: string | null }>(),

    c.env.DB.prepare(
      `SELECT id, name, email, phone
         FROM users
        WHERE role = 'rider'
          AND (name LIKE ? ESCAPE '\\' OR email LIKE ? ESCAPE '\\' OR phone LIKE ? ESCAPE '\\')
        ORDER BY created_at DESC
        LIMIT ?`,
    )
      .bind(like, like, like, PER_GROUP)
      .all<{ id: string; name: string | null; email: string; phone: string | null }>(),

    // Trips are looked up by id prefix (what an operator pastes from a report)
    // or by city name.
    c.env.DB.prepare(
      `SELECT id, status, city, estimated_fare, created_at
         FROM trips
        WHERE id LIKE ? ESCAPE '\\' OR city LIKE ? ESCAPE '\\'
        ORDER BY created_at DESC
        LIMIT ?`,
    )
      .bind(like, like, PER_GROUP)
      .all<{ id: string; status: string; city: string; estimated_fare: number | null; created_at: string }>(),
  ]);

  return c.json({
    results: {
      captains: captains.results ?? [],
      riders: riders.results ?? [],
      trips: trips.results ?? [],
    },
  });
});

/*  Paged BY CAPTAIN, not by document. The verification UI groups documents into
 *  one accordion per captain and offers a bulk "approve all" per group, so a
 *  page boundary that splits one captain's paperwork across two pages would
 *  make that button silently approve only part of the file. Paging the captain
 *  list and then returning every matching document for the captains on the
 *  page keeps each group whole.
 *
 *  The previous implementation returned a flat `LIMIT 200` with no offset, so
 *  no document past the first 200 was reachable from the dashboard at all.  */
adminRoutes.get("/documents", async (c) => {
  const status = c.req.query("status");

  const page = Math.max(1, Number.parseInt(c.req.query("page") ?? "1", 10) || 1);
  const rawSize = Number.parseInt(c.req.query("pageSize") ?? "10", 10) || 10;
  const pageSize = Math.min(50, Math.max(1, rawSize));
  const offset = (page - 1) * pageSize;

  const where = status ? ` WHERE d.status = ?` : ``;
  const statusBind: string[] = status ? [status] : [];

  // Total is a count of captains (the paged unit), not of documents.
  const countRow = await (statusBind.length
    ? c.env.DB.prepare(
        `SELECT COUNT(DISTINCT d.captain_id) as total FROM driver_documents d
         JOIN users u ON u.id = d.captain_id${where}`,
      ).bind(...statusBind)
    : c.env.DB.prepare(
        `SELECT COUNT(DISTINCT d.captain_id) as total FROM driver_documents d
         JOIN users u ON u.id = d.captain_id`,
      )
  ).first<{ total: number }>();
  const total = countRow?.total ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  // The captains on this page, most recently active first.
  const idsRes = await c.env.DB.prepare(
    `SELECT d.captain_id as captain_id, MAX(d.created_at) as last_doc
     FROM driver_documents d
     JOIN users u ON u.id = d.captain_id${where}
     GROUP BY d.captain_id
     ORDER BY last_doc DESC
     LIMIT ? OFFSET ?`,
  )
    .bind(...statusBind, pageSize, offset)
    .all<{ captain_id: string }>();

  const captainIds = (idsRes.results ?? []).map((r) => r.captain_id);
  if (captainIds.length === 0) {
    return c.json({ documents: [], page, pageSize, total, totalPages });
  }

  // d.* carries the identity metadata added in migration 0012
  // (holder_full_name, national_id_number, expires_at), so the verification UI
  // can render it beside each document image with no extra query.
  const placeholders = captainIds.map(() => "?").join(", ");
  const res = await c.env.DB.prepare(
    `SELECT d.*, u.name as captain_name, u.email as captain_email, u.phone as captain_phone, u.avatar_url as captain_avatar_url,
            COALESCE(t.title_ar, d.type) as type_title_ar,
            COALESCE(t.title_en, '') as type_title_en
     FROM driver_documents d
     JOIN users u ON u.id = d.captain_id
     LEFT JOIN document_types t ON t.id = d.type
     WHERE d.captain_id IN (${placeholders})${status ? ` AND d.status = ?` : ``}
     ORDER BY d.created_at DESC`,
  )
    .bind(...captainIds, ...statusBind)
    .all();

  return c.json({ documents: res.results ?? [], page, pageSize, total, totalPages });
});

/* ------------------------------------------------------------------ */
/*  Document type catalog (admin-managed)                              */
/*                                                                     */
/*  The captain app's onboarding grid renders whatever this catalog    */
/*  returns, so adding a new required document (تأمين السيارة, شهادة   */
/*  صحية, …) is an admin action — not an app release. Deactivating a   */
/*  type hides it from new uploads but keeps every historical row.     */
/* ------------------------------------------------------------------ */

adminRoutes.get("/document-types", async (c) => {
  const rows = await c.env.DB.prepare(
    `SELECT * FROM document_types ORDER BY sort_order ASC, id ASC`,
  ).all();
  return c.json({ types: rows.results ?? [] });
});

adminRoutes.post("/document-types", async (c) => {
  const user = c.get("user");
  const body = await c.req.json().catch(() => ({}));

  const docId = typeof body.id === "string" ? body.id.trim() : "";
  const titleAr = typeof body.titleAr === "string" ? body.titleAr.trim() : "";
  if (!docId || !titleAr) {
    return c.json({ error: "id and titleAr are required", code: "MISSING_FIELDS" }, 400);
  }
  // Machine ids are what driver_documents.type stores — keep them URL/icon safe.
  if (!/^[a-z][a-z0-9_]{1,48}$/.test(docId)) {
    return c.json(
      { error: "id must be lowercase letters, digits and underscores (e.g. 'car_insurance')", code: "BAD_ID" },
      400,
    );
  }

  const existing = await c.env.DB.prepare(`SELECT id FROM document_types WHERE id = ?`)
    .bind(docId)
    .first();
  if (existing) {
    return c.json({ error: "Document type id already exists", code: "DUPLICATE_ID" }, 409);
  }

  await c.env.DB.prepare(
    `INSERT INTO document_types (id, title_ar, title_en, icon, required, sort_order, active)
     VALUES (?, ?, ?, ?, ?, ?, 1)`,
  )
    .bind(
      docId,
      titleAr,
      typeof body.titleEn === "string" ? body.titleEn.trim() : "",
      typeof body.icon === "string" && body.icon.trim() ? body.icon.trim() : "description",
      body.required === false ? 0 : 1,
      Number.isFinite(Number(body.sortOrder)) ? Number(body.sortOrder) : 100,
    )
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "document_type.create",
    entityType: "document_type",
    entityId: docId,
    payload: JSON.stringify({ titleAr }),
    ip: c.req.header("cf-connecting-ip"),
  });

  const row = await c.env.DB.prepare(`SELECT * FROM document_types WHERE id = ?`).bind(docId).first();
  return c.json({ type: row });
});

adminRoutes.put("/document-types/:id", async (c) => {
  const user = c.get("user");
  const typeId = c.req.param("id");
  const body = await c.req.json().catch(() => ({}));

  const existing = await c.env.DB.prepare(`SELECT * FROM document_types WHERE id = ?`)
    .bind(typeId)
    .first<{ id: string }>();
  if (!existing) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);

  await c.env.DB.prepare(
    `UPDATE document_types SET
       title_ar = COALESCE(?, title_ar),
       title_en = COALESCE(?, title_en),
       icon = COALESCE(?, icon),
       required = COALESCE(?, required),
       sort_order = COALESCE(?, sort_order),
       active = COALESCE(?, active),
       updated_at = ?
     WHERE id = ?`,
  )
    .bind(
      typeof body.titleAr === "string" ? body.titleAr.trim() : null,
      typeof body.titleEn === "string" ? body.titleEn.trim() : null,
      typeof body.icon === "string" && body.icon.trim() ? body.icon.trim() : null,
      typeof body.required === "boolean" ? (body.required ? 1 : 0) : null,
      Number.isFinite(Number(body.sortOrder)) ? Number(body.sortOrder) : null,
      typeof body.active === "boolean" ? (body.active ? 1 : 0) : null,
      nowIso(),
      typeId,
    )
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "document_type.update",
    entityType: "document_type",
    entityId: typeId,
    payload: JSON.stringify(body),
    ip: c.req.header("cf-connecting-ip"),
  });

  const row = await c.env.DB.prepare(`SELECT * FROM document_types WHERE id = ?`).bind(typeId).first();
  return c.json({ type: row });
});

// Deletion is a soft delete: driver_documents rows reference the type id, so a
// hard delete would orphan history. Active=0 removes it from every client.
adminRoutes.delete("/document-types/:id", async (c) => {
  const user = c.get("user");
  const typeId = c.req.param("id");

  const existing = await c.env.DB.prepare(`SELECT id FROM document_types WHERE id = ?`)
    .bind(typeId)
    .first();
  if (!existing) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);

  await c.env.DB.prepare(`UPDATE document_types SET active = 0, updated_at = ? WHERE id = ?`)
    .bind(nowIso(), typeId)
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "document_type.deactivate",
    entityType: "document_type",
    entityId: typeId,
    ip: c.req.header("cf-connecting-ip"),
  });

  return c.json({ ok: true });
});

adminRoutes.post("/documents/:id/review", async (c) => {
  const user = c.get("user");
  const docId = c.req.param("id");
  const body = await c.req.json().catch(() => ({}));
  const status = body.status === "approved" ? "approved" : "rejected";
  const rejectionReason = status === "rejected" ? (body.reason || null) : null;

  await c.env.DB.prepare(
    `UPDATE driver_documents SET status = ?, rejection_reason = COALESCE(?, rejection_reason), reviewed_by = ?, reviewed_at = ? WHERE id = ?`
  )
    .bind(status, rejectionReason, user.id, nowIso(), docId)
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
    payload: body.reason ? JSON.stringify({ reason: body.reason }) : undefined,
    ip: c.req.header("cf-connecting-ip"),
  });

  return c.json({ ok: true, status });
});

// POST /admin/captains/:id/documents/:docId/reject - Reject a document with a reason payload
adminRoutes.post("/captains/:id/documents/:docId/reject", async (c) => {
  const user = c.get("user");
  const captainId = c.req.param("id");
  const docId = c.req.param("docId");
  const body = await c.req.json().catch(() => ({}));
  const reason = body.reason || "تم الرفض بواسطة المشرف";

  await c.env.DB.prepare(
    `UPDATE driver_documents SET status = 'rejected', rejection_reason = ?, reviewed_by = ?, reviewed_at = ? WHERE id = ? AND captain_id = ?`
  )
    .bind(reason, user.id, nowIso(), docId, captainId)
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "document.rejected",
    entityType: "driver_document",
    entityId: docId,
    payload: JSON.stringify({ captainId, reason }),
    ip: c.req.header("cf-connecting-ip"),
  });

  return c.json({ ok: true, status: "rejected", reason });
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
    `SELECT u.id, u.name, u.email, u.phone, u.avatar_url as avatar_url, c.is_online, c.last_lat, c.last_lng,
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
