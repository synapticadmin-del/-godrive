import { DurableObject } from "cloudflare:workers";

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

export class OfferScheduler extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/schedule" && request.method === "POST") {
      const body = (await request.json()) as {
        tripId: string;
        captains: Wave[];
        offer: OfferPayload;
      };
      await this.ctx.storage.put("tripId", body.tripId);
      await this.ctx.storage.put("captains", body.captains);
      await this.ctx.storage.put("offer", body.offer);
      await this.ctx.storage.put("waveIndex", 0);
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
    const [tripId, captains, offer, waveIndex] = await Promise.all([
      this.ctx.storage.get<string>("tripId"),
      this.ctx.storage.get<Wave[]>("captains"),
      this.ctx.storage.get<OfferPayload>("offer"),
      this.ctx.storage.get<number>("waveIndex"),
    ]);
    if (!tripId || !captains || !offer || waveIndex == null) return;

    const wave = captains.slice(waveIndex, waveIndex + WAVE_SIZE);
    if (wave.length === 0) {
      await this.teardown();
      return;
    }

    // Push this wave to captain inboxes (best-effort; one dead inbox does not
    // hold the wave). FCM stays with the caller — see trips.ts.
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

    const nextIndex = waveIndex + WAVE_SIZE;
    await this.ctx.storage.put("waveIndex", nextIndex);
    if (nextIndex < captains.length) {
      await this.ctx.storage.setAlarm(Date.now() + WAVE_DELAY_MS);
    } else {
      // Everyone saw the offer; the rollout is done.
      await this.teardown();
    }
  }

  /** Alarm handler — drive the next wave if the trip is still open. */
  async alarm(): Promise<void> {
    const tripId = await this.ctx.storage.get<string>("tripId");
    if (!tripId) return;

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
