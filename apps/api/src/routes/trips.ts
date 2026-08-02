import { Hono } from "hono";
import { canTransition, type TripStatus } from "@synaptic-go/shared";
import type { Context } from "hono";
import { pricingFromRow } from "../lib/pricing";
import { findNearbyCaptains } from "../lib/nearby";
import {
  fareFromRoute,
  getDurationsToPoint,
  getRoute,
  resolveOsrmBaseUrl,
  RouteUnavailableError,
  type RouteResult,
} from "../lib/routing";
import { dispatchTrip } from "../lib/dispatch";
import {
  resolveTripSettlement,
  settleTripCompletion,
  type SettlementTrip,
} from "../lib/settlement";
import {
  createTripSchema,
  estimateTripSchema,
  cancelTripSchema,
  rateTripSchema,
  createBidSchema,
  acceptBidSchema,
} from "../lib/schemas";
import type { DbCaptain, DbPricing, DbTrip } from "../lib/types";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody, rateLimit } from "../middleware/rateLimit";
import { pushToUser } from "../lib/notifications";
import { counter, logWarn } from "../lib/log";
import { getRequestId } from "../middleware/requestId";
import { revokeShareToken } from "./safety";

export const tripRoutes = new Hono<AppEnv>();

async function getPricing(db: D1Database, city: string): Promise<DbPricing | null> {
  return (
    (await db
      .prepare(`SELECT * FROM pricing_rules WHERE city = ?`)
      .bind(city)
      .first<DbPricing>()) ??
    (await db.prepare(`SELECT * FROM pricing_rules WHERE city = 'cairo'`).first<DbPricing>())
  );
}

async function logEvent(
  db: D1Database,
  tripId: string,
  type: string,
  actorId?: string,
  payload?: unknown,
) {
  await db
    .prepare(
      `INSERT INTO trip_events (id, trip_id, actor_id, type, payload) VALUES (?, ?, ?, ?, ?)`,
    )
    .bind(id("evt"), tripId, actorId ?? null, type, payload ? JSON.stringify(payload) : null)
    .run();
}

/**
 * The captain half of an assigned trip.
 *
 * `trips` stores a bare `captain_id`; every human-readable fact about the
 * person driving to the rider lives in `users` and `captains`. Until this
 * existed, `GET /trips/:id` and every `trip.updated` broadcast shipped the raw
 * row, so the rider's driver card had no data source at all — it is gated on
 * `captain_name`, which never arrived, so the card never rendered once a trip
 * was assigned. `GET /trips/:id/bids` already did this JOIN, but that endpoint
 * stops being reachable the moment the bid is accepted, which is precisely
 * when the rider most wants to know who is coming.
 */
export type TripCaptainFacts = {
  captain_name: string | null;
  captain_phone: string | null;
  captain_avatar_url: string | null;
  vehicle_make: string | null;
  vehicle_model: string | null;
  vehicle_plate: string | null;
  vehicle_color: string | null;
  vehicle_year: number | null;
  rating_avg: number | null;
  rating_count: number | null;
  captain_trips_count: number | null;
};

export type TripWithCaptain = DbTrip & Partial<TripCaptainFacts>;

/**
 * Widen a trip row with its captain's identity and vehicle.
 *
 * `captain_avatar_url` is the API-relative path held in `users.avatar_url`,
 * the same shape `GET /auth/me` and the bids endpoint return — clients prefix
 * it with the API base and send the bearer token.
 *
 * `captain_trips_count` counts completed trips, which is what a rider reads
 * "عدد الرحلات" to mean. It is deliberately not `rating_count`: that counts
 * ratings left, and a captain who drove 400 trips but was rated 12 times
 * should not be shown as a beginner.
 *
 * Unassigned trips skip the query entirely, and a failed lookup degrades to
 * the bare row — status, fare and coordinates matter more than a photo.
 */
async function withCaptain(env: Env, trip: DbTrip): Promise<TripWithCaptain> {
  if (!trip.captain_id) return trip;
  try {
    const row = await env.DB.prepare(
      `SELECT u.name       AS captain_name,
              u.phone      AS captain_phone,
              u.avatar_url AS captain_avatar_url,
              c.vehicle_make,
              c.vehicle_model,
              c.vehicle_plate,
              c.vehicle_color,
              c.vehicle_year,
              c.rating_avg,
              c.rating_count,
              (SELECT COUNT(*) FROM trips t
                WHERE t.captain_id = u.id AND t.status = 'completed')
                AS captain_trips_count
         FROM users u
         LEFT JOIN captains c ON c.user_id = u.id
        WHERE u.id = ?`,
    )
      .bind(trip.captain_id)
      .first<TripCaptainFacts>();
    return row ? { ...trip, ...row } : trip;
  } catch {
    return trip;
  }
}

async function broadcastTrip(env: Env, trip: DbTrip) {
  // Enrich once, then ship the same object to both the live socket and the
  // room's stored state — a rider whose socket connects late reads /state and
  // must not get a thinner payload than one who was already listening.
  const payload = await withCaptain(env, trip);
  const room = env.TRIP_ROOM.get(env.TRIP_ROOM.idFromName(trip.id));
  await room.fetch("https://room/broadcast", {
    method: "POST",
    body: JSON.stringify({ type: "trip.updated", trip: payload }),
  });
  await room.fetch("https://room/state", {
    method: "PUT",
    body: JSON.stringify(payload),
  });
}

/**
 * The routing engine for this Worker, resolved the fail-closed way.
 *
 * **This line used to be the reason gate item 11 could not close.** It read:
 *
 *     return (env as Env & { OSRM_URL?: string }).OSRM_URL || "https://router.project-osrm.org";
 *
 * — so however carefully `wrangler.toml` or `lib/routing.ts` were configured,
 * an unset `OSRM_URL` still sent every pickup and dropoff coordinate in the
 * product to the public OSRM demo server, whose policy forbids this use and
 * permits withdrawal without notice. E15 built [resolveOsrmBaseUrl] to replace
 * it and could not touch this file; its own header names the swap as the seam
 * E09 should adopt. This is that adoption.
 *
 * `null` means "no engine we are entitled to use" — either unset, or set to the
 * public host, which `resolveOsrmBaseUrl` deliberately reports as unset. What
 * each caller does about that is a policy decision, and it differs:
 *
 *  - **booking** refuses (503) — the number becomes a price;
 *  - **estimate** and the **arrival ETA** degrade to haversine — they are
 *    indicative, and refusing to draw a car makes no fare more accurate.
 */
function osrmUrl(env: Env): string | null {
  return resolveOsrmBaseUrl(env);
}

/**
 * How many times booking retries a failed route before giving up.
 *
 * One retry, not three. `getRoute` already carries an 8 s timeout, so a
 * three-deep retry ladder would hold a rider's booking request for 24 s before
 * admitting failure — by which point they have closed the app. One retry
 * catches the single dropped connection, which is the failure this is for; a
 * routing engine that is genuinely down is not going to answer on attempt two.
 */
const BOOKING_ROUTE_ATTEMPTS = 2;

/**
 * Route a booking, or fail the booking.
 *
 * Gate item 11's other half. `getRoute` defaults `allowFallback` to `true`
 * because E15 had to be safe to merge against this file untouched; on the
 * booking path that default is the bug. When OSRM fails, the fallback is
 * `haversine × 1.35` — and because a negotiated fare is never recomputed, that
 * straight line *becomes the settled price*. The plan's wording is exact: "a
 * permanent mispricing engine with no metric distinguishing the two states".
 *
 * So booking passes `allowFallback: false` and converts the resulting
 * [RouteUnavailableError] into a 503. A booking that fails loudly is recoverable
 * — the rider retries in a minute. A booking that silently prices a straight
 * line is not: nobody ever finds out, including the captain who gets paid off
 * it.
 *
 * Returns `null` when no route could be obtained; the caller answers 503.
 */
async function routeForBooking(
  env: Env,
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
): Promise<RouteResult | null> {
  const baseUrl = osrmUrl(env);

  // Not configured, or configured to the one host that does not count. There is
  // nothing transient about that, so it is not retried.
  if (!baseUrl) {
    counter("booking_route_unavailable", 1, { reason: "unconfigured" });
    logWarn("trips.booking_route_unavailable", {
      reason: "OSRM_URL is unset or points at the public demo server",
      retried: false,
    });
    return null;
  }

  let lastReason = "unknown";
  for (let attempt = 1; attempt <= BOOKING_ROUTE_ATTEMPTS; attempt++) {
    try {
      return await getRoute(pickup, dropoff, baseUrl, { allowFallback: false });
    } catch (e) {
      if (!(e instanceof RouteUnavailableError)) throw e;
      lastReason = e.reason;
      if (attempt < BOOKING_ROUTE_ATTEMPTS) {
        counter("booking_route_retry", 1, {});
      }
    }
  }

  counter("booking_route_unavailable", 1, { reason: "route_failed" });
  logWarn("trips.booking_route_unavailable", {
    reason: lastReason,
    attempts: BOOKING_ROUTE_ATTEMPTS,
    note: "refused to price this trip off a straight line; returned 503",
  });
  return null;
}

/**
 * Revoke every live share token for a trip that has ended — E13's seam.
 *
 * "Trip end" is any terminal transition, not just completion: a cancelled or
 * expired trip must not leave a live tracking link behind either.
 * `revokeShareToken` is idempotent, so calling it twice costs one no-op UPDATE.
 *
 * Non-fatal by design. At the completion call site the money has already moved;
 * throwing here would fail a request whose financial half already succeeded, and
 * the client would retry a completion that cannot complete. A token outliving
 * its trip is a real safety problem, so it is counted and logged at warn rather
 * than swallowed — visible to the alert on `share_token_revoke_failed` without
 * being able to break the trip lifecycle it is attached to.
 */
async function revokeShareTokensForTrip(db: D1Database, tripId: string, at: string): Promise<void> {
  try {
    const revoked = await revokeShareToken(db, tripId);
    if (revoked > 0) counter("share_token_revoked", revoked, { at });
  } catch (e) {
    counter("share_token_revoke_failed", 1, { at });
    logWarn("safety.share_token_revoke_failed", {
      tripId,
      at,
      reason: e instanceof Error ? e.message : String(e),
    });
  }
}

// ---------------------------------------------------------------------------
// Captain arrival ETA (used by GET /trips/:id/bids)
// ---------------------------------------------------------------------------

/**
 * How stale a captain's last fix may be before an ETA computed from it is
 * fiction rather than an estimate. An online captain posts a location every
 * few seconds; past this, the phone has stopped reporting and the honest
 * answer is no number at all.
 */
const ETA_MAX_LOCATION_AGE_MS = 10 * 60 * 1000;

/**
 * How long a computed ETA is reused for. 60s is the Cloudflare KV floor, and
 * it is also about the useful life of the number: a car covers ~300 m in that
 * time, which moves the answer by roughly a minute on a figure the rider is
 * reading to the nearest minute anyway.
 *
 * This is the knob if the numbers ever need to feel more live — lowering it
 * costs one OSRM request and one KV write per captain per negotiation per
 * interval, so the two scale together.
 */
const ETA_CACHE_TTL_SEC = 60;

/** A row from the bids query — the columns the ETA needs, plus the ones it
 * writes back. Intersected with the D1 row type rather than generic, because
 * assigning through a type parameter (`<T extends ...>(row: T)`) does not
 * typecheck: T could always be a narrower subtype than the value written. */
type BidRow = Record<string, unknown> & {
  captain_id?: string | null;
  captain_lat?: number | null;
  captain_lng?: number | null;
  captain_seen_at?: string | null;
  eta_min?: number | null;
  eta_source?: "osrm" | "haversine";
};

/**
 * Fills `eta_min` / `eta_source` on each bid — real driving minutes from the
 * captain's last known position to the pickup, over the street network.
 *
 * The rider app used to derive this itself: straight-line distance at a flat
 * 22 km/h. Across the Nile that is not an approximation, it is a different
 * number — the bridge is not where the crow flies.
 *
 * Two things keep a polled endpoint from becoming an OSRM firehose:
 *
 *  1. **One request for all bids.** OSRM's table service takes every captain
 *     and the pickup in a single call, so the cost is per poll, not per offer.
 *  2. **A KV cache per captain per trip.** The panel re-polls every 5s, so
 *     without it a single negotiation would fire twelve OSRM requests a minute
 *     for a number that barely moves. Keying on the pair rather than on the
 *     captain's rounded position is deliberate: a position key looks like a
 *     tighter cache, but a moving car misses it on every poll, which just
 *     trades OSRM requests for KV writes one-for-one. Keyed on the pair, both
 *     are bounded at one per interval whether the car is moving or parked.
 *
 * The fallback is cached too, under its own marker. When OSRM is unreachable
 * the alternative is paying the timeout on every single poll, which turns a
 * degraded ETA into a degraded endpoint.
 */
async function attachCaptainEtas(
  env: Env,
  rows: BidRow[],
  pickup: { lat?: number | null; lng?: number | null },
  tripId: string,
): Promise<void> {
  const pLat = pickup.lat;
  const pLng = pickup.lng;
  if (rows.length === 0 || typeof pLat !== "number" || typeof pLng !== "number") {
    return;
  }

  const now = Date.now();
  const routable: Array<{ row: BidRow; lat: number; lng: number; key: string }> = [];

  for (const row of rows) {
    const lat = typeof row.captain_lat === "number" ? row.captain_lat : null;
    const lng = typeof row.captain_lng === "number" ? row.captain_lng : null;
    if (lat === null || lng === null) continue;
    if (typeof row.captain_id !== "string" || !row.captain_id) continue;

    // An unparseable timestamp is treated as fresh rather than dropped: the
    // column is nullable on rows that predate location tracking, and a
    // slightly optimistic ETA beats a blank where a car clearly exists.
    const seenAt = row.captain_seen_at ? Date.parse(row.captain_seen_at) : NaN;
    if (Number.isFinite(seenAt) && now - seenAt > ETA_MAX_LOCATION_AGE_MS) continue;

    routable.push({ row, lat, lng, key: `eta:${tripId}:${row.captain_id}` });
  }

  if (routable.length === 0) return;

  // Cached as `<o|h>:<minutes>` so a hit restores the source too — the app
  // marks an estimate differently from a routed answer.
  const cached = await Promise.all(
    routable.map((entry) => env.SESSIONS.get(entry.key).catch(() => null)),
  );

  const misses: Array<{ row: BidRow; lat: number; lng: number; key: string }> = [];
  cached.forEach((hit, i) => {
    const entry = routable[i];
    if (!entry) return;
    const minutes = hit ? Number.parseInt(hit.slice(2), 10) : NaN;
    if (hit && Number.isFinite(minutes) && minutes > 0) {
      entry.row.eta_min = minutes;
      entry.row.eta_source = hit.startsWith("o:") ? "osrm" : "haversine";
    } else {
      misses.push(entry);
    }
  });

  if (misses.length > 0) {
    const estimates = await getDurationsToPoint(
      misses.map((entry) => ({ lat: entry.lat, lng: entry.lng })),
      { lat: pLat, lng: pLng },
      // `?? ""` is the honest translation of "no engine we may use":
      // `getDurationsToPoint` treats an empty base URL as unconfigured and
      // degrades to haversine per origin, counting `eta_fallback` as it goes.
      // This is an arrival ETA on a map, never a price — see [osrmUrl].
      osrmUrl(env) ?? "",
    );

    await Promise.all(
      misses.map(async (entry, i) => {
        const estimate = estimates[i];
        if (!estimate) return;
        entry.row.eta_min = estimate.durationMin;
        entry.row.eta_source = estimate.source;
        await env.SESSIONS.put(
          entry.key,
          `${estimate.source === "osrm" ? "o" : "h"}:${estimate.durationMin}`,
          { expirationTtl: ETA_CACHE_TTL_SEC },
        ).catch(() => {});
      }),
    );
  }
}

tripRoutes.post(
  "/estimate",
  rateLimit({ prefix: "estimate", limit: 30, windowSec: 60 }),
  async (c) => {
    const body = await parseBody(c, estimateTripSchema);
    if (isResponse(body)) return body;

    const city = body.city || c.env.DEFAULT_CITY || "cairo";
    const pricing = await getPricing(c.env.DB, city);
    if (!pricing) return c.json({ error: "Pricing not configured", code: "NO_PRICING" }, 500);

    // Fare math and the nearby-captain probe are independent — run them in
    // parallel so showing the cars on the rider's map adds no latency to the
    // estimate. The rider app also calls this endpoint with a zero-length
    // route purely as a proximity probe, to draw the Uber-style nearby cars.
    const [route, nearbyCaptains] = await Promise.all([
      // `allowFallback` stays at its default of `true` here, deliberately.
      // This is an indicative quote on a map, not a booking: refusing it when
      // OSRM blinks would turn every estimate into an error, which is strictly
      // worse than the straight line it replaces. Booking is where the number
      // becomes a price, and booking refuses — see [routeForBooking].
      getRoute(
        { lat: body.pickupLat, lng: body.pickupLng },
        { lat: body.dropoffLat, lng: body.dropoffLng },
        osrmUrl(c.env) ?? "",
      ),
      findNearbyCaptains(c.env, city, body.pickupLat, body.pickupLng, 15).catch(
        () => [] as Awaited<ReturnType<typeof findNearbyCaptains>>,
      ),
    ]);
    const result = fareFromRoute(route, pricingFromRow(pricing));

    // `result.source` is E15's `RouteSource` carried through `fareFromRoute`,
    // and spreading `result` is what puts it on the wire — the brief's "the
    // estimate may keep falling back but must surface `source`". A client
    // reading `source === "haversine"` knows this quote is a straight line.
    return c.json({ city, ...result, nearbyCaptains });
  },
);

tripRoutes.use("*", authMiddleware);

tripRoutes.post(
  "/",
  requireRole("rider", "admin"),
  rateLimit({
    prefix: "create-trip",
    limit: 10,
    windowSec: 60,
    keyFn: (c) => c.get("user")?.id ?? "anon",
  }),
  async (c) => {
    const user = c.get("user");
    const body = await parseBody(c, createTripSchema);
    if (isResponse(body)) return body;

    const active = await c.env.DB.prepare(
      `SELECT id FROM trips WHERE rider_id = ? AND status NOT IN ('completed', 'cancelled') LIMIT 1`,
    )
      .bind(user.id)
      .first();
    if (active) {
      return c.json(
        {
          error: "You already have an active trip",
          code: "ACTIVE_TRIP",
          tripId: String((active as { id: string }).id),
        },
        409,
      );
    }

    const city = body.city || c.env.DEFAULT_CITY || "cairo";
    const pricing = await getPricing(c.env.DB, city);
    if (!pricing) return c.json({ error: "Pricing not configured", code: "NO_PRICING" }, 500);

    // Gate item 11, the call-site half. This number becomes the fare, and a
    // negotiated fare is never recomputed — so a straight line accepted here is
    // a straight line the captain gets paid on. Fail the booking instead.
    const route = await routeForBooking(
      c.env,
      { lat: body.pickupLat, lng: body.pickupLng },
      { lat: body.dropoffLat, lng: body.dropoffLng },
    );
    if (!route) {
      return c.json(
        {
          error: "تعذّر حساب مسار الرحلة الآن. برجاء المحاولة بعد قليل.",
          code: "ROUTE_UNAVAILABLE",
        },
        503,
      );
    }

    let surgeMultiplier = 1.0;
    // Simple surge: multiply coefficient stored on pricing_rules via comment field
    // "surge:1.5" parsed out; default 1.0 to keep deterministic pricing.
    if (typeof (pricing as DbPricing & { surge_multiplier?: number }).surge_multiplier === "number") {
      surgeMultiplier = (pricing as DbPricing & { surge_multiplier?: number }).surge_multiplier ?? 1.0;
    }
    const est = fareFromRoute(route, pricingFromRow(pricing));
    // Apply surge to total
    if (surgeMultiplier !== 1.0) {
      est.fare.total = Math.round(est.fare.total * surgeMultiplier * 100) / 100;
    }

    let discount = 0;
    let promoCode: string | null = null;
    if (body.promoCode) {
      const promo = await c.env.DB.prepare(
        `SELECT * FROM promo_codes WHERE code = ? AND active = 1`,
      )
        .bind(body.promoCode.toUpperCase())
        .first<{
          code: string;
          type: string;
          value: number;
          max_uses: number | null;
          uses_count: number;
          expires_at: string | null;
        }>();

      if (
        promo &&
        (!promo.expires_at || new Date(promo.expires_at).getTime() > Date.now()) &&
        (promo.max_uses == null || promo.uses_count < promo.max_uses)
      ) {
        promoCode = promo.code;
        discount =
          promo.type === "percent"
            ? Math.round(est.fare.total * (promo.value / 100) * 100) / 100
            : Math.min(promo.value, est.fare.total);
      }
    }

    const finalEstimate = Math.max(0, Math.round((est.fare.total - discount) * 100) / 100);
    const commission = Math.round(finalEstimate * pricing.commission_rate * 100) / 100;

    // Resolve company binding (B2B) — employee trips are billed to the company.
    const emp = await c.env.DB.prepare(
      `SELECT company_id, cost_center FROM company_employees WHERE user_id = ? AND active = 1 LIMIT 1`,
    )
      .bind(user.id)
      .first<{ company_id: string; cost_center: string }>();

    const offeredPrice = body.offeredPrice || finalEstimate;

    const tripId = id("trip");
    await c.env.DB.prepare(
      `INSERT INTO trips (
        id, rider_id, status, city,
        pickup_lat, pickup_lng, pickup_address,
        dropoff_lat, dropoff_lng, dropoff_address,
        distance_km, duration_min, currency, estimated_fare, offered_price, commission, payment_method,
        promo_code, discount, vehicle_type_id, route_geometry, route_source,
        scheduled_for, schedule_status, waypoints, surge_multiplier,
        company_id, cost_center, billed_to_company
      ) VALUES (?, ?, 'searching', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        tripId,
        user.id,
        city,
        body.pickupLat,
        body.pickupLng,
        body.pickupAddress ?? null,
        body.dropoffLat,
        body.dropoffLng,
        body.dropoffAddress ?? null,
        est.distanceKm,
        est.durationMin,
        est.fare.currency,
        finalEstimate,
        offeredPrice,
        commission,
        body.paymentMethod || "cash",
        promoCode,
        discount,
        body.vehicleTypeId ?? null,
        JSON.stringify(est.geometry),
        // `trips.route_source`, migration 0023 — the other half of gate item
        // 11. E15 shipped the column and the `source` field and could not touch
        // this file; the INSERT is E09's. Without this write the column is a
        // value defined and never populated, which is root R3 exactly, and the
        // question "was this fare routed or guessed?" stays unanswerable after
        // the fact. `routeForBooking` refuses `haversine` outright, so in
        // practice this records `'osrm'` — and the day that stops being true,
        // the column is how anyone finds out.
        est.source,
        body.scheduledFor ?? null,
        body.scheduledFor ? "pending" : null,
        body.waypoints ? JSON.stringify(body.waypoints) : null,
        surgeMultiplier,
        emp?.company_id ?? null,
        emp?.cost_center ?? null,
        emp ? 1 : 0,
      )
      .run();

    // Schedule dispatch when requested
    if (body.scheduledFor) {
      await c.env.DB.prepare(
        `INSERT INTO scheduled_trip_dispatch
          (id, trip_id, scheduled_for, status) VALUES (?, ?, ?, 'pending')`,
      )
        .bind(id("sched"), tripId, body.scheduledFor)
        .run();
    }

    if (promoCode) {
      await c.env.DB.prepare(
        `INSERT INTO trip_promo (trip_id, promo_code, discount) VALUES (?, ?, ?)`,
      )
        .bind(tripId, promoCode, discount)
        .run();
      await c.env.DB.prepare(
        `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE code = ?`,
      )
        .bind(promoCode)
        .run();
    }

    const createdEvent = logEvent(c.env.DB, tripId, "created", user.id, {
      estimate: est.fare,
      discount,
      promoCode,
      routeSource: est.source,
    });

    // Gate item 9. A scheduled ride is **not** dispatched now.
    //
    // This one `if` is the fix. Before it, a ride booked for 07:00 tomorrow was
    // offered to captains the moment it was booked: `OfferScheduler` rolled
    // through all ten candidates in ~45 s, each declined a job they could not
    // take, and the trip then sat in `searching` with its entire candidate pool
    // already spent — landing in exactly the permanent-`searching` state of
    // item 7 (F-06-01 / F-16-02). Booking a ride for tomorrow morning was the
    // most reliable way to brick an account.
    //
    // It is also what makes the cron reachable. `runScheduledDispatchJob`
    // filters on `t.status = 'searching'`, a predicate that could never match
    // while this call ran unconditionally and moved the row to `offered`. The
    // dead `WHERE` and the early dispatch were one bug seen from two ends.
    let status: TripStatus = "searching";
    let captains: Awaited<ReturnType<typeof dispatchTrip>>["captains"] = [];

    if (body.scheduledFor) {
      // `dispatchTrip` was the only thing awaiting this write; nothing else
      // does, so it has to be awaited here or the request can return before
      // the `created` event lands.
      await createdEvent;
      await logEvent(c.env.DB, tripId, "scheduled", user.id, {
        scheduledFor: body.scheduledFor,
        note: "dispatch deferred to cron/dispatch.ts at the scheduled time",
      });
      counter("trip_scheduled", 1, {});
    } else {
      const dispatched = await dispatchTrip({
        env: c.env,
        tripId,
        city,
        pickupLat: body.pickupLat,
        pickupLng: body.pickupLng,
        dropoffLat: body.dropoffLat,
        dropoffLng: body.dropoffLng,
        estimatedFare: finalEstimate,
        currency: est.fare.currency,
        actorId: user.id,
        pendingEvent: createdEvent,
        logEvent,
      });
      status = dispatched.status;
      captains = dispatched.captains;
    }

    const nearby = { captains };

    const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind(tripId)
      .first<DbTrip>();

    if (trip) await broadcastTrip(c.env, trip);

    return c.json(
      {
        trip,
        estimate: { ...est, discount, totalAfterDiscount: finalEstimate },
        nearbyCaptains: nearby.captains ?? [],
        status,
      },
      201,
    );
  },
);

tripRoutes.get("/history", async (c) => {
  const user = c.get("user");
  const q = c.env.DB.prepare(
    `SELECT * FROM trips WHERE rider_id = ? ORDER BY created_at DESC LIMIT 50`,
  ).bind(user.id);
  const res = await q.all<DbTrip>();
  return c.json({ trips: res.results ?? [] });
});

/**
 * `GET /trips/active` — the trip this user is currently in, if any.
 *
 * Gate item 7, the recovery half. Killing the app mid-trip and reopening it
 * used to land the rider on the home screen with no way back: `bootstrap()`
 * never asked whether a trip was in flight, and nothing served the answer if it
 * had. This is the endpoint that answers. E10 owns the client that calls it.
 *
 * ## The predicates are copied from the guards, deliberately
 *
 * Each role's filter here is **byte-identical to the guard that would otherwise
 * lock that role out**:
 *
 *  - rider → `status NOT IN ('completed','cancelled')`, the `ACTIVE_TRIP` guard
 *    in `POST /trips`;
 *  - captain → `status IN ('assigned','arrived','in_progress')`, the `BUSY`
 *    guard in `POST /trips/:id/accept`.
 *
 * That is the property that matters, and it is worth more than the endpoint
 * itself. If this query were merely *similar* to the guard, the two could
 * disagree — and the state where the guard says "you already have a trip" while
 * recovery says "you have none" is precisely the bricked account, now with an
 * endpoint that confirms nothing is wrong. Whoever changes one of these must
 * change the other; they are the same question asked by two callers.
 *
 * Registered ahead of `GET /:id` because Hono matches in registration order and
 * `/:id` would otherwise swallow `/active` and 404 on a trip called "active".
 *
 * Returns `{ trip: null }` rather than a 404 when there is nothing active:
 * "you have no trip in progress" is a successful answer to this question, and
 * making the client distinguish it from a transport failure is how clients end
 * up treating both as "stay on the home screen".
 */
tripRoutes.get("/active", async (c) => {
  const user = c.get("user");

  const trip =
    user.role === "captain"
      ? await c.env.DB.prepare(
          `SELECT * FROM trips WHERE captain_id = ? AND status IN ('assigned','arrived','in_progress')
           ORDER BY created_at DESC LIMIT 1`,
        )
          .bind(user.id)
          .first<DbTrip>()
      : await c.env.DB.prepare(
          `SELECT * FROM trips WHERE rider_id = ? AND status NOT IN ('completed', 'cancelled')
           ORDER BY created_at DESC LIMIT 1`,
        )
          .bind(user.id)
          .first<DbTrip>();

  if (!trip) return c.json({ trip: null, geometry: null });

  // Same shape `GET /trips/:id` returns, minus the event log: a client
  // recovering into the live trip screen needs the captain card and the
  // polyline, and should not have to make a second call for either.
  let geometry: unknown = null;
  try {
    geometry = trip.route_geometry ? JSON.parse(trip.route_geometry) : null;
  } catch {
    geometry = null;
  }

  return c.json({ trip: await withCaptain(c.env, trip), geometry });
});

tripRoutes.get("/", async (c) => {
  const user = c.get("user");
  let q: D1PreparedStatement;
  if (user.role === "admin") {
    q = c.env.DB.prepare(`SELECT * FROM trips ORDER BY created_at DESC LIMIT 100`);
  } else if (user.role === "captain") {
    // City scoping: open trips (searching/offered) are only surfaced from the
    // captain's working city, mirroring /captain/offers and
    // /captain/nearby-requests. Without this the endpoint leaked every open
    // request nationwide to any authenticated captain — trips in cities they
    // could never serve — while the curated offers endpoints were filtered.
    // The captain's own trips (any status) are unaffected by the filter.
    const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
      .bind(user.id)
      .first<DbCaptain>();
    const city =
      (captain as (DbCaptain & { city?: string | null }) | null)?.city ||
      c.env.DEFAULT_CITY ||
      "cairo";
    q = c.env.DB.prepare(
      `SELECT * FROM trips WHERE captain_id = ? OR (status IN ('searching','offered') AND city = ?)
       ORDER BY created_at DESC LIMIT 50`,
    ).bind(user.id, city);
  } else {
    q = c.env.DB.prepare(
      `SELECT * FROM trips WHERE rider_id = ? ORDER BY created_at DESC LIMIT 50`,
    ).bind(user.id);
  }
  const res = await q.all<DbTrip>();
  return c.json({ trips: res.results ?? [] });
});

tripRoutes.get("/:id", async (c) => {
  const user = c.get("user");
  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(c.req.param("id"))
    .first<DbTrip>();
  if (!trip) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);

  if (
    user.role !== "admin" &&
    trip.rider_id !== user.id &&
    trip.captain_id !== user.id
  ) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const events = await c.env.DB.prepare(
    `SELECT * FROM trip_events WHERE trip_id = ? ORDER BY created_at ASC`,
  )
    .bind(trip.id)
    .all();

  let geometry: unknown = null;
  try {
    geometry = trip.route_geometry ? JSON.parse(trip.route_geometry) : null;
  } catch {
    geometry = null;
  }

  return c.json({
    trip: await withCaptain(c.env, trip),
    events: events.results ?? [],
    geometry,
  });
});

tripRoutes.get("/:id/path", async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("id");
  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (!trip) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);

  if (
    user.role !== "admin" &&
    trip.rider_id !== user.id &&
    trip.captain_id !== user.id
  ) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const points = await c.env.DB.prepare(
    `SELECT lat, lng, heading, speed, recorded_at FROM trip_path_points
     WHERE trip_id = ? ORDER BY recorded_at ASC LIMIT 2000`,
  )
    .bind(tripId)
    .all();

  return c.json({ tripId, points: points.results ?? [] });
});


tripRoutes.post("/:id/cancel", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, cancelTripSchema);
  const reason = isResponse(body) ? undefined : body.reason;

  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(c.req.param("id"))
    .first<DbTrip>();
  if (!trip) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);

  if (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  if (!canTransition(trip.status as TripStatus, "cancelled")) {
    return c.json({ error: `Cannot cancel from ${trip.status}`, code: "INVALID_TRANSITION" }, 400);
  }

  await c.env.DB.prepare(
    `UPDATE trips SET status = 'cancelled', cancel_reason = ?, cancelled_at = ?, updated_at = ? WHERE id = ?`,
  )
    .bind(reason ?? null, nowIso(), nowIso(), trip.id)
    .run();

  await logEvent(c.env.DB, trip.id, "cancelled", user.id, { reason });

  // Trip end — kill any live tracking link. A cancelled trip that leaves a
  // shareable position URL alive is the safety feature lying in the other
  // direction: the recipient keeps watching a journey that is not happening.
  await revokeShareTokensForTrip(c.env.DB, trip.id, "cancel");

  const updated = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(trip.id)
    .first<DbTrip>();
  if (updated) await broadcastTrip(c.env, updated);

  const cancelledByRider = user.id === trip.rider_id;

  // (1) Rider cancelled an open request → clear it from every nearby
  // captain's inbox in real time. Without this the offer card lingered on
  // captains' screens until the next offers poll (up to 20s later), and a
  // captain could tap accept on a dead trip and hit a 409 — the visible
  // "تأخير بين الالغاء" the captain experiences.
  //
  // The fanout queries the same neighbourhood with a WIDER limit (25) than
  // dispatch (10). In the theoretical case of >10 captains in the
  // neighbourhood the cancel event may reach captains who never got the
  // offer; that is harmless — their app simply removes a card that is not
  // on screen — while the reverse (a captain who got the offer never
  // hearing the cancel) would strand the card.
  if (cancelledByRider && ["searching", "offered"].includes(trip.status)) {
    // Stop the staged rollout first — no further wave fires after the trip
    // died, and the scheduler's alarm would otherwise re-offer a dead trip.
    try {
      const scheduler = c.env.OFFER_SCHEDULER.get(
        c.env.OFFER_SCHEDULER.idFromName(trip.id),
      );
      await scheduler.fetch("https://scheduler/cancel", { method: "POST" });
    } catch (e) {
      console.error("offer scheduler teardown failed", trip.id, e);
    }
    try {
      // Same neighbourhood the offer reached on the way in — widening the
      // dispatch radius without widening the cancel radius would strand
      // offer cards on captains in the outer cells.
      const nearbyCaptains = await findNearbyCaptains(
        c.env,
        trip.city,
        trip.pickup_lat,
        trip.pickup_lng,
        25,
      );
      await Promise.all(
        nearbyCaptains.map(async (cap) => {
          try {
            const inbox = c.env.CAPTAIN_INBOX.get(
              c.env.CAPTAIN_INBOX.idFromName(cap.userId),
            );
            await inbox.fetch("https://inbox/push", {
              method: "POST",
              body: JSON.stringify({
                type: "trip.cancelled",
                tripId: trip.id,
                at: nowIso(),
              }),
            });
          } catch (e) {
            console.error("cancel inbox push failed", cap.userId, e);
          }
        }),
      );
    } catch (e) {
      console.error("cancel fanout failed", trip.id, e);
    }
  }

  // (2) Tell the other side by push, so the cancellation lands even when
  // their app is not watching the trip room (rider on the home screen /
  // captain with the app closed).
  try {
    if (cancelledByRider && trip.captain_id) {
      await pushToUser({
        env: c.env,
        userId: trip.captain_id,
        topic: "trip.cancelled",
        title: "ألغى الراكب الرحلة",
        body: "قام الراكب بإلغاء الرحلة. لا حاجة لأي إجراء منك.",
        data: { tripId: trip.id, status: "cancelled" },
      });
    } else if (!cancelledByRider && trip.rider_id) {
      await pushToUser({
        env: c.env,
        userId: trip.rider_id,
        topic: "trip.cancelled",
        title: "تم إلغاء الرحلة",
        body: "نعتذر — تم إلغاء رحلتك. يمكنك طلب رحلة جديدة فورًا.",
        data: { tripId: trip.id, status: "cancelled" },
      });
    }
  } catch (e) {
    console.error("cancel push failed", trip.id, e);
  }

  return c.json({ trip: updated });
});

tripRoutes.post("/:id/accept", requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("id");
  if (!tripId) return c.json({ error: "trip id required", code: "MISSING_ID" }, 400);

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();
  if (!captain || (captain.approval_status !== "approved" && user.role !== "admin")) {
    return c.json({ error: "Captain not approved", code: "NOT_APPROVED" }, 403);
  }
  // Online guard: an offline captain must not accept trips.
  // The client suppresses the UI, but a direct API call could still slip through.
  if (!captain.is_online && user.role !== "admin") {
    return c.json({ error: "يجب أن تكون متصلاً لقبول الرحلات", code: "OFFLINE" }, 403);
  }

  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (!trip) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  if (!["searching", "offered"].includes(trip.status)) {
    return c.json({ error: `Trip not available (${trip.status})`, code: "NOT_AVAILABLE" }, 409);
  }

  const busy = await c.env.DB.prepare(
    `SELECT id FROM trips WHERE captain_id = ? AND status IN ('assigned','arrived','in_progress') LIMIT 1`,
  )
    .bind(user.id)
    .first();
  if (busy) return c.json({ error: "You already have an active trip", code: "BUSY" }, 409);

  // ── Gate item 6, the call site ──────────────────────────────────────────
  //
  // "Make `/trips/:id/accept` settle `offered_price`." E08 built the primitive
  // and could not reach this line; its header says so: "that line, and the
  // `/trips/:id/accept` handler at `routes/trips.ts:733`, are in
  // `routes/trips.ts`, which **E09** owns. Until E09 flips the call site the
  // corrected number is available and unused."
  //
  // The defect: on the direct-accept path no bid row exists, so `accepted_price`
  // is null. The captain is *shown* `offered_price` — `GET /trips` serves
  // captains `SELECT *` — and accepts that number, but settlement at completion
  // fell through to `estimated_fare`. T05 measured the gap at 89 EGP on a real
  // trip and calls it the most important finding in that document, because it
  // breaks the product's entire differentiator silently: a negotiated-price
  // platform that pays a different number from the one that was negotiated.
  //
  // Recording the agreed price *here*, at the moment of agreement, is what
  // makes it true later. The alternative — resolving it again at completion —
  // leaves the row ambiguous for the whole trip and gives an operator nothing
  // to answer a dispute with. [resolveTripSettlement] is E08's pure function,
  // so both ends of the trip agree on the number by construction.
  const agreed = resolveTripSettlement(trip as SettlementTrip);
  const hasAgreedPrice = agreed.priceSource !== "none";

  const updateRes = await c.env.DB.prepare(
    `UPDATE trips SET status = 'assigned', captain_id = ?, assigned_at = ?, captain_lat = ?, captain_lng = ?,
            accepted_price = COALESCE(?, accepted_price), commission = COALESCE(?, commission), updated_at = ?
     WHERE id = ? AND status IN ('searching','offered')`,
  )
    .bind(
      user.id,
      nowIso(),
      captain.last_lat,
      captain.last_lng,
      // Null leaves the column alone. A trip with no price on it at all is a
      // data fault, not a free ride — writing a resolved `0` over it would
      // erase the evidence and settle the trip at zero.
      hasAgreedPrice ? agreed.agreedPrice : null,
      hasAgreedPrice ? agreed.commission : null,
      nowIso(),
      tripId,
    )
    .run();

  if (updateRes.meta && updateRes.meta.changes === 0) {
    return c.json({ error: "Trip was already taken by another captain", code: "TRIP_TAKEN" }, 409);
  }

  if (!hasAgreedPrice) {
    counter("accept_without_price", 1, {});
    logWarn("trips.accept_without_price", {
      tripId,
      requestId: getRequestId(c),
      reason: "no accepted_price, offered_price, final_fare or estimated_fare on the row",
    });
  }

  await logEvent(c.env.DB, tripId, "assigned", user.id, {
    acceptedPrice: hasAgreedPrice ? agreed.agreedPrice : null,
    priceSource: agreed.priceSource,
    commission: hasAgreedPrice ? agreed.commission : null,
    commissionSource: agreed.commissionSource,
  });
  const updated = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (updated) await broadcastTrip(c.env, updated);
  // Notify the rider their trip was accepted
  if (updated?.rider_id) {
    await pushToUser({
      env: c.env,
      userId: updated.rider_id,
      topic: "trip.accepted",
      title: "تم قبول رحلتك",
      body: "الكابتن في الطريق إليك. تتبّع الرحلة لحظيًا داخل التطبيق.",
      data: { tripId, captainId: user.id, status: "assigned" },
    });
  }
  return c.json({ trip: updated });
});

async function advanceStatus(
  c: Context<AppEnv>,
  next: TripStatus,
  timestampCol: "arrived_at" | "started_at",
) {
  const user = c.get("user");
  const tripId = c.req.param("id");
  if (!tripId) return c.json({ error: "trip id required", code: "MISSING_ID" }, 400);
  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (!trip) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  if (trip.captain_id !== user.id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }
  if (!canTransition(trip.status as TripStatus, next)) {
    return c.json(
      { error: `Cannot go ${trip.status} → ${next}`, code: "INVALID_TRANSITION" },
      400,
    );
  }

  await c.env.DB.prepare(
    `UPDATE trips SET status = ?, ${timestampCol} = ?, updated_at = ? WHERE id = ?`,
  )
    .bind(next, nowIso(), nowIso(), tripId)
    .run();

  await logEvent(c.env.DB, tripId, next, user.id);
  const updated = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (updated) await broadcastTrip(c.env, updated);
  // Push the rider when the captain arrives or starts the trip
  if (updated?.rider_id) {
    const title = next === "arrived" ? "وصل الكابتن" : "بدأت الرحلة";
    const body =
      next === "arrived"
        ? "الكابتن وصل إلى نقطة الالتقاء. تفضّل بالنزول."
        : "انطلقت رحلتك. تتبّع المسار لحظيًا داخل التطبيق.";
    await pushToUser({
      env: c.env,
      userId: updated.rider_id,
      topic: `trip.${next}`,
      title,
      body,
      data: { tripId, status: next },
    });
  }
  return c.json({ trip: updated });
}

tripRoutes.post("/:id/arrived", requireRole("captain", "admin"), async (c) =>
  advanceStatus(c, "arrived", "arrived_at"),
);

tripRoutes.post("/:id/start", requireRole("captain", "admin"), async (c) =>
  advanceStatus(c, "in_progress", "started_at"),
);

tripRoutes.post("/:id/complete", requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("id");
  if (!tripId) return c.json({ error: "trip id required", code: "MISSING_ID" }, 400);
  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (!trip) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  if (trip.captain_id !== user.id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }
  if (!canTransition(trip.status as TripStatus, "completed")) {
    return c.json(
      { error: `Cannot complete from ${trip.status}`, code: "INVALID_TRANSITION" },
      400,
    );
  }

  // Gate item 6, the second call site. This block used to be:
  //
  //     const finalFare = trip.accepted_price ?? trip.final_fare ?? trip.estimated_fare ?? 0;
  //     const commission = trip.commission ?? 0;
  //
  // — a fourth, independent price-resolution chain, and the one place
  // `offered_price` was missing from. E08 put the canonical chain in
  // [resolveTripSettlement] and left a `settlement_price_mismatch` counter
  // firing on every completion where the caller's number disagreed with the
  // resolved one, precisely so this gap was visible on `main` rather than only
  // in a document. Using the same function on both sides is what stops that
  // counter — not by silencing it, but by removing the disagreement.
  //
  // The commission matters as much as the fare: settling price X while taking
  // commission computed from Y pays the captain the wrong number. On the
  // `offered_price` path the stored commission is still on the `estimated_fare`
  // basis, and E08 rescales it at the booking's own effective rate.
  const settlement = resolveTripSettlement(trip as SettlementTrip);
  const finalFare = settlement.agreedPrice;
  const commission = settlement.commission;
  const captainPayout = settlement.captainPayout;

  const updateRes = await c.env.DB.prepare(
    `UPDATE trips SET status = 'completed', final_fare = ?, completed_at = ?, updated_at = ? WHERE id = ? AND status != 'completed'`,
  )
    .bind(finalFare, nowIso(), nowIso(), tripId)
    .run();

  if (updateRes.meta && updateRes.meta.changes === 0) {
    return c.json({ error: "Trip is already completed or state changed", code: "CONFLICT" }, 409);
  }

  await logEvent(c.env.DB, tripId, "completed", user.id, {
    finalFare,
    commission,
    priceSource: settlement.priceSource,
    commissionSource: settlement.commissionSource,
  });

  // `finalFare`, `commission` and `captainPayout` are deliberately **not**
  // passed. They are optional on the primitive exactly so this call site can
  // stop supplying them once it was flipped, and letting settlement resolve its
  // own numbers means there is one chain in the codebase rather than two that
  // have to be kept in agreement by hand. `requestId` ties the money moves to
  // the request that caused them — E12's correlation id, tolerant of the
  // middleware being absent.
  await settleTripCompletion({
    db: c.env.DB,
    trip,
    tripId,
    requestId: getRequestId(c),
  });

  // Trip end — kill any live tracking link (E13's seam). Deliberately after
  // settlement: the money is the part that must not be disturbed, and this
  // never throws.
  await revokeShareTokensForTrip(c.env.DB, tripId, "complete");

  const updated = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (updated) await broadcastTrip(c.env, updated);
  // Notify both rider and captain the trip completed
  if (updated?.rider_id) {
    await pushToUser({
      env: c.env,
      userId: updated.rider_id,
      topic: "trip.completed",
      title: "وصلت بسلامة",
      body: `انتهت رحلتك. الأجرة ${finalFare} ج.م. قيّم رحلتك من فضلك.`,
      data: { tripId, finalFare: String(finalFare) },
    });
  }
  if (updated?.captain_id) {
    const isCash = trip.payment_method === "cash";
    await pushToUser({
      env: c.env,
      userId: updated.captain_id,
      topic: "trip.completed",
      title: "اكتملت الرحلة",
      body: isCash
        ? `حصّلت ${finalFare} ج.م نقداً. عمولة المنصة ${commission} ج.م خُصمت من محفظتك.`
        : `أرباحك من هذه الرحلة ${captainPayout} ج.م.`,
      data: isCash
        ? { tripId, collected: String(finalFare), commission: String(commission) }
        : { tripId, payout: String(captainPayout) },
    });
  }
  return c.json({ trip: updated });
});

tripRoutes.post("/:id/rate", async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("id");
  const body = await parseBody(c, rateTripSchema);
  if (isResponse(body)) return body;

  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();
  if (!trip || trip.status !== "completed") {
    return c.json({ error: "Trip not completed", code: "NOT_COMPLETED" }, 400);
  }

  let toUserId: string | null = null;
  if (user.id === trip.rider_id && trip.captain_id) toUserId = trip.captain_id;
  else if (user.id === trip.captain_id) toUserId = trip.rider_id;
  else if (user.role === "admin" && trip.captain_id) toUserId = trip.captain_id;
  else return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);

  const ratingId = id("rate");
  try {
    await c.env.DB.prepare(
      `INSERT INTO ratings (id, trip_id, from_user_id, to_user_id, score, comment)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(ratingId, tripId, user.id, toUserId, body.score, body.comment ?? null)
      .run();
  } catch {
    return c.json({ error: "Already rated", code: "ALREADY_RATED" }, 409);
  }

  if (toUserId === trip.captain_id && toUserId) {
    const agg = await c.env.DB.prepare(
      `SELECT AVG(score) as avg_score, COUNT(*) as cnt FROM ratings WHERE to_user_id = ?`,
    )
      .bind(toUserId)
      .first<{ avg_score: number; cnt: number }>();
    if (agg) {
      await c.env.DB.prepare(
        `UPDATE captains SET rating_avg = ?, rating_count = ?, updated_at = ? WHERE user_id = ?`,
      )
        .bind(agg.avg_score, agg.cnt, nowIso(), toUserId)
        .run();
    }
  }

  return c.json({ ok: true, ratingId });
});

// ============================================================
// DYNAMIC BIDDING & NEGOTIATION ENDPOINTS
// ============================================================

// POST /trips/:id/bid — Captain submits a counter-offer or accepts rider's offer
tripRoutes.post("/:id/bid", requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: "Unauthorized", code: "UNAUTHORIZED" }, 401);
  const tripId = c.req.param("id");
  const parsed = await parseBody(c, createBidSchema);
  if (isResponse(parsed)) return parsed;
  const body = parsed as { counterPrice: number };

  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();

  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
  if (!["searching", "offered"].includes(trip.status)) {
    return c.json({ error: "Trip is no longer accepting bids", code: "TRIP_CLOSED" }, 400);
  }

  // Online guard: an offline captain must not submit bids.
  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();
  if (captain && !captain.is_online && user.role !== "admin") {
    return c.json({ error: "يجب أن تكون متصلاً لتقديم عرض سعر", code: "OFFLINE" }, 403);
  }

  const bidId = id("bid");
  await c.env.DB.prepare(
    `INSERT INTO trip_bids (id, trip_id, captain_id, counter_price, status, created_at)
     VALUES (?, ?, ?, ?, 'pending', ?)`
  )
    .bind(bidId, tripId, user.id, body.counterPrice, nowIso())
    .run();

  await c.env.DB.prepare(`UPDATE trips SET status = 'offered', updated_at = ? WHERE id = ?`)
    .bind(nowIso(), tripId)
    .run();

  const cleanTripId = tripId ?? "";
  await logEvent(c.env.DB, cleanTripId, "bid.created", user.id, {
    bidId,
    counterPrice: body.counterPrice,
  });

  // Tell the rider's trip room the status moved to `offered`. Every other
  // mutating endpoint here broadcasts; this one did not, and the omission was
  // load-bearing: the rider only opens CaptainBidsSheet when it sees status
  // `offered`, and the 5s GET /trips/:id/bids poll lives INSIDE that sheet. No
  // broadcast → no sheet → no poll → the counter-offer was never fetched, so a
  // captain who bid on a trip still in `searching` was invisible to the rider.
  const updatedTrip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(cleanTripId)
    .first<DbTrip>();
  if (updatedTrip) await broadcastTrip(c.env, updatedTrip);

  // Notify Rider about new driver counter-offer
  await pushToUser({
    env: c.env,
    userId: trip.rider_id,
    topic: "trip.bid_received",
    title: "عرض سعر جديد لكابتن!",
    body: `قدم الكابتن عرض سعر بمبلغ ${body.counterPrice} ج.م. اضغط للمعاينة.`,
    data: { tripId: cleanTripId, bidId, counterPrice: String(body.counterPrice) },
  });

  return c.json({ ok: true, bidId, counterPrice: body.counterPrice });
});

// GET /trips/:id/bids — Rider or Admin fetches all bids submitted for a trip
tripRoutes.get("/:id/bids", async (c) => {
  const user = c.get("user");
  const tripId = c.req.param("id");

  // pickup_lat/pickup_lng are selected for the arrival ETA below.
  const trip = await c.env.DB.prepare(
    `SELECT rider_id, pickup_lat, pickup_lng FROM trips WHERE id = ?`,
  )
    .bind(tripId)
    .first<{ rider_id: string; pickup_lat: number | null; pickup_lng: number | null }>();

  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);

  if (user.role !== "admin" && trip.rider_id !== user.id) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  // avatar_url: the rider is choosing between people, and every offer
  // rendering the same placeholder glyph made that choice harder than it
  // needed to be. GET /user/avatar/* is already readable by any authenticated
  // user for exactly this reason.
  //
  // last_seen_at qualifies the coordinates: it is what tells the ETA whether
  // last_lat/last_lng are a live position or an abandoned one.
  const bids = await c.env.DB.prepare(
    `SELECT b.id, b.trip_id, b.captain_id, b.counter_price, b.status, b.created_at,
            u.name as captain_name, u.phone as captain_phone, u.avatar_url as captain_avatar_url,
            c.vehicle_make, c.vehicle_model, c.vehicle_plate, c.vehicle_color, c.rating_avg, c.rating_count,
            c.last_lat as captain_lat, c.last_lng as captain_lng, c.last_seen_at as captain_seen_at
     FROM trip_bids b
     JOIN users u ON b.captain_id = u.id
     LEFT JOIN captains c ON b.captain_id = c.user_id
     WHERE b.trip_id = ? AND b.status = 'pending'
     ORDER BY b.created_at DESC`
  )
    .bind(tripId)
    .all<BidRow>();

  const rows = bids.results || [];
  await attachCaptainEtas(
    c.env,
    rows,
    { lat: trip.pickup_lat, lng: trip.pickup_lng },
    tripId ?? "",
  );

  return c.json({ bids: rows });
});

// POST /trips/:id/accept-bid — Rider accepts a specific captain's bid
tripRoutes.post("/:id/accept-bid", requireRole("rider", "admin"), async (c) => {
  const user = c.get("user");
  if (!user) return c.json({ error: "Unauthorized", code: "UNAUTHORIZED" }, 401);
  const tripId = c.req.param("id");
  const parsed = await parseBody(c, acceptBidSchema);
  if (isResponse(parsed)) return parsed;
  const body = parsed as { bidId: string };

  const trip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<DbTrip>();

  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
  if (user.role !== "admin" && trip.rider_id !== user.id) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  if (!["searching", "offered"].includes(trip.status)) {
    return c.json({ error: "Trip is no longer open", code: "TRIP_CLOSED" }, 409);
  }

  const selectedBid = await c.env.DB.prepare(`SELECT * FROM trip_bids WHERE id = ? AND trip_id = ? AND status = 'pending'`)
    .bind(body.bidId, tripId)
    .first<{ id: string; captain_id: string; counter_price: number; status: string }>();

  if (!selectedBid) {
    return c.json({ error: "Bid not found or no longer valid", code: "BID_NOT_FOUND" }, 404);
  }

  const cap = await c.env.DB.prepare(`SELECT approval_status FROM captains WHERE user_id = ?`)
    .bind(selectedBid.captain_id)
    .first<{ approval_status: string }>();

  if (cap?.approval_status !== "approved") {
    return c.json({ error: "Captain is not approved", code: "CAPTAIN_NOT_APPROVED" }, 409);
  }

  const acceptedPrice = selectedBid.counter_price;
  const pricing = await getPricing(c.env.DB, trip.city);
  const commissionRate = pricing?.commission_rate || 0.2;
  const commission = Math.round(acceptedPrice * commissionRate * 100) / 100;

  // Assign captain conditionally and set agreed price
  const updateRes = await c.env.DB.prepare(
    `UPDATE trips SET captain_id = ?, accepted_price = ?, final_fare = ?, commission = ?, status = 'assigned', assigned_at = ?, updated_at = ?
     WHERE id = ? AND status IN ('searching', 'offered')`
  )
    .bind(selectedBid.captain_id, acceptedPrice, acceptedPrice, commission, nowIso(), nowIso(), tripId)
    .run();

  if (updateRes.meta && updateRes.meta.changes === 0) {
    return c.json({ error: "Trip already assigned or completed", code: "TRIP_CONFLICT" }, 409);
  }

  // Mark selected bid as accepted, others as rejected
  await c.env.DB.prepare(`UPDATE trip_bids SET status = 'accepted' WHERE id = ?`).bind(body.bidId).run();
  await c.env.DB.prepare(`UPDATE trip_bids SET status = 'rejected' WHERE trip_id = ? AND id != ?`)
    .bind(tripId, body.bidId)
    .run();

  const cleanTripId = tripId ?? "";
  await logEvent(c.env.DB, cleanTripId, "bid.accepted", user.id, {
    bidId: body.bidId,
    captainId: selectedBid.captain_id,
    acceptedPrice,
  });

  const updatedTrip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`).bind(cleanTripId).first<DbTrip>();
  if (updatedTrip) await broadcastTrip(c.env, updatedTrip);

  // Wake the winning captain on their offers socket, not just by FCM.
  //
  // broadcastTrip publishes to the trip room, which this captain has not
  // joined yet — they only open that socket once the trip is theirs. So the
  // only in-app signal used to be the 8–60s offers poll: the captain sat on
  // the bid screen after the rider had already accepted, with no idea the job
  // was won. The inbox event lands in milliseconds and is what flips the app
  // to the map.
  try {
    const inbox = c.env.CAPTAIN_INBOX.get(
      c.env.CAPTAIN_INBOX.idFromName(selectedBid.captain_id),
    );
    await inbox.fetch("https://inbox/push", {
      method: "POST",
      body: JSON.stringify({
        type: "trip.assigned",
        reason: "bid.accepted",
        tripId: cleanTripId,
        bidId: body.bidId,
        acceptedPrice,
        at: nowIso(),
      }),
    });
  } catch (e) {
    // Best-effort: FCM below and the offers poll both still deliver.
    console.error("bid accepted inbox push failed", selectedBid.captain_id, e);
  }

  // Notify assigned Captain
  await pushToUser({
    env: c.env,
    userId: selectedBid.captain_id,
    topic: "trip.assigned",
    title: "تم قبول عرضك!",
    body: `وافق الراكب على عرضك بمبلغ ${acceptedPrice} ج.م. توجه لموقع الانطلاق.`,
    data: { tripId: cleanTripId, acceptedPrice: String(acceptedPrice) },
  });

  return c.json({ ok: true, trip: updatedTrip });
});
