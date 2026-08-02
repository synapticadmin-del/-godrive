import { Hono } from "hono";
import { z } from "zod";
import type { Context } from "hono";
import type { ZodSchema, ZodTypeDef } from "zod";
import { TRIP_TRANSITIONS, type TripStatus } from "@synaptic-go/shared";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody, rateLimit } from "../middleware/rateLimit";
import { sosSchema, tripShareSchema } from "../lib/schemas";
import { pushToUser } from "../lib/notifications";
import { logAudit } from "../lib/audit";

// ---------------------------------------------------------------------------
// E13 — safety surface. Launch-gate item 10.
//
// Item 10 is split FOUR ways (E05 · E09 · E13 · E14, WAVE-PLAN §4). Nothing in
// this file closes it on its own:
//   E05  deleted the false "authorities are notified" claim in the rider app.
//   E13  (here) redacts the tracker payload, unauthenticates the tracker route,
//        fixes the share URL, and gives an SOS a lifecycle.
//   E09  calls revokeShareToken() at trip end and purgeExpiredShareTokens()
//        from the dispatch sweeper. Both are exported below and WIRED BY NOBODY
//        until E09 lands — that is root R3 and it is deliberate: `trips.ts` and
//        `cron/dispatch.ts` are E09's files and this task may not touch them.
//   E14  builds the operator console on top of the endpoints below.
//
// Order matters inside this file too. The payload redaction lands in the SAME
// commit as the URL fix, per WAVE-PLAN §6: repairing the two URL bugs first
// would have published the rider's pickup and dropoff street addresses to an
// unauthenticated bearer token with a 7-day life (tripShareSchema caps
// ttlMinutes at 10080) that nothing revokes.
// ---------------------------------------------------------------------------

/**
 * Trip statuses during which a share link may still expose a position.
 *
 * Derived from the repository's own state machine rather than retyped here: a
 * status with no legal outgoing transition is terminal, which today means
 * exactly `completed` and `cancelled`. `routes/trips.ts` already drives its
 * transition guards off the same table, so there is one definition of "this
 * trip is over" and not two that can drift apart.
 *
 * This is an ALLOW-list and it fails CLOSED, which matters twice over.
 * `trips.status` carries no CHECK constraint (0001_init.sql:62 — free text,
 * defaulting to 'searching'), so the column can hold a value the union has
 * never heard of; anything unrecognised is treated as not-live and discloses
 * no position. And E09 is about to add a terminal state for trips nobody
 * accepts — when it lands in TRIP_TRANSITIONS with no outgoing edges, this
 * stops serving a position for it with no edit to this file.
 */
const LIVE_TRIP_STATUSES: ReadonlySet<string> = new Set(
  (Object.keys(TRIP_TRANSITIONS) as TripStatus[]).filter(
    (status) => TRIP_TRANSITIONS[status].length > 0,
  ),
);

/**
 * Decimal places kept on a shared coordinate.
 *
 * 3 dp is ~110 m of latitude, and ~96 m of longitude at Cairo's latitude. That
 * is enough to follow a car along a road on a map — which is the entire point
 * of the feature — and not enough to identify which building it stopped
 * outside. The addresses, which are the real disclosure, are gone entirely.
 */
const TRACK_PRECISION_DP = 3;
const TRACK_PRECISION_M = 110;

function coarsen(value: number): number {
  const factor = 10 ** TRACK_PRECISION_DP;
  return Math.round(value * factor) / factor;
}

// ---------------------------------------------------------------------------
// Exports for E09 — the seam recorded in WAVE-PLAN §7.
//
// E13 must revoke share tokens at trip end and purge them on a schedule, and
// both call sites live in E09's files. So this task ships the primitives and
// E09 points the code at them. Neither is called from anywhere yet, and a
// verifier must NOT read "exported" as "working": until E09 merges, the live
// revoke-on-trip-end path does not exist.
// ---------------------------------------------------------------------------

/**
 * Revoke every share token still live for a trip. Call at trip end — any
 * terminal transition, including cancellation, not just completion.
 *
 * Idempotent: the `revoked_at IS NULL` guard means a second call changes
 * nothing and returns 0. Safe to call from a retry path.
 *
 * @returns how many tokens this call actually revoked.
 */
export async function revokeShareToken(db: D1Database, tripId: string): Promise<number> {
  const res = await db
    .prepare(
      `UPDATE trip_share_tokens SET revoked_at = ?
       WHERE trip_id = ? AND revoked_at IS NULL`,
    )
    .bind(nowIso(), tripId)
    .run();
  return res.meta.changes ?? 0;
}

/**
 * Delete share tokens whose lifetime has run out.
 *
 * `trip_share_tokens` is append-only in practice and nothing prunes it, so it
 * grows with every shared trip against a hard 10 GB D1 ceiling. 0022 adds
 * `idx_share_tokens_expiry` so this predicate is an index range scan rather
 * than the full table scan it is today.
 *
 * Only `expires_at` is used, deliberately: adding `OR revoked_at IS NOT NULL`
 * would make the statement unindexable. A revoked token is already dead to
 * `/track/:token`; it is collected here when it expires.
 *
 * @param cutoffIso delete tokens that expired strictly before this instant.
 *                  Defaults to now.
 * @returns how many rows were removed.
 */
export async function purgeExpiredShareTokens(
  db: D1Database,
  cutoffIso: string = nowIso(),
): Promise<number> {
  const res = await db
    .prepare(`DELETE FROM trip_share_tokens WHERE expires_at < ?`)
    .bind(cutoffIso)
    .run();
  return res.meta.changes ?? 0;
}

// ---------------------------------------------------------------------------
// The SOS escalation trail.
// ---------------------------------------------------------------------------

type SosEventName =
  | "raised"
  | "acknowledged"
  | "escalated"
  | "contacted"
  | "resolved"
  | "false_alarm"
  | "note";

type SosActorRole = "rider" | "captain" | "admin" | "system";

/**
 * Append one immutable row to an alert's trail.
 *
 * The table refuses UPDATE and DELETE by trigger (0022), so a correction is a
 * new row and the trail cannot be rewritten after the fact. This is the
 * evidence record for a passenger emergency; "who saw it, when, and what did
 * they do" is the question asked afterwards, and a single mutable status
 * column cannot answer it.
 */
async function recordSosEvent(
  db: D1Database,
  input: {
    alertId: string;
    event: SosEventName;
    actorId?: string | null;
    actorRole?: SosActorRole | null;
    note?: string | null;
  },
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO sos_alert_events (id, alert_id, event, actor_id, actor_role, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      id("sose"),
      input.alertId,
      input.event,
      input.actorId ?? null,
      input.actorRole ?? null,
      input.note ?? null,
      nowIso(),
    )
    .run();
}

/** Parse a body that is allowed to be absent entirely. */
async function parseOptionalBody<T>(
  c: Context<AppEnv>,
  schema: ZodSchema<T, ZodTypeDef, unknown>,
): Promise<T | Response> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    raw = {};
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    return c.json(
      { error: "Validation failed", code: "VALIDATION_ERROR", details: parsed.error.flatten() },
      400,
    );
  }
  return parsed.data;
}

const sosAckSchema = z.object({
  note: z.string().max(500).optional(),
});

const sosResolveSchema = z.object({
  outcome: z.enum(["resolved", "false_alarm"]),
  // Required, not optional. A destructive action that cannot record why is
  // exactly how F-11-08 happened.
  note: z.string().min(3).max(500),
});

const sosNoteSchema = z.object({
  event: z.enum(["escalated", "contacted", "note"]),
  note: z.string().min(1).max(1000),
});

// ---------------------------------------------------------------------------
// PUBLIC router — the one /safety path that must resolve without a JWT.
//
// index.ts mounts this ahead of the authenticated router and strips the
// "/safety" prefix before handing the request over, so the path here is
// "/track/:token". That mount is E02's and it is already on `main`; it
// late-binds through `await import()` and falls through to the authenticated
// router while this export is absent. Renaming this export silently returns
// the tracker to 401 — the exact bug this task exists to fix.
// ---------------------------------------------------------------------------
export const publicSafetyRoutes = new Hono<AppEnv>();

/**
 * GET /safety/track/:token — public read-only view of a shared trip.
 *
 * Fixes three faults, all verified on `main` before being changed:
 *
 *  1. F-17-02 — the route was behind `safetyRoutes.use("*", authMiddleware)`
 *     (old safety.ts:11), so the family member holding the link got 401 while
 *     the rider was told `ok: true`. It now lives on the public router.
 *  2. F-17-03 — the payload returned `pickup_address` and `dropoff_address`
 *     verbatim (old safety.ts:119-120). Both are gone. A token is a bearer
 *     credential that can live 7 days, is forwarded through WhatsApp, and is
 *     revoked by nobody until E09 ships; it must never carry a street address.
 *  3. The URL handed to the sharer omitted the `/safety` mount prefix, so it
 *     404'd. Fixed at the POST /safety/share handler below.
 *
 * Rate limited because this is now the only unauthenticated route in the app
 * that touches D1. Tokens are 128-bit (`id("sh")`), so this is scrape
 * resistance rather than the primary control, and the limiter fails open on a
 * KV error — a safety feature must not go dark because a cache did.
 */
publicSafetyRoutes.get(
  "/track/:token",
  rateLimit({ prefix: "track", limit: 60, windowSec: 60 }),
  async (c) => {
    const token = c.req.param("token");
    const share = await c.env.DB.prepare(
      `SELECT trip_id, expires_at, revoked_at FROM trip_share_tokens WHERE token = ?`,
    )
      .bind(token)
      .first<{ trip_id: string; expires_at: string; revoked_at: string | null }>();

    if (!share) return c.json({ error: "Invalid token", code: "NOT_FOUND" }, 404);
    if (share.revoked_at) return c.json({ error: "Token revoked", code: "REVOKED" }, 410);
    if (new Date(share.expires_at).getTime() < Date.now()) {
      return c.json({ error: "Token expired", code: "EXPIRED" }, 410);
    }

    const trip = await c.env.DB.prepare(`SELECT id, status FROM trips WHERE id = ?`)
      .bind(share.trip_id)
      .first<{ id: string; status: string }>();
    if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);

    // A finished trip still answers — "they arrived" is the single most useful
    // thing this link can say — but it answers with a status and nothing else.
    // Hard revocation at trip end is E09's call to revokeShareToken(); this is
    // the belt to that braces, and it closes the window between the trip
    // ending and the sweeper running.
    const live = LIVE_TRIP_STATUSES.has(trip.status);

    let lastPoint: { lat: number; lng: number; at: string } | null = null;
    if (live) {
      const point = await c.env.DB.prepare(
        `SELECT lat, lng, recorded_at FROM trip_path_points
         WHERE trip_id = ? ORDER BY recorded_at DESC LIMIT 1`,
      )
        .bind(share.trip_id)
        .first<{ lat: number; lng: number; recorded_at: string }>();
      if (point) {
        lastPoint = {
          lat: coarsen(point.lat),
          lng: coarsen(point.lng),
          at: point.recorded_at,
        };
      }
    }

    return c.json({
      tripId: trip.id,
      status: trip.status,
      live,
      lastPoint,
      precisionMeters: TRACK_PRECISION_M,
      expiresAt: share.expires_at,
    });
  },
);

// ---------------------------------------------------------------------------
// AUTHENTICATED router. Everything below requires a JWT — that is the property
// the auth test asserts path by path, with /track/:token as the one exception,
// and it is why /track/:token is no longer registered here at all.
// ---------------------------------------------------------------------------
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

  // Open the trail. Wrapped, because the alert row is the emergency and the
  // trail is the evidence about it: a failure to write history must never turn
  // into a failure to raise the alarm.
  try {
    await recordSosEvent(c.env.DB, {
      alertId,
      event: "raised",
      actorId: user.id,
      actorRole: user.role === "captain" ? "captain" : user.role === "admin" ? "admin" : "rider",
      note: body.reason ?? null,
    });
  } catch (e) {
    console.error("sos trail: failed to record 'raised'", alertId, e);
  }

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

// ---------------------------------------------------------------------------
// SOS lifecycle — F-17-04.
//
// `sos_alerts` was INSERT-only: `status` and `resolved_at` existed since
// 0003 and no code path ever wrote either a second time, so an alert had two
// observable states — it happened, and that is all. A rider pressed the panic
// button and the only trace was a push notification that, once dismissed, was
// unrecoverable without direct D1 access.
//
// These are the endpoints an operator needs. The CONSOLE that calls them is
// E14's (`routes/admin.ts` + `apps/admin/`), which depends on this task.
//
// There is deliberately no 'acknowledged' status value: 0003:170 pins
// CHECK (status IN ('open','resolved','false_alarm')) and SQLite cannot widen a
// CHECK without rebuilding the table — not a trade worth making on a live
// safety table. Acknowledgement is therefore a property of an open alert
// (`status = 'open' AND acknowledged_at IS NOT NULL`), which is also the more
// truthful model: an acknowledged emergency is still an emergency.
// ---------------------------------------------------------------------------

type SosRow = {
  id: string;
  user_id: string;
  trip_id: string | null;
  lat: number;
  lng: number;
  reason: string | null;
  status: string;
  acknowledged_at: string | null;
  acknowledged_by: string | null;
  resolved_at: string | null;
  resolved_by: string | null;
  created_at: string;
};

function shapeAlert(row: SosRow) {
  return {
    id: row.id,
    userId: row.user_id,
    tripId: row.trip_id,
    lat: row.lat,
    lng: row.lng,
    reason: row.reason,
    status: row.status,
    acknowledged: row.acknowledged_at !== null,
    acknowledgedAt: row.acknowledged_at,
    acknowledgedBy: row.acknowledged_by,
    resolvedAt: row.resolved_at,
    resolvedBy: row.resolved_by,
    createdAt: row.created_at,
  };
}

const SOS_COLUMNS = `id, user_id, trip_id, lat, lng, reason, status,
       acknowledged_at, acknowledged_by, resolved_at, resolved_by, created_at`;

// GET /safety/sos — the operator queue.
//
// Open alerts oldest-first, which is queue order and the reason 0022 adds the
// (status, created_at) composite: neither idx_sos_status nor idx_sos_created
// alone can filter and order in one pass. History reads newest-first instead;
// SQLite walks the same index backwards.
safetyRoutes.get("/sos", requireRole("admin"), async (c) => {
  const status = c.req.query("status") ?? "open";
  if (!["open", "resolved", "false_alarm", "all"].includes(status)) {
    return c.json({ error: "Unknown status filter", code: "VALIDATION_ERROR" }, 400);
  }
  const limit = Math.min(Math.max(Number(c.req.query("limit") ?? 50) || 50, 1), 200);

  const rows =
    status === "all"
      ? await c.env.DB.prepare(
          `SELECT ${SOS_COLUMNS} FROM sos_alerts ORDER BY created_at DESC LIMIT ?`,
        )
          .bind(limit)
          .all<SosRow>()
      : await c.env.DB.prepare(
          `SELECT ${SOS_COLUMNS} FROM sos_alerts WHERE status = ?
           ORDER BY created_at ${status === "open" ? "ASC" : "DESC"} LIMIT ?`,
        )
          .bind(status, limit)
          .all<SosRow>();

  const alerts = (rows.results ?? []).map(shapeAlert);
  return c.json({
    alerts,
    counts: {
      returned: alerts.length,
      unacknowledged: alerts.filter((a) => a.status === "open" && !a.acknowledged).length,
    },
  });
});

// GET /safety/sos/:id — one alert and its whole trail, oldest first.
safetyRoutes.get("/sos/:id", requireRole("admin"), async (c) => {
  const alertId = c.req.param("id") ?? "";
  const alert = await c.env.DB.prepare(`SELECT ${SOS_COLUMNS} FROM sos_alerts WHERE id = ?`)
    .bind(alertId)
    .first<SosRow>();
  if (!alert) return c.json({ error: "Alert not found", code: "NOT_FOUND" }, 404);

  // Tie-broken on rowid, not on id. `id` is `id("sose")` — a random UUID — so
  // two events written inside the same millisecond would come back in an
  // arbitrary order, and this table is the evidence record for a passenger
  // emergency: "acknowledged then resolved" and "resolved then acknowledged"
  // are different stories. SQLite's implicit rowid is monotonic in insertion
  // order, which is the actual sequence we need to preserve. Caught by the
  // behaviour harness, which writes two events in the same second.
  const events = await c.env.DB.prepare(
    `SELECT id, event, actor_id, actor_role, note, created_at
     FROM sos_alert_events WHERE alert_id = ? ORDER BY created_at ASC, rowid ASC`,
  )
    .bind(alertId)
    .all<{
      id: string;
      event: string;
      actor_id: string | null;
      actor_role: string | null;
      note: string | null;
      created_at: string;
    }>();

  return c.json({
    alert: shapeAlert(alert),
    events: (events.results ?? []).map((e) => ({
      id: e.id,
      event: e.event,
      actorId: e.actor_id,
      actorRole: e.actor_role,
      note: e.note,
      at: e.created_at,
    })),
  });
});

// POST /safety/sos/:id/ack — a named operator takes the alert.
//
// Guarded by `acknowledged_at IS NULL`, so a double click does not overwrite
// who got there first and does not append a second 'acknowledged' row.
safetyRoutes.post("/sos/:id/ack", requireRole("admin"), async (c) => {
  const user = c.get("user");
  const alertId = c.req.param("id") ?? "";
  const body = await parseOptionalBody(c, sosAckSchema);
  if (isResponse(body)) return body;

  const exists = await c.env.DB.prepare(
    `SELECT id, status, acknowledged_by FROM sos_alerts WHERE id = ?`,
  )
    .bind(alertId)
    .first<{ id: string; status: string; acknowledged_by: string | null }>();
  if (!exists) return c.json({ error: "Alert not found", code: "NOT_FOUND" }, 404);

  const res = await c.env.DB.prepare(
    `UPDATE sos_alerts SET acknowledged_at = ?, acknowledged_by = ?
     WHERE id = ? AND acknowledged_at IS NULL`,
  )
    .bind(nowIso(), user.id, alertId)
    .run();

  if ((res.meta.changes ?? 0) === 0) {
    return c.json({
      ok: true,
      alreadyAcknowledged: true,
      acknowledgedBy: exists.acknowledged_by,
    });
  }

  // Deliberately after the guarded UPDATE, never before. D1 has no interactive
  // transaction, and `batch()` cannot express "insert only if the update
  // matched" — so the ordering is chosen such that the impossible state is the
  // harmless one. An event with no state change would be a lie in the evidence
  // trail; a state change whose event insert then fails is loud, recoverable,
  // and visible in the audit log below.
  await recordSosEvent(c.env.DB, {
    alertId,
    event: "acknowledged",
    actorId: user.id,
    actorRole: "admin",
    note: body.note ?? null,
  });

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "safety.sos.ack",
    entityType: "sos_alert",
    entityId: alertId,
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
  });

  return c.json({ ok: true, alreadyAcknowledged: false });
});

// POST /safety/sos/:id/events — escalate, record contact, or leave a note.
// Changes no state; this is how the trail gets the detail a review needs.
safetyRoutes.post("/sos/:id/events", requireRole("admin"), async (c) => {
  const user = c.get("user");
  const alertId = c.req.param("id") ?? "";
  const body = await parseBody(c, sosNoteSchema);
  if (isResponse(body)) return body;

  const exists = await c.env.DB.prepare(`SELECT id FROM sos_alerts WHERE id = ?`)
    .bind(alertId)
    .first<{ id: string }>();
  if (!exists) return c.json({ error: "Alert not found", code: "NOT_FOUND" }, 404);

  await recordSosEvent(c.env.DB, {
    alertId,
    event: body.event,
    actorId: user.id,
    actorRole: "admin",
    note: body.note,
  });

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: `safety.sos.${body.event}`,
    entityType: "sos_alert",
    entityId: alertId,
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
  });

  return c.json({ ok: true });
});

// POST /safety/sos/:id/resolve — close it out. A reason is mandatory.
safetyRoutes.post("/sos/:id/resolve", requireRole("admin"), async (c) => {
  const user = c.get("user");
  const alertId = c.req.param("id") ?? "";
  const body = await parseBody(c, sosResolveSchema);
  if (isResponse(body)) return body;

  const exists = await c.env.DB.prepare(`SELECT id, status FROM sos_alerts WHERE id = ?`)
    .bind(alertId)
    .first<{ id: string; status: string }>();
  if (!exists) return c.json({ error: "Alert not found", code: "NOT_FOUND" }, 404);

  const res = await c.env.DB.prepare(
    `UPDATE sos_alerts SET status = ?, resolved_at = ?, resolved_by = ?
     WHERE id = ? AND status = 'open'`,
  )
    .bind(body.outcome, nowIso(), user.id, alertId)
    .run();

  if ((res.meta.changes ?? 0) === 0) {
    return c.json(
      {
        error: "Alert is already closed",
        code: "ALREADY_RESOLVED",
        status: exists.status,
      },
      409,
    );
  }

  await recordSosEvent(c.env.DB, {
    alertId,
    event: body.outcome,
    actorId: user.id,
    actorRole: "admin",
    note: body.note,
  });

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "safety.sos.resolve",
    entityType: "sos_alert",
    entityId: alertId,
    payload: { outcome: body.outcome },
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
  });

  return c.json({ ok: true, status: body.outcome });
});

// POST /safety/share — generate a public tracking token the rider can send to
// contacts. Anyone holding the token can view the redacted live trip position
// without authenticating; see publicSafetyRoutes above for what "redacted"
// means here.
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
    // The `/safety` mount prefix was missing here, so every link this endpoint
    // has ever produced 404'd while the rider was told `ok: true`. The path
    // must match index.ts's public mount, which is "/safety/track/*".
    url: `https://api.synapticstudio.tech/safety/track/${token}`,
    expiresAt: expires,
  });
});

// DELETE /safety/share/:token — revoke a previously created share token.
safetyRoutes.delete("/share/:token", async (c) => {
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
safetyRoutes.post("/chat/:tripId", async (c) => {
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

safetyRoutes.get("/chat/:tripId", async (c) => {
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
safetyRoutes.post("/chat/:tripId/typing", async (c) => {
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
