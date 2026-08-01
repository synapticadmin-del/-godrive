import { DurableObject } from "cloudflare:workers";
import { haversineKm } from "@synaptic-go/shared";

type CaptainPresence = {
  userId: string;
  lat: number;
  lng: number;
  lastSeen: number;
  name?: string | null;
};

/**
 * How long a presence record counts as live for matching. A captain who has
 * not been heard from in this long stops being offered work.
 *
 * This window was never the bug. The bug was that the captain app only
 * published on 50 m of movement with no time floor, so a *stationary* captain
 * — parked at a rank, waiting at a light, sitting outside a school — emitted
 * nothing and aged out while still online and still willing (F-06-02). E11
 * adds an unconditional client heartbeat well inside this window; the window
 * itself is left where it is, because 120 s of silence genuinely is stale.
 */
const PRESENCE_MAX_AGE_MS = 120_000;

/** Records older than this are deleted outright by the sweep alarm. */
const PRESENCE_EVICT_MS = 180_000;

/** How often the sweep alarm runs while any captain is in this cell. */
const SWEEP_INTERVAL_MS = 60_000;

/**
 * Location-publish rate limit, per captain, enforced here.
 *
 * It used to live in the KV-backed `rateLimit()` middleware, which cost a read
 * and a write on every single location POST — the highest-frequency authorised
 * request in the product (T24 P0.3). The request already has to reach this
 * Durable Object to record presence, so the counter rides along for free.
 *
 * The counter is deliberately **in memory**, not in `ctx.storage`: persisting
 * it would reintroduce exactly the per-write cost the move is meant to remove.
 * The consequence of an eviction is that a captain gets a fresh window early,
 * which is the harmless direction for a rate limit to fail in. The consequence
 * of a cell handoff is the same — see the note on `/heartbeat` below.
 */
const RATE_LIMIT = 30;
const RATE_WINDOW_MS = 60_000;

/**
 * The pace the server would like clients to publish at, advertised in the
 * heartbeat response so the app can pace itself from the server's own budget
 * instead of hard-coding a number that drifts out of step with this one.
 * Two thirds of the raw budget, leaving headroom for /online, retries and the
 * occasional burst on a cell handoff.
 */
const RECOMMENDED_MIN_PUBLISH_INTERVAL_MS = Math.ceil(
  RATE_WINDOW_MS / (RATE_LIMIT * (2 / 3)),
);

type RateWindow = { startedAt: number; count: number };

/**
 * One Durable Object per geohash cell in a city.
 * Tracks online captains for matching, and paces their location publishes.
 */
export class GeoCell extends DurableObject<Env> {
  /**
   * userId → fixed window. In memory on purpose (see RATE_LIMIT above).
   * Bounded by the number of captains in one cell, and pruned on sweep.
   */
  private rateWindows: Map<string, RateWindow> = new Map();

  /**
   * Account one request against the captain's window.
   * Returns whether the caller should be allowed to do the expensive work.
   */
  private admit(userId: string, now: number): {
    allowed: boolean;
    count: number;
    retryAfterSec: number;
  } {
    const window = this.rateWindows.get(userId);

    if (!window || now - window.startedAt >= RATE_WINDOW_MS) {
      this.rateWindows.set(userId, { startedAt: now, count: 1 });
      return { allowed: true, count: 1, retryAfterSec: 0 };
    }

    window.count += 1;
    if (window.count > RATE_LIMIT) {
      const retryAfterMs = window.startedAt + RATE_WINDOW_MS - now;
      return {
        allowed: false,
        count: window.count,
        retryAfterSec: Math.max(1, Math.ceil(retryAfterMs / 1000)),
      };
    }

    return { allowed: true, count: window.count, retryAfterSec: 0 };
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/heartbeat" && request.method === "POST") {
      const body = await request.json<CaptainPresence & { rateLimit?: boolean }>();
      const now = Date.now();

      // `rateLimit: false` is for the /online transition, which is a
      // deliberate user action rather than a stream of fixes and must never be
      // refused because the location stream was chatty a moment earlier.
      const enforce = body.rateLimit !== false;
      const verdict = enforce
        ? this.admit(body.userId, now)
        : { allowed: true, count: 0, retryAfterSec: 0 };

      if (!verdict.allowed) {
        // Deliberately no storage write. The last one was at most a couple of
        // seconds ago — far inside PRESENCE_MAX_AGE_MS — so presence stays
        // accurate while the write cost disappears. Skipping the write *is*
        // the saving; throttling that still wrote would save nothing.
        return Response.json(
          {
            ok: false,
            throttled: true,
            retryAfterSec: verdict.retryAfterSec,
            minPublishIntervalMs: RECOMMENDED_MIN_PUBLISH_INTERVAL_MS,
          },
          { status: 429, headers: { "Retry-After": String(verdict.retryAfterSec) } },
        );
      }

      const key = `captain:${body.userId}`;
      const record: CaptainPresence = {
        userId: body.userId,
        lat: body.lat,
        lng: body.lng,
        lastSeen: now,
        name: body.name ?? null,
      };
      await this.ctx.storage.put(key, record);

      const currentAlarm = await this.ctx.storage.getAlarm();
      if (currentAlarm == null) {
        await this.ctx.storage.setAlarm(now + SWEEP_INTERVAL_MS);
      }

      return Response.json({
        ok: true,
        throttled: false,
        minPublishIntervalMs: RECOMMENDED_MIN_PUBLISH_INTERVAL_MS,
      });
    }

    if (url.pathname === "/offline" && request.method === "POST") {
      const body = await request.json<{ userId: string }>();
      await this.ctx.storage.delete(`captain:${body.userId}`);
      this.rateWindows.delete(body.userId);
      return Response.json({ ok: true });
    }

    if (url.pathname === "/nearby" && request.method === "GET") {
      const lat = Number(url.searchParams.get("lat"));
      const lng = Number(url.searchParams.get("lng"));
      const limit = Number(url.searchParams.get("limit") || "10");
      const maxAgeMs = Number(
        url.searchParams.get("maxAgeMs") || String(PRESENCE_MAX_AGE_MS),
      );

      const list = await this.ctx.storage.list<CaptainPresence>({ prefix: "captain:" });
      const now = Date.now();
      const captains: Array<CaptainPresence & { distanceKm: number }> = [];

      for (const [, c] of list) {
        if (now - c.lastSeen > maxAgeMs) continue;
        const distanceKm = haversineKm({ lat, lng }, { lat: c.lat, lng: c.lng });
        captains.push({ ...c, distanceKm });
      }

      captains.sort((a, b) => a.distanceKm - b.distanceKm);
      return Response.json({ captains: captains.slice(0, limit) });
    }

    return new Response("GeoCell: /heartbeat /offline /nearby", { status: 400 });
  }

  async alarm() {
    const list = await this.ctx.storage.list<CaptainPresence>({ prefix: "captain:" });
    const now = Date.now();
    const toDelete: string[] = [];
    for (const [key, c] of list) {
      if (now - c.lastSeen > PRESENCE_EVICT_MS) {
        toDelete.push(key);
        this.rateWindows.delete(c.userId);
      }
    }
    if (toDelete.length) await this.ctx.storage.delete(toDelete);

    // Drop rate windows for captains who have gone quiet, so the map cannot
    // grow without bound in a busy cell.
    for (const [userId, window] of this.rateWindows) {
      if (now - window.startedAt > RATE_WINDOW_MS * 2) this.rateWindows.delete(userId);
    }

    const remaining = await this.ctx.storage.list({ prefix: "captain:" });
    if ([...remaining.keys()].length > 0) {
      await this.ctx.storage.setAlarm(now + SWEEP_INTERVAL_MS);
    }
  }
}
