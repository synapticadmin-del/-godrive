import { Hono } from "hono";
import { canTransition, type TripStatus } from "@synaptic-go/shared";
import type { Context } from "hono";
import { pricingFromRow } from "../lib/pricing";
import { filterByCaptainRadius, findNearbyCaptains } from "../lib/nearby";
import { fareFromRoute, getDurationsToPoint, getRoute } from "../lib/routing";
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
import { logAudit } from "../lib/audit";

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

// `filterByCaptainRadius` used to live here. It moved to ../lib/nearby so the
// OfferScheduler DO can apply the same radius rule when it re-scans for
// captains on a later wave — dispatch that respects the captain's chosen
// radius on the first wave but ignores it on the third would be worse than
// not filtering at all.

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

function osrmUrl(env: Env): string {
  return (env as Env & { OSRM_URL?: string }).OSRM_URL || "https://router.project-osrm.org";
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
      osrmUrl(env),
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
      getRoute(
        { lat: body.pickupLat, lng: body.pickupLng },
        { lat: body.dropoffLat, lng: body.dropoffLng },
        osrmUrl(c.env),
      ),
      findNearbyCaptains(c.env, city, body.pickupLat, body.pickupLng, 15).catch(
        () => [] as Awaited<ReturnType<typeof findNearbyCaptains>>,
      ),
    ]);
    const result = fareFromRoute(route, pricingFromRow(pricing));

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

    const route = await getRoute(
      { lat: body.pickupLat, lng: body.pickupLng },
      { lat: body.dropoffLat, lng: body.dropoffLng },
      osrmUrl(c.env),
    );
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
        promo_code, discount, vehicle_type_id, route_geometry,
        scheduled_for, schedule_status, waypoints, surge_multiplier,
        company_id, cost_center, billed_to_company
      ) VALUES (?, ?, 'searching', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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

    // Neighbourhood matching: the pickup's cell PLUS its 8 surrounding cells,
    // so a captain idling just over a geohash boundary is no longer invisible
    // to dispatch. Runs in parallel with the audit write above — they are
    // independent, and awaiting them serially used to add a full D1/DO
    // round-trip to every booking.
    const [discovered] = await Promise.all([
      findNearbyCaptains(c.env, city, body.pickupLat, body.pickupLng, 10),
      createdEvent,
    ]);

    // Honour each captain's own search radius before anything is sent.
    //
    // The 9-cell neighbourhood reaches ~7km, and every captain in it used to
    // get both an inbox card and an FCM push regardless of the radius they
    // had chosen in the app. That is the "trips outside my range still
    // notify me" complaint: the chips filtered one list while dispatch
    // ignored them entirely. Filtering here means an excluded trip never
    // reaches the captain on ANY channel.
    const nearbyCaptains = await filterByCaptainRadius(c.env.DB, discovered);
    const nearby = { captains: nearbyCaptains };

    // The trip stays `searching` until a captain actually names a price.
    //
    // This block used to flip it to `offered` whenever the neighbourhood
    // search came back non-empty — that is, when there was somebody to *ask*,
    // not when anybody had *answered*. `offered` therefore meant two different
    // things depending on who read it, and the rider's trip screen (which
    // titles itself off the status) announced "عروض متاحة" over an empty list.
    // `POST /trips/:id/bid` is now the only writer of `offered`, so the status
    // means exactly one thing: at least one captain has bid.
    const status: TripStatus = "searching";

    // Named `dispatched`, not `offered`: this records who the offer went out
    // to, which is not the same event as a captain responding to it.
    await logEvent(c.env.DB, tripId, "dispatched", user.id, {
      candidates: nearby.captains.map((x) => x.userId),
    });

    // Staged offer rollout — the closest captains see the offer first; the
    // rest only if nobody accepts within the grace window. Previously every
    // nearby captain got the card at once → a ~10-captain sprint on every
    // trip. The rollout lives in this trip's OfferScheduler DO, whose alarm
    // drives the next wave even after this request returns.
    //
    // Scheduled unconditionally now, including when the search found nobody.
    // The empty case used to skip this entire block: no DO, no push, and a
    // trip that reached a captain only if one happened to poll
    // GET /captain/offers. Booking from a quiet street therefore told nobody
    // at all. The scheduler re-scans on its own alarm, so a captain who comes
    // online a minute after booking still gets the offer.
    const offerPayload = {
      type: "trip.offer" as const,
      tripId,
      city,
      pickupLat: body.pickupLat,
      pickupLng: body.pickupLng,
      dropoffLat: body.dropoffLat,
      dropoffLng: body.dropoffLng,
      estimatedFare: finalEstimate,
      currency: est.fare.currency,
      at: nowIso(),
    };
    const firstWaveRoster = nearby.captains.slice(0, 10);
    const scheduler = c.env.OFFER_SCHEDULER.get(
      c.env.OFFER_SCHEDULER.idFromName(tripId),
    );
    await scheduler.fetch("https://scheduler/schedule", {
      method: "POST",
      body: JSON.stringify({
        tripId,
        captains: firstWaveRoster,
        offer: offerPayload,
        // Who this request already reached by FCM. The scheduler pushes to
        // captains it discovers later, and skipping this set is what keeps a
        // captain from being buzzed twice for the same trip.
        fcmSent: firstWaveRoster.map((cap) => cap.userId),
      }),
    });
    // FCM fanout keeps the previous blast — push is what wakes a captain
    // whose app is closed, so it still reaches everyone who could accept.
    // A no-op on an empty roster; the scheduler covers whoever turns up next.
    await Promise.all(
      firstWaveRoster.map((cap) =>
        pushToUser({
          env: c.env,
          userId: cap.userId,
          topic: "trip.offer",
          title: "رحلة جديدة متاحة",
          body: `الأجرة المتوقعة ${finalEstimate} ${est.fare.currency}. تبعد عنك ${cap.distanceKm.toFixed(1)} كم.`,
          data: { tripId, channel: "trip_offer", city },
        }).catch((e) => console.error("offer fcm failed", cap.userId, e)),
      ),
    );

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

  const updateRes = await c.env.DB.prepare(
    `UPDATE trips SET status = 'assigned', captain_id = ?, assigned_at = ?, captain_lat = ?, captain_lng = ?, updated_at = ?
     WHERE id = ? AND status IN ('searching','offered')`,
  )
    .bind(user.id, nowIso(), captain.last_lat, captain.last_lng, nowIso(), tripId)
    .run();

  if (updateRes.meta && updateRes.meta.changes === 0) {
    return c.json({ error: "Trip was already taken by another captain", code: "TRIP_TAKEN" }, 409);
  }

  await logEvent(c.env.DB, tripId, "assigned", user.id);
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

  const finalFare = trip.accepted_price ?? trip.final_fare ?? trip.estimated_fare ?? 0;
  const commission = trip.commission ?? 0;
  const captainPayout = Math.max(0, Math.round((finalFare - commission) * 100) / 100);

  const updateRes = await c.env.DB.prepare(
    `UPDATE trips SET status = 'completed', final_fare = ?, completed_at = ?, updated_at = ? WHERE id = ? AND status != 'completed'`,
  )
    .bind(finalFare, nowIso(), nowIso(), tripId)
    .run();

  if (updateRes.meta && updateRes.meta.changes === 0) {
    return c.json({ error: "Trip is already completed or state changed", code: "CONFLICT" }, 409);
  }

  await logEvent(c.env.DB, tripId, "completed", user.id, { finalFare, commission });

  // Wallet handling:
  //  - Wallet (rider): debit the rider, credit the captain's payout.
  //  - Company-billed (B2B): no rider debit; finance is collected monthly.
  //  - Cash: the captain collected the fare in hand, so DEBIT the platform
  //    commission from the captain instead of crediting a payout. Crediting
  //    here would pay the captain twice and forfeit the commission.
  // All wallet moves are keyed by idempotency_key (unique index idx_wt_idem)
  // so a retried completion cannot double-apply a balance change.
  if (trip.payment_method === "wallet" && !trip.billed_to_company && trip.rider_id) {
    const idemKey = `trip_debit:${tripId}`;
    const finalFarePiastres = Math.round(finalFare * 100);

    const debitRes = await c.env.DB.prepare(
      `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
    )
      .bind(finalFare, finalFarePiastres, nowIso(), trip.rider_id, finalFare)
      .run();

    const txnStatus = (debitRes.meta && debitRes.meta.changes === 1) ? 'settled' : 'failed';

    await c.env.DB.prepare(
      `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
       VALUES (?, ?, 'trip_payment', 'debit', ?, ?, ?, ?, ?, ?, datetime('now'))`,
    )
      .bind(id("wt"), trip.rider_id, finalFare, finalFarePiastres, tripId, idemKey, txnStatus === 'settled' ? 'رحلة مكتملة' : 'فشل الخصم - رصيد غير كافٍ', txnStatus)
      .run();
  }
  if (trip.captain_id) {
    if (trip.payment_method === "cash") {
      // Cash: the captain already collected the full fare in hand from the rider.
      // The platform is owed its commission, so debit that amount from the
      // captain's wallet instead of crediting a payout.
      const commissionPiastres = Math.round(commission * 100);
      if (commission > 0) {
        const idemKey = `trip_commission_debit:${tripId}`;
        const ins = await c.env.DB.prepare(
          `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
           VALUES (?, ?, 'commission', 'debit', ?, ?, ?, ?, 'عمولة المنصة على رحلة نقدية', 'settled', datetime('now'))`,
        )
          .bind(id("wt"), trip.captain_id, commission, commissionPiastres, tripId, idemKey)
          .run();

        // Only move the balance if this is the first time we recorded the debit.
        if (ins.meta && ins.meta.changes === 1) {
          await c.env.DB.prepare(
            `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?, wallet_updated_at = ? WHERE id = ?`,
          )
            .bind(commission, commissionPiastres, nowIso(), trip.captain_id)
            .run();
        }
      }
    } else {
      // Non-cash: the platform collected the fare, so credit the captain's payout.
      const payoutPiastres = Math.round(captainPayout * 100);
      const idemKey = `trip_payout:${tripId}`;
      const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
         VALUES (?, ?, 'commission', 'credit', ?, ?, ?, ?, 'أرباح رحلة مكتملة', 'settled', datetime('now'))`,
      )
        .bind(id("wt"), trip.captain_id, captainPayout, payoutPiastres, tripId, idemKey)
        .run();

      if (ins.meta && ins.meta.changes === 1) {
        await c.env.DB.prepare(
          `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) + ?, wallet_updated_at = ? WHERE id = ?`,
        )
          .bind(captainPayout, payoutPiastres, nowIso(), trip.captain_id)
          .run();
      }
    }
  }

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
  // mutating endpoint here broadcasts; this one did not, and the omission used
  // to be fatal: the rider mounted its offers panel only when it saw status
  // `offered`, and the 5s GET /trips/:id/bids poll lived inside that panel. No
  // broadcast → no panel → no poll → the counter-offer was never fetched, so a
  // captain who bid on a trip still in `searching` was invisible to the rider.
  //
  // That gate is gone — the offers list is mounted for the whole waiting phase
  // now, so the poll finds a bid whether or not this broadcast lands. The
  // broadcast stays because it is what keeps the rider's trip object, panel
  // heading and status pill current instead of trailing the 10s fallback poll.
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
