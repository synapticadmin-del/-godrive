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
