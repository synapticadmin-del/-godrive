import {
  calculateFare,
  estimateDurationMin,
  haversineKm,
  type PricingRule,
} from "@synaptic-go/shared";

export type RouteResult = {
  distanceKm: number;
  durationMin: number;
  geometry: Array<[number, number]>; // [lat, lng]
  source: "osrm" | "haversine";
};

const DEFAULT_OSRM = "https://router.project-osrm.org";

/**
 * Get driving route via OSRM. Falls back to haversine * 1.35 if OSRM fails.
 * OSRM expects lon,lat order.
 */
export async function getRoute(
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
  osrmBaseUrl = DEFAULT_OSRM,
): Promise<RouteResult> {
  try {
    const url =
      `${osrmBaseUrl.replace(/\/$/, "")}/route/v1/driving/` +
      `${pickup.lng},${pickup.lat};${dropoff.lng},${dropoff.lat}` +
      `?overview=full&geometries=geojson`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    const res = await fetch(url, {
      headers: { "User-Agent": "SynapticGo/0.2 (ride-hailing)" },
      signal: controller.signal,
    });
    clearTimeout(timer);

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
  } catch {
    return haversineFallback(pickup, dropoff);
  }
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
  source: "osrm" | "haversine";
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
 */
export async function getDurationsToPoint(
  origins: Array<{ lat: number; lng: number }>,
  destination: { lat: number; lng: number },
  osrmBaseUrl = DEFAULT_OSRM,
  timeoutMs = 3500,
): Promise<EtaEstimate[]> {
  if (origins.length === 0) return [];

  try {
    // Destination goes last, so it is index `origins.length` — sources are
    // everything before it.
    const coords = [...origins, destination].map((p) => `${p.lng},${p.lat}`).join(";");
    const sources = origins.map((_, i) => i).join(";");
    const url =
      `${osrmBaseUrl.replace(/\/$/, "")}/table/v1/driving/${coords}` +
      `?sources=${sources}&destinations=${origins.length}&annotations=duration`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const res = await fetch(url, {
      headers: { "User-Agent": "SynapticGo/0.2 (ride-hailing)" },
      signal: controller.signal,
    });
    clearTimeout(timer);

    if (!res.ok) throw new Error(`OSRM HTTP ${res.status}`);

    const data = (await res.json()) as {
      code?: string;
      durations?: Array<Array<number | null>>;
    };

    if (data.code !== "Ok" || !Array.isArray(data.durations)) {
      throw new Error("OSRM no table");
    }

    return origins.map((origin, i) => {
      const seconds = data.durations?.[i]?.[0];
      if (typeof seconds !== "number" || !Number.isFinite(seconds)) {
        return haversineEta(origin, destination);
      }
      return { durationMin: Math.max(1, Math.round(seconds / 60)), source: "osrm" as const };
    });
  } catch {
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
    source: route.source,
    fare,
  };
}
