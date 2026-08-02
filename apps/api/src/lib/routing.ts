/**
 * Routing — and the difference between a route and a guess.
 *
 * Closes the definition half of launch-gate **item 11**: *"no price is ever
 * computed off a straight line"*.
 *
 * ## What was wrong
 *
 * `getRoute` defaulted to `https://router.project-osrm.org` — the public demo
 * server, whose usage policy forbids this use and permits withdrawal without
 * notice — and wrapped the whole call in a bare `catch` that silently
 * substituted `haversine × 1.35`. Because a negotiated fare is never
 * recomputed, that estimate **becomes the settled price** (F-21-02). The plan
 * calls it exactly right: a permanent mispricing engine with no metric
 * distinguishing the two states. It is also a transfer of precise trip
 * coordinates to an uncontracted third party (F-25-08), and a single point of
 * failure for the whole booking flow.
 *
 * ## What this file can and cannot fix
 *
 * Three things change here: there is no public default any more, the fallback
 * is now **optional and loud** instead of mandatory and silent, and the engine
 * that answered is reported so it can be persisted.
 *
 * What it cannot do is decide the policy at the call sites. `routes/trips.ts`
 * is **E09's** file and this task must be safe to merge with it untouched, so:
 *
 *   - `allowFallback` **defaults to `true`, today's exact behaviour**. E09
 *     flips booking to `false`.
 *   - `resolveOsrmBaseUrl()` is exported for E09 to replace its own local
 *     `osrmUrl()` helper (`trips.ts:139-141`), which still carries a hardcoded
 *     `|| "https://router.project-osrm.org"`. **Until E09 adopts it, an unset
 *     `OSRM_URL` still reaches the public server** — see the PR.
 *
 * Gate item 11 is therefore **not closed by this file alone**.
 */

import {
  calculateFare,
  estimateDurationMin,
  haversineKm,
  type PricingRule,
} from "@synaptic-go/shared";
import { counter, logWarn } from "./log";

/**
 * Which engine produced a distance.
 *
 * Persisted to `trips.route_source` by migration `0023`. That column's CHECK
 * also permits `'cached'`, reserved for a future route cache; nothing emits it
 * today and it is deliberately absent from this union rather than being a
 * variant no code produces.
 */
export type RouteSource = "osrm" | "haversine";

export type RouteResult = {
  distanceKm: number;
  durationMin: number;
  geometry: Array<[number, number]>; // [lat, lng]
  source: RouteSource;
};

export type RouteOptions = {
  /**
   * Whether a routing failure may be answered with `haversine × 1.35`.
   *
   * **Defaults to `true`, which is exactly the behaviour before this task** —
   * the existing call sites in `trips.ts` are E09's and must keep working
   * untouched. Pass `false` on any path where the number becomes a price: the
   * call then raises {@link RouteUnavailableError} instead of quietly guessing.
   */
  allowFallback?: boolean;
};

/**
 * The public demo server. Named here so it can be *detected*, not used.
 *
 * There is deliberately no `DEFAULT_OSRM` constant any more: `osrmBaseUrl` is a
 * required argument, so a caller cannot omit it and silently inherit a public
 * endpoint. That is the type-level half of "fail closed".
 */
export const PUBLIC_OSRM_HOST = "router.project-osrm.org";

/** Raised when a route was required and could not be obtained. */
export class RouteUnavailableError extends Error {
  readonly code = "ROUTE_UNAVAILABLE";
  /** The underlying cause, for the log line — not for the client. */
  readonly reason: string;

  constructor(reason: string) {
    super(`ROUTE_UNAVAILABLE: ${reason}`);
    this.name = "RouteUnavailableError";
    this.reason = reason;
  }
}

function isPublicOsrm(baseUrl: string): boolean {
  try {
    return new URL(baseUrl).hostname.endsWith(PUBLIC_OSRM_HOST);
  } catch {
    return baseUrl.includes(PUBLIC_OSRM_HOST);
  }
}

/**
 * The correct way to find the routing engine — **the seam E09 should adopt.**
 *
 * `trips.ts:139-141` currently does:
 *
 *     return (env as Env & { OSRM_URL?: string }).OSRM_URL || "https://router.project-osrm.org";
 *
 * which means the public server is still the effective default no matter what
 * this module or `wrangler.toml` say. That line is in E09's file and this task
 * may not touch it. Replacing it with `resolveOsrmBaseUrl(env)` completes
 * fail-closed: unset config, or config still pointing at the public demo
 * server, both resolve to `null` and the caller must decide what to do rather
 * than being handed a working-but-forbidden endpoint.
 *
 * Returns `null` — never a fallback URL — precisely so "not configured" cannot
 * be mistaken for "configured".
 */
export function resolveOsrmBaseUrl(env: unknown): string | null {
  if (typeof env !== "object" || env === null) return null;
  const raw = (env as Record<string, unknown>).OSRM_URL;
  if (typeof raw !== "string") return null;

  const url = raw.trim().replace(/\/+$/, "");
  if (url.length === 0) return null;

  if (isPublicOsrm(url)) {
    // Configured, but with the one value that is not allowed to count.
    counter("route_public_osrm_configured", 1);
    logWarn("routing.public_osrm_configured", {
      reason: "OSRM_URL points at the public demo server; treating as unconfigured",
    });
    return null;
  }
  return url;
}

const ROUTE_TIMEOUT_MS = 8_000;

/**
 * Driving route between two points.
 *
 * OSRM expects `lon,lat`; the geometry comes back as `[lng, lat]` pairs and is
 * flipped to `[lat, lng]` for the clients.
 */
export async function getRoute(
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
  osrmBaseUrl: string,
  options: RouteOptions = {},
): Promise<RouteResult> {
  const allowFallback = options.allowFallback ?? true;

  // Refusing a *price* computed against a server we are not entitled to use is
  // the point of the task. On the estimate path (`allowFallback: true`) the
  // call still goes out, because refusing there would turn every estimate into
  // a straight line — strictly worse than the status quo this is fixing.
  if (!osrmBaseUrl || osrmBaseUrl.trim().length === 0) {
    return fallbackOrFail(pickup, dropoff, allowFallback, "OSRM_URL is not configured");
  }
  if (isPublicOsrm(osrmBaseUrl)) {
    counter("route_public_osrm_used", 1);
    logWarn("routing.public_osrm_used", {
      reason: "routing through the public demo server; see gate item 11",
      allowFallback,
    });
    if (!allowFallback) {
      throw new RouteUnavailableError("refusing to price against the public OSRM demo server");
    }
  }

  try {
    const url =
      `${osrmBaseUrl.replace(/\/+$/, "")}/route/v1/driving/` +
      `${pickup.lng},${pickup.lat};${dropoff.lng},${dropoff.lat}` +
      `?overview=full&geometries=geojson`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ROUTE_TIMEOUT_MS);
    let res: Response;
    try {
      res = await fetch(url, {
        headers: { "User-Agent": "SynapticGo/0.2 (ride-hailing)" },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    if (!res.ok) throw new Error(`OSRM HTTP ${res.status}`);

    const data = (await res.json()) as {
      code?: string;
      routes?: Array<{
        distance: number; // meters
        duration: number; // seconds
        geometry?: { coordinates: Array<[number, number]> }; // [lng, lat]
      }>;
    };

    const route = data.routes?.[0];
    if (!route || data.code !== "Ok") throw new Error("OSRM no route");

    const distanceKm = Math.round((route.distance / 1000) * 100) / 100;
    const durationMin = Math.max(1, Math.round(route.duration / 60));
    const geometry: Array<[number, number]> = (route.geometry?.coordinates ?? []).map(
      ([lng, lat]) => [lat, lng],
    );

    return { distanceKm, durationMin, geometry, source: "osrm" };
  } catch (e) {
    if (e instanceof RouteUnavailableError) throw e;
    const reason = e instanceof Error ? e.message : String(e);
    return fallbackOrFail(pickup, dropoff, allowFallback, reason);
  }
}

/**
 * The single place a routing failure is resolved.
 *
 * Every outcome is counted. `route_fallback` is the metric gate item 11's alert
 * threshold sits on — "how many trips in the last hour were priced off a
 * straight line" — and it is the reason the fallback is no longer invisible.
 */
function fallbackOrFail(
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
  allowFallback: boolean,
  reason: string,
): RouteResult {
  if (!allowFallback) {
    counter("route_unavailable", 1);
    logWarn("routing.unavailable", { reason, allowFallback });
    throw new RouteUnavailableError(reason);
  }

  counter("route_fallback", 1, { reason });
  logWarn("routing.fallback_to_haversine", {
    reason,
    note: "distance is a straight line × 1.35, not a route",
  });
  return haversineFallback(pickup, dropoff);
}

function haversineFallback(
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
): RouteResult {
  const straight = haversineKm(pickup, dropoff);
  const distanceKm = Math.round(straight * 1.35 * 100) / 100;
  const durationMin = estimateDurationMin(distanceKm, 22);
  return {
    distanceKm,
    durationMin,
    geometry: [
      [pickup.lat, pickup.lng],
      [dropoff.lat, dropoff.lng],
    ],
    source: "haversine",
  };
}

export type EtaEstimate = {
  /** Whole driving minutes, never below 1. */
  durationMin: number;
  source: RouteSource;
};

/**
 * Driving minutes from many origins to a single destination, in one request.
 *
 * `getRoute` is the wrong shape for "how far away is each of these captains":
 * it is one HTTP round trip per origin and it drags a full polyline back with
 * every one of them. OSRM's table service answers the whole fan-in at once and
 * returns durations only.
 *
 * Degrades per origin, not per call. A `null` cell — an origin OSRM cannot
 * snap to the road network, say a captain parked inside an unmapped compound —
 * falls back to haversine for that one captain while everybody else keeps
 * their routed answer.
 *
 * The timeout is deliberately much tighter than `getRoute`'s 8s: this is
 * called from an endpoint the rider's app polls every few seconds, where a
 * slow answer is worse than an approximate one.
 *
 * **No `allowFallback` here, deliberately.** This produces an arrival ETA shown
 * on a map, never a price. Item 11 is about fares; refusing to draw a car
 * because the router blinked would be a worse product and would not make a
 * single fare more accurate. The degradation is still counted.
 */
export async function getDurationsToPoint(
  origins: Array<{ lat: number; lng: number }>,
  destination: { lat: number; lng: number },
  osrmBaseUrl: string,
  timeoutMs = 3500,
): Promise<EtaEstimate[]> {
  if (origins.length === 0) return [];

  if (!osrmBaseUrl || osrmBaseUrl.trim().length === 0) {
    counter("eta_fallback", origins.length, { reason: "unconfigured" });
    return origins.map((origin) => haversineEta(origin, destination));
  }

  try {
    // Destination goes last, so it is index `origins.length` — sources are
    // everything before it.
    const coords = [...origins, destination].map((p) => `${p.lng},${p.lat}`).join(";");
    const sources = origins.map((_, i) => i).join(";");
    const url =
      `${osrmBaseUrl.replace(/\/+$/, "")}/table/v1/driving/${coords}` +
      `?sources=${sources}&destinations=${origins.length}&annotations=duration`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let res: Response;
    try {
      res = await fetch(url, {
        headers: { "User-Agent": "SynapticGo/0.2 (ride-hailing)" },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    if (!res.ok) throw new Error(`OSRM HTTP ${res.status}`);

    const data = (await res.json()) as {
      code?: string;
      durations?: Array<Array<number | null>>;
    };

    if (data.code !== "Ok" || !Array.isArray(data.durations)) {
      throw new Error("OSRM no table");
    }

    let degraded = 0;
    const out = origins.map((origin, i) => {
      const seconds = data.durations?.[i]?.[0];
      if (typeof seconds !== "number" || !Number.isFinite(seconds)) {
        degraded += 1;
        return haversineEta(origin, destination);
      }
      return { durationMin: Math.max(1, Math.round(seconds / 60)), source: "osrm" as const };
    });
    if (degraded > 0) counter("eta_fallback", degraded, { reason: "unsnappable_origin" });
    return out;
  } catch (e) {
    counter("eta_fallback", origins.length, {
      reason: e instanceof Error ? e.message : String(e),
    });
    return origins.map((origin) => haversineEta(origin, destination));
  }
}

/** Same arithmetic as `haversineFallback`, without building a geometry. */
function haversineEta(
  origin: { lat: number; lng: number },
  destination: { lat: number; lng: number },
): EtaEstimate {
  const distanceKm = Math.round(haversineKm(origin, destination) * 1.35 * 100) / 100;
  return { durationMin: estimateDurationMin(distanceKm, 22), source: "haversine" };
}

export function fareFromRoute(route: RouteResult, rule: PricingRule) {
  const fare = calculateFare(route.distanceKm, route.durationMin, rule);
  return {
    distanceKm: route.distanceKm,
    durationMin: route.durationMin,
    geometry: route.geometry,
    // Carried through so the caller can persist it to `trips.route_source`
    // (migration 0023). **E09 owns the INSERT.**
    source: route.source,
    fare,
  };
}
