import { Hono } from "hono";
import { canTransition, type TripStatus } from "@synaptic-go/shared";
import type { Context } from "hono";
import { pricingFromRow } from "../lib/pricing";
import { findNearbyCaptains } from "../lib/nearby";
import { fareFromRoute, getRoute } from "../lib/routing";
import {
  createTripSchema,
  estimateTripSchema,
  cancelTripSchema,
  rateTripSchema,
  createBidSchema,
  acceptBidSchema,
} from "../lib/schemas";
import type { DbCaptain, DbPricing, DbTrip } from "../lib/types";
import { id, nowIso, resolveSearchRadiusKm } from "../lib/utils";
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

/**
 * Drop captains whose own search radius excludes this pickup.
 *
 * [findNearbyCaptains] answers "who is geographically close" from the geohash
 * neighbourhood; this answers "who actually asked for work this far out". A
 * captain hunting inside 5km must not be woken by a request 7km away — not by
 * an inbox card, not by FCM, and not by a badge on a tab.
 *
 * Best-effort by design: if the lookup fails we return the discovered list
 * untouched, because a dispatch that reaches slightly too far is recoverable
 * (the captain declines) while a dispatch that reaches nobody strands a rider.
 */
async function filterByCaptainRadius<T extends { userId: string; distanceKm: number }>(
  db: D1Database,
  captains: T[],
): Promise<T[]> {
  if (captains.length === 0) return captains;
  try {
    const placeholders = captains.map(() => "?").join(", ");
    const rows = await db
      .prepare(
        `SELECT user_id, search_radius_km FROM captains WHERE user_id IN (${placeholders})`,
      )
      .bind(...captains.map((cap) => cap.userId))
      .all<{ user_id: string; search_radius_km: number | null }>();

    const radiusByUser = new Map(
      (rows.results ?? []).map((row) => [row.user_id, resolveSearchRadiusKm(row.search_radius_km)]),
    );

    return captains.filter(
      (cap) => cap.distanceKm <= resolveSearchRadiusKm(radiusByUser.get(cap.userId)),
    );
  } catch (e) {
    console.error("captain radius filter failed", e);
    return captains;
  }
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

async function broadcastTrip(env: Env, trip: DbTrip) {
  const room = env.TRIP_ROOM.get(env.TRIP_ROOM.idFromName(trip.id));
  await room.fetch("https://room/broadcast", {
    method: "POST",
    body: JSON.stringify({ type: "trip.updated", trip }),
  });
  await room.fetch("https://room/state", {
    method: "PUT",
    body: JSON.stringify(trip),
  });
}

function osrmUrl(env: Env): string {
  return (env as Env & { OSRM_URL?: string }).OSRM_URL || "https://router.project-osrm.org";
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

    let status: TripStatus = "searching";
    if (nearby.captains?.length) {
      status = "offered";
      await c.env.DB.prepare(`UPDATE trips SET status = 'offered', updated_at = ? WHERE id = ?`)
        .bind(nowIso(), tripId)
        .run();
      await logEvent(c.env.DB, tripId, "offered", user.id, {
        candidates: nearby.captains.map((x) => x.userId),
      });

      // Staged offer rollout — the closest captains see the offer first;
      // the rest only if nobody accepts within the grace window.
      // Previously every nearby captain got the card at once → a ~10-captain
      // sprint on every trip. The rollout lives in this trip's OfferScheduler
      // DO, whose alarm drives the next wave even after this request returns.
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
      const scheduler = c.env.OFFER_SCHEDULER.get(
        c.env.OFFER_SCHEDULER.idFromName(tripId),
      );
      await scheduler.fetch("https://scheduler/schedule", {
        method: "POST",
        body: JSON.stringify({
          tripId,
          captains: nearby.captains.slice(0, 10),
          offer: offerPayload,
        }),
      });
      // FCM fanout keeps the previous blast — push is what wakes a captain
      // whose app is closed, so it still reaches everyone who could accept.
      await Promise.all(
        nearby.captains.slice(0, 10).map((cap) =>
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
    }

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

  return c.json({ trip, events: events.results ?? [], geometry });
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

  const trip = await c.env.DB.prepare(`SELECT rider_id FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<{ rider_id: string }>();

  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);

  if (user.role !== "admin" && trip.rider_id !== user.id) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const bids = await c.env.DB.prepare(
    `SELECT b.id, b.trip_id, b.captain_id, b.counter_price, b.status, b.created_at,
            u.name as captain_name, u.phone as captain_phone,
            c.vehicle_make, c.vehicle_model, c.vehicle_plate, c.vehicle_color, c.rating_avg, c.rating_count,
            c.last_lat as captain_lat, c.last_lng as captain_lng
     FROM trip_bids b
     JOIN users u ON b.captain_id = u.id
     LEFT JOIN captains c ON b.captain_id = c.user_id
     WHERE b.trip_id = ? AND b.status = 'pending'
     ORDER BY b.created_at DESC`
  )
    .bind(tripId)
    .all();

  return c.json({ bids: bids.results || [] });
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
