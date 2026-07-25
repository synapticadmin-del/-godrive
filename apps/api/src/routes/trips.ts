import { Hono } from "hono";
import { canTransition, type TripStatus } from "@synaptic-go/shared";
import type { Context } from "hono";
import { pricingFromRow, cellKey } from "../lib/pricing";
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

    const route = await getRoute(
      { lat: body.pickupLat, lng: body.pickupLng },
      { lat: body.dropoffLat, lng: body.dropoffLng },
      osrmUrl(c.env),
    );
    const result = fareFromRoute(route, pricingFromRow(pricing));

    return c.json({ city, ...result });
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

    await logEvent(c.env.DB, tripId, "created", user.id, {
      estimate: est.fare,
      discount,
      promoCode,
      routeSource: est.source,
    });

    const key = cellKey(city, body.pickupLat, body.pickupLng);
    const cell = c.env.GEO_CELL.get(c.env.GEO_CELL.idFromName(key));
    const nearbyRes = await cell.fetch(
      `https://cell/nearby?lat=${body.pickupLat}&lng=${body.pickupLng}&limit=10`,
    );
    const nearby = (await nearbyRes.json()) as {
      captains: Array<{ userId: string; distanceKm: number }>;
    };

    let status: TripStatus = "searching";
    if (nearby.captains?.length) {
      status = "offered";
      await c.env.DB.prepare(`UPDATE trips SET status = 'offered', updated_at = ? WHERE id = ?`)
        .bind(nowIso(), tripId)
        .run();
      await logEvent(c.env.DB, tripId, "offered", user.id, {
        candidates: nearby.captains.map((x) => x.userId),
      });

      // Push live offers to nearby captains' inboxes
      const offerPayload = {
        type: "trip.offer",
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
      await Promise.all(
        nearby.captains.slice(0, 10).map(async (cap) => {
          try {
            const inbox = c.env.CAPTAIN_INBOX.get(c.env.CAPTAIN_INBOX.idFromName(cap.userId));
            await inbox.fetch("https://inbox/push", {
              method: "POST",
              body: JSON.stringify({ ...offerPayload, distanceKm: cap.distanceKm }),
            });
          } catch (e) {
            console.error("offer push failed", cap.userId, e);
          }
          // FCM push so the captain sees the new offer even with app closed
          await pushToUser({
            env: c.env,
            userId: cap.userId,
            topic: "trip.offer",
            title: "رحلة جديدة متاحة",
            body: `الأجرة المتوقعة ${finalEstimate} ${est.fare.currency}. تبعد عنك ${cap.distanceKm.toFixed(1)} كم.`,
            data: { tripId, channel: "trip_offer", city },
          });
        }),
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
    q = c.env.DB.prepare(
      `SELECT * FROM trips WHERE captain_id = ? OR status IN ('searching','offered')
       ORDER BY created_at DESC LIMIT 50`,
    ).bind(user.id);
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

  await c.env.DB.prepare(
    `UPDATE trips SET status = 'assigned', captain_id = ?, assigned_at = ?, captain_lat = ?, captain_lng = ?, updated_at = ?
     WHERE id = ? AND status IN ('searching','offered')`,
  )
    .bind(user.id, nowIso(), captain.last_lat, captain.last_lng, nowIso(), tripId)
    .run();

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
  //  - If paying from wallet (rider): debit rider, credit captain (commission separate).
  //  - If company-billed (B2B): no rider debit; finance is collected monthly.
  //  - Cash: no wallet writes here — commission is logged only.
  if (trip.payment_method === "wallet" && !trip.billed_to_company && trip.rider_id) {
    const idemKey = `trip_debit:${tripId}`;
    const finalFarePiastres = Math.round(finalFare * 100);

    const ins = await c.env.DB.prepare(
      `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
       VALUES (?, ?, 'trip_payment', 'debit', ?, ?, ?, ?, 'رحلة مكتملة', 'settled', datetime('now'))`,
    )
      .bind(id("wt"), trip.rider_id, finalFare, finalFarePiastres, tripId, idemKey)
      .run();

    if (!ins.meta || ins.meta.changes > 0) {
      await c.env.DB.prepare(
        `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
      )
        .bind(finalFare, finalFarePiastres, nowIso(), trip.rider_id, finalFare)
        .run();
    }
  }
  if (trip.captain_id) {
    await c.env.DB.prepare(
      `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, trip_id, note, status, created_at)
       VALUES (?, ?, 'commission', 'credit', ?, ?, 'أرباح رحلة مكتملة', 'settled', datetime('now'))`,
    )
      .bind(id("wt"), trip.captain_id, captainPayout, tripId)
      .run();
    await c.env.DB.prepare(
      `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_updated_at = ? WHERE id = ?`,
    )
      .bind(captainPayout, nowIso(), trip.captain_id)
      .run();
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
    await pushToUser({
      env: c.env,
      userId: updated.captain_id,
      topic: "trip.completed",
      title: "اكتملت الرحلة",
      body: `أرباحك من هذه الرحلة ${captainPayout} ج.م.`,
      data: { tripId, payout: String(captainPayout) },
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

  await logEvent(c.env.DB, tripId, "bid.created", user.id, {
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
    data: { tripId, bidId, counterPrice: String(body.counterPrice) },
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

  const selectedBid = await c.env.DB.prepare(`SELECT * FROM trip_bids WHERE id = ? AND trip_id = ?`)
    .bind(body.bidId, tripId)
    .first<{ id: string; captain_id: string; counter_price: number }>();

  if (!selectedBid) {
    return c.json({ error: "Bid not found", code: "BID_NOT_FOUND" }, 404);
  }

  const acceptedPrice = selectedBid.counter_price;
  const pricing = await getPricing(c.env.DB, trip.city);
  const commissionRate = pricing?.commission_rate || 0.2;
  const commission = Math.round(acceptedPrice * commissionRate * 100) / 100;

  // Assign captain and set agreed price
  await c.env.DB.prepare(
    `UPDATE trips SET captain_id = ?, accepted_price = ?, final_fare = ?, commission = ?, status = 'assigned', assigned_at = ?, updated_at = ?
     WHERE id = ?`
  )
    .bind(selectedBid.captain_id, acceptedPrice, acceptedPrice, commission, nowIso(), nowIso(), tripId)
    .run();

  // Mark selected bid as accepted, others as rejected
  await c.env.DB.prepare(`UPDATE trip_bids SET status = 'accepted' WHERE id = ?`).bind(body.bidId).run();
  await c.env.DB.prepare(`UPDATE trip_bids SET status = 'rejected' WHERE trip_id = ? AND id != ?`)
    .bind(tripId, body.bidId)
    .run();

  await logEvent(c.env.DB, tripId, "bid.accepted", user.id, {
    bidId: body.bidId,
    captainId: selectedBid.captain_id,
    acceptedPrice,
  });

  const updatedTrip = await c.env.DB.prepare(`SELECT * FROM trips WHERE id = ?`).bind(tripId).first<DbTrip>();
  if (updatedTrip) await broadcastTrip(c.env, updatedTrip);

  // Notify assigned Captain
  await pushToUser({
    env: c.env,
    userId: selectedBid.captain_id,
    topic: "trip.assigned",
    title: "تم قبول عرضك!",
    body: `وافق الراكب على عرضك بمبلغ ${acceptedPrice} ج.م. توجه لموقع الانطلاق.`,
    data: { tripId, acceptedPrice: String(acceptedPrice) },
  });

  return c.json({ ok: true, trip: updatedTrip });
});
