import { DurableObject } from "cloudflare:workers";
import { filterByCaptainRadius, findNearbyCaptains } from "../lib/nearby";
import { pushToUser } from "../lib/notifications";

/**
 * OfferScheduler — one DO per trip, drives the staged offer rollout.
 *
 * The Problem
 * -----------
 * After the neighbourhood search expanded dispatch to 9 geohash cells,
 * `POST /trips` pushed the offer to every nearby captain (up to 10) **at the
 * same moment**. Acceptance turned into a race between ~10 captains: all of
 * them get the card, one wins the conditional update, and the rest open a
 * trip that was already taken (or eat a 409).
 *
 * The Fix — staged rollout ("wave" dispatch, the inDrive/Uber pattern)
 * --------------------------------------------------------------------
 * The offer is released to captains in distance-ordered waves:
 *   wave 1  → the closest 3 captains, immediately
 *   wave 2  → next 3, after WAVE_DELAY_MS with no acceptance
 *   wave 3+ → the rest, one wave at a time
 * Captains are typically minutes apart in a cell, so the closest captain
 * almost always accepts during the grace window — the outer waves simply
 * never fire, and 7 fewer captains see a card they can lose on.
 *
 * Scheduling survives the request lifecycle: each trip's rollout lives in
 * its own DO, and the next wave is driven by a Durable Object **alarm** —
 * the only worker-side timer guaranteed to survive a deployed isolate
 * (ctx.waitUntil would silently stop ~30s after the response).
 *
 * Re-scanning: dispatch is a standing order, not a one-shot
 * --------------------------------------------------------
 * `POST /trips` runs the neighbourhood search exactly once, at the instant
 * the rider taps request. That used to be the only search a trip ever got,
 * and the route skipped this DO entirely when the search came back empty. So
 * a rider booking from a quiet street at 2am was dispatched to nobody, and a
 * captain who came online ten seconds later never learned the trip existed —
 * they could only stumble on it via the `GET /captain/offers` poll.
 *
 * The rollout is now scheduled for *every* trip, and when the roster runs dry
 * this DO searches again on its own alarm (same radius rule, via
 * `filterByCaptainRadius`) until the trip is taken, cancelled, or SEARCH_TTL_MS
 * elapses. Captains discovered on a re-scan also get FCM, because the caller
 * only pushed to the roster it found itself and an inbox card does not wake a
 * closed app — `fcmSent` carries that set forward so nobody is buzzed twice.
 *
 * Cancellation reaches exactly the audience that saw the offer
 * -----------------------------------------------------------
 * `POST /trips/:id/cancel` fans out to the same neighbourhood (a wider
 * sweep). It also POSTs /cancel here, which tears down the rollout state
 * and cancels any pending alarm — so no wave fires after the trip died.
 *
 * Safety on every wave
 * --------------------
 * Before pushing, the alarm re-reads the trip status from D1 and stops the
 * rollout the moment the trip left searching/offered (accepted, completed,
 * cancelled) — the DO cannot offer a trip that is no longer available even
 * if the cancel/teardown message raced with the alarm.
 */

type Wave = {
  userId: string;
  distanceKm: number;
  name?: string | null;
};

type OfferPayload = {
  type: "trip.offer";
  tripId: string;
  city: string;
  pickupLat: number;
  pickupLng: number;
  dropoffLat: number;
  dropoffLng: number;
  estimatedFare: number;
  currency: string;
  at: string;
};

const WAVE_SIZE = 3;
const WAVE_DELAY_MS = 15_000;

/**
 * How long to keep hunting for a captain before abandoning the rollout.
 *
 * The alarm's status check ends most rollouts (accepted / cancelled). This is
 * the backstop for the trip nobody takes and the rider never cancels — without
 * it the DO would re-scan on a 15s alarm forever.
 */
const SEARCH_TTL_MS = 5 * 60_000;

export class OfferScheduler extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/schedule" && request.method === "POST") {
      const body = (await request.json()) as {
        tripId: string;
        captains: Wave[];
        offer: OfferPayload;
        /** Captains the caller has already reached by FCM. */
        fcmSent?: string[];
      };
      await this.ctx.storage.put("tripId", body.tripId);
      await this.ctx.storage.put("captains", body.captains);
      await this.ctx.storage.put("offer", body.offer);
      await this.ctx.storage.put("waveIndex", 0);
      await this.ctx.storage.put("fcmSent", body.fcmSent ?? []);
      await this.ctx.storage.put("startedAt", Date.now());
      await this.pushWave();
      return Response.json({ ok: true, captains: body.captains.length });
    }

    if (url.pathname === "/cancel" && request.method === "POST") {
      await this.teardown();
      return Response.json({ ok: true });
    }

    return new Response("OfferScheduler: POST /schedule | POST /cancel", { status: 400 });
  }

  /** Fire the current wave and arm the next alarm. */
  private async pushWave(): Promise<void> {
    const [tripId, storedCaptains, offer, waveIndex, startedAt, fcmSent] = await Promise.all([
      this.ctx.storage.get<string>("tripId"),
      this.ctx.storage.get<Wave[]>("captains"),
      this.ctx.storage.get<OfferPayload>("offer"),
      this.ctx.storage.get<number>("waveIndex"),
      this.ctx.storage.get<number>("startedAt"),
      this.ctx.storage.get<string[]>("fcmSent"),
    ]);
    if (!tripId || !storedCaptains || !offer || waveIndex == null) return;

    let roster = storedCaptains;
    let wave = roster.slice(waveIndex, waveIndex + WAVE_SIZE);

    if (wave.length === 0) {
      // The roster is spent — or was empty from the start, which is exactly
      // what happens when the rider books with no captain in the
      // neighbourhood. Either way, look again before giving up.
      if (this.expired(startedAt)) {
        await this.teardown();
        return;
      }

      const found = await this.rescan(roster, offer);
      if (found.length === 0) {
        // Nobody has come online yet. Sleep a wave and search again.
        await this.ctx.storage.setAlarm(Date.now() + WAVE_DELAY_MS);
        return;
      }

      roster = [...roster, ...found];
      await this.ctx.storage.put("captains", roster);
      wave = roster.slice(waveIndex, waveIndex + WAVE_SIZE);
    }

    // Push this wave to captain inboxes (best-effort; one dead inbox does not
    // hold the wave).
    await Promise.all(
      wave.map(async (cap) => {
        try {
          const inbox = this.env.CAPTAIN_INBOX.get(this.env.CAPTAIN_INBOX.idFromName(cap.userId));
          await inbox.fetch("https://inbox/push", {
            method: "POST",
            body: JSON.stringify({ ...offer, distanceKm: cap.distanceKm }),
          });
        } catch (e) {
          console.error("offer wave push failed", cap.userId, e);
        }
      }),
    );

    // FCM for anyone this trip has not already buzzed. `POST /trips` pushes to
    // the roster it discovered itself and declares that set in `fcmSent`;
    // captains found by a re-scan have had no push at all, and an inbox card
    // alone will not wake a captain whose app is closed.
    const pushedAlready = new Set(fcmSent ?? []);
    const needPush = wave.filter((cap) => !pushedAlready.has(cap.userId));
    if (needPush.length) {
      await Promise.all(
        needPush.map((cap) =>
          pushToUser({
            env: this.env,
            userId: cap.userId,
            topic: "trip.offer",
            title: "رحلة جديدة متاحة",
            body: `الأجرة المتوقعة ${offer.estimatedFare} ${offer.currency}. تبعد عنك ${cap.distanceKm.toFixed(1)} كم.`,
            data: { tripId, channel: "trip_offer", city: offer.city },
          }).catch((e) => console.error("offer wave fcm failed", cap.userId, e)),
        ),
      );
      for (const cap of needPush) pushedAlready.add(cap.userId);
      await this.ctx.storage.put("fcmSent", [...pushedAlready]);
    }

    await this.ctx.storage.put("waveIndex", waveIndex + WAVE_SIZE);

    // Always come back: either to drive the next wave, or to re-scan once the
    // roster runs dry. This is deliberately unconditional now — the old code
    // tore the rollout down the moment the initial roster was exhausted, which
    // is what made dispatch a single snapshot of who happened to be online at
    // booking time. `alarm()` ends the rollout instead, as soon as the trip
    // leaves searching/offered or the TTL expires.
    await this.ctx.storage.setAlarm(Date.now() + WAVE_DELAY_MS);
  }

  /**
   * Search the neighbourhood again, dropping captains already on the roster.
   *
   * Applies the same `filterByCaptainRadius` rule as the initial dispatch, so
   * a captain who limited themselves to 5km is not handed a 7km pickup just
   * because they arrived late.
   */
  private async rescan(known: Wave[], offer: OfferPayload): Promise<Wave[]> {
    try {
      const discovered = await findNearbyCaptains(
        this.env,
        offer.city,
        offer.pickupLat,
        offer.pickupLng,
        10,
      );
      const eligible = await filterByCaptainRadius(this.env.DB, discovered);
      const seen = new Set(known.map((cap) => cap.userId));
      return eligible
        .filter((cap) => !seen.has(cap.userId))
        .map((cap) => ({
          userId: cap.userId,
          distanceKm: cap.distanceKm,
          name: cap.name ?? null,
        }));
    } catch (e) {
      // A failed re-scan is not fatal: the next alarm tries again.
      console.error("offer rescan failed", e);
      return [];
    }
  }

  /** True once the rollout has been hunting longer than [SEARCH_TTL_MS]. */
  private expired(startedAt?: number): boolean {
    if (startedAt == null) return false;
    return Date.now() - startedAt > SEARCH_TTL_MS;
  }

  /** Alarm handler — drive the next wave if the trip is still open. */
  async alarm(): Promise<void> {
    const [tripId, startedAt] = await Promise.all([
      this.ctx.storage.get<string>("tripId"),
      this.ctx.storage.get<number>("startedAt"),
    ]);
    if (!tripId) return;

    if (this.expired(startedAt)) {
      await this.teardown();
      return;
    }

    const trip = await this.env.DB.prepare(
      `SELECT status FROM trips WHERE id = ?`,
    )
      .bind(tripId)
      .first<{ status: string }>();

    if (!trip || !["searching", "offered"].includes(trip.status)) {
      // Accepted / completed / cancelled — stop offering.
      await this.teardown();
      return;
    }

    await this.pushWave();
  }

  /** Drop rollout state and cancel any pending alarm. */
  private async teardown(): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }
}
