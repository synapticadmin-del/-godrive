/**
 * Trip dispatch — captain discovery, radius filtering and the staged offer rollout.
 *
 * Lifted verbatim out of the `POST /trips` handler in `routes/trips.ts`
 * (lines 513-586 at base `b0c0866`, unchanged at `f58f227`), together with the
 * `filterByCaptainRadius` helper it was the only caller of (lines 34-71).
 * This is E03, a pure structural pass: the code moved, nothing in it changed.
 *
 * Why it moved: `trips.ts` is touched by 55 planned items and 6 of the 16 gate
 * items. Dispatch had to come out before E09 can change dispatch behaviour and
 * E08 can change settlement, without the two rebasing on top of each other.
 * T16's P0.2 proposes this extraction in exactly this form.
 *
 * Mechanical renames on the way across, and nothing else: `c.env` became the
 * `env` parameter, the four `body.*` coordinates and `finalEstimate` /
 * `est.fare.currency` / `user.id` became named parameters, and `createdEvent`
 * became `pendingEvent`. Every conditional, every await point, both
 * `nowIso()` call sites and the `slice(0, 10)` bounds are unchanged.
 *
 * **`logEvent` is injected rather than imported.** It lives in `trips.ts` and
 * has eight other call sites there that have nothing to do with dispatch, so
 * importing it here would either duplicate the `trip_events` INSERT or create
 * a `lib/ -> routes/` import cycle. Passing it in keeps this module callable
 * from the cron as the brief requires. If a future task wants a shared trip-
 * event writer it belongs in its own `lib/tripEvents.ts` — a path in nobody's
 * `owns:` today, so E03 did not create it.
 */

import type { TripStatus } from "@synaptic-go/shared";
import { findNearbyCaptains, type NearbyCaptain } from "./nearby";
import { pushToUser } from "./notifications";
import { nowIso, resolveSearchRadiusKm } from "./utils";

/** The `trip_events` writer, supplied by the caller. Signature matches `logEvent` in `routes/trips.ts`. */
export type TripEventWriter = (
  db: D1Database,
  tripId: string,
  type: string,
  actorId?: string,
  payload?: unknown,
) => Promise<void>;

export type DispatchTripInput = {
  env: Env;
  tripId: string;
  city: string;
  pickupLat: number;
  pickupLng: number;
  dropoffLat: number;
  dropoffLng: number;
  /** The post-discount estimate the rider was quoted. */
  estimatedFare: number;
  currency: string;
  /** Actor recorded on the `offered` trip event. */
  actorId?: string;
  /**
   * A write already in flight that the original code awaited *in parallel*
   * with captain discovery. Passing it in preserves that concurrency exactly;
   * awaiting it before the call would add a D1 round-trip to every booking.
   */
  pendingEvent?: Promise<void>;
  logEvent: TripEventWriter;
};

export type DispatchTripResult = {
  /** `"offered"` when at least one captain survived the radius filter, else `"searching"`. */
  status: TripStatus;
  captains: NearbyCaptain[];
};

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

/**
 * Discover captains for a trip, filter them by their own search radius, and
 * roll the offer out to the closest ten.
 *
 * Returns the status the trip now has and the captains that were offered it,
 * which is exactly what the `POST /trips` response body needs.
 */
export async function dispatchTrip({
  env,
  tripId,
  city,
  pickupLat,
  pickupLng,
  dropoffLat,
  dropoffLng,
  estimatedFare,
  currency,
  actorId,
  pendingEvent,
  logEvent,
}: DispatchTripInput): Promise<DispatchTripResult> {
  // Neighbourhood matching: the pickup's cell PLUS its 8 surrounding cells,
  // so a captain idling just over a geohash boundary is no longer invisible
  // to dispatch. Runs in parallel with the audit write above — they are
  // independent, and awaiting them serially used to add a full D1/DO
  // round-trip to every booking.
  const [discovered] = await Promise.all([
    findNearbyCaptains(env, city, pickupLat, pickupLng, 10),
    pendingEvent,
  ]);

  // Honour each captain's own search radius before anything is sent.
  //
  // The 9-cell neighbourhood reaches ~7km, and every captain in it used to
  // get both an inbox card and an FCM push regardless of the radius they
  // had chosen in the app. That is the "trips outside my range still
  // notify me" complaint: the chips filtered one list while dispatch
  // ignored them entirely. Filtering here means an excluded trip never
  // reaches the captain on ANY channel.
  const nearbyCaptains = await filterByCaptainRadius(env.DB, discovered);
  const nearby = { captains: nearbyCaptains };

  let status: TripStatus = "searching";
  if (nearby.captains?.length) {
    status = "offered";
    await env.DB.prepare(`UPDATE trips SET status = 'offered', updated_at = ? WHERE id = ?`)
      .bind(nowIso(), tripId)
      .run();
    await logEvent(env.DB, tripId, "offered", actorId, {
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
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      estimatedFare: estimatedFare,
      currency: currency,
      at: nowIso(),
    };
    const scheduler = env.OFFER_SCHEDULER.get(
      env.OFFER_SCHEDULER.idFromName(tripId),
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
          env: env,
          userId: cap.userId,
          topic: "trip.offer",
          title: "رحلة جديدة متاحة",
          body: `الأجرة المتوقعة ${estimatedFare} ${currency}. تبعد عنك ${cap.distanceKm.toFixed(1)} كم.`,
          data: { tripId, channel: "trip_offer", city },
        }).catch((e) => console.error("offer fcm failed", cap.userId, e)),
      ),
    );
  }

  return { status, captains: nearby.captains };
}
