type ReverseResult = {
  address: string;
  city: string | null;
  area: string | null;
  raw?: unknown;
};

type SearchResult = {
  lat: number;
  lng: number;
  label: string;
};

/** A point to bias search results towards — normally the rider's map centre. */
export type NearPoint = { lat: number; lng: number };

/**
 * Nominatim `viewbox`, as `left,top,right,bottom` in **lon,lat** order.
 *
 * T21 measured this endpoint returning matches up to ~700 km from the user.
 * `countrycodes=eg` was already set, so those hits were inside Egypt — the
 * country filter cannot separate "مدينة نصر, Cairo" from a same-named village
 * in Aswan, because both are Egyptian. A viewbox can.
 *
 * This national box is the floor, used when the caller sends no location.
 */
const EGYPT_VIEWBOX = "24.7000,31.7000,36.9000,21.7000";

/** Roughly 100 km at Egypt's latitudes. Wide enough for a metro area. */
const NEAR_DEGREES = 0.9;

/**
 * `viewbox` biases ranking; it does **not** filter unless `bounded=1` is also
 * sent, and that is deliberately omitted. A rider in Cairo searching for
 * "الإسكندرية" must still find Alexandria 220 km away — a hard bound would
 * turn a ranking bug into a missing-results bug, which is worse.
 */
function viewboxFor(near?: NearPoint): string {
  if (!near || !Number.isFinite(near.lat) || !Number.isFinite(near.lng)) {
    return EGYPT_VIEWBOX;
  }
  const left = near.lng - NEAR_DEGREES;
  const right = near.lng + NEAR_DEGREES;
  const top = near.lat + NEAR_DEGREES;
  const bottom = near.lat - NEAR_DEGREES;
  return [left, top, right, bottom].map((n) => n.toFixed(4)).join(",");
}

function roundCoord(n: number, digits = 4): number {
  const f = 10 ** digits;
  return Math.round(n * f) / f;
}

function cacheKey(lat: number, lng: number): string {
  return `geo:${roundCoord(lat)},${roundCoord(lng)}`;
}

/**
 * Reverse geocode via Nominatim (OSM). Results cached in KV for 30 days.
 * Respect Nominatim usage policy: max ~1 req/sec, set User-Agent.
 */
export async function reverseGeocode(
  lat: number,
  lng: number,
  kv: KVNamespace,
): Promise<ReverseResult> {
  const key = cacheKey(lat, lng);
  const cached = await kv.get(key, "json");
  if (cached && typeof cached === "object" && "address" in (cached as object)) {
    return cached as ReverseResult;
  }

  const url =
    `https://nominatim.openstreetmap.org/reverse?format=jsonv2` +
    `&lat=${lat}&lon=${lng}&accept-language=ar,en`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  let res: Response;
  try {
    res = await fetch(url, {
      headers: {
        "User-Agent": "SynapticGo/0.2 (ride-hailing; contact=admin@synapticstudio.tech)",
      },
      signal: controller.signal,
    });
  } catch {
    clearTimeout(timer);
    return { address: `${lat.toFixed(5)}, ${lng.toFixed(5)}`, city: null, area: null };
  }
  clearTimeout(timer);

  if (!res.ok) {
    return { address: `${lat.toFixed(5)}, ${lng.toFixed(5)}`, city: null, area: null };
  }

  const data = (await res.json()) as {
    display_name?: string;
    address?: {
      city?: string;
      town?: string;
      village?: string;
      state?: string;
      suburb?: string;
      neighbourhood?: string;
      road?: string;
    };
  };

  const addr = data.address ?? {};
  const result: ReverseResult = {
    address: data.display_name ?? `${lat.toFixed(5)}, ${lng.toFixed(5)}`,
    city: addr.city ?? addr.town ?? addr.village ?? addr.state ?? null,
    area: addr.suburb ?? addr.neighbourhood ?? addr.road ?? null,
  };

  await kv.put(key, JSON.stringify(result), { expirationTtl: 60 * 60 * 24 * 30 });
  return result;
}

export async function searchPlaces(
  query: string,
  kv: KVNamespace,
  limit = 5,
  near?: NearPoint,
): Promise<SearchResult[]> {
  const q = query.trim().slice(0, 120);
  if (!q) return [];

  const viewbox = viewboxFor(near);

  // The viewbox is part of the cache identity. Without it, the first caller to
  // search a term from anywhere in the country would poison every other
  // location's results for a week — the bias would be applied once and then
  // served to people it was not computed for.
  const key = `geosearch:${q.toLowerCase()}:${viewbox}`;
  const cached = await kv.get(key, "json");
  if (Array.isArray(cached)) return cached as SearchResult[];

  // Bias towards Egypt, and towards the caller's own map view within it.
  const url =
    `https://nominatim.openstreetmap.org/search?format=jsonv2` +
    `&q=${encodeURIComponent(q)}` +
    `&countrycodes=eg&limit=${limit}&accept-language=ar,en` +
    `&viewbox=${viewbox}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  const res = await fetch(url, {
    headers: {
      "User-Agent": "SynapticGo/0.2 (ride-hailing; contact=admin@synapticstudio.tech)",
    },
    signal: controller.signal,
  });
  clearTimeout(timer);

  if (!res.ok) return [];

  const data = (await res.json()) as Array<{
    lat: string;
    lon: string;
    display_name: string;
  }>;

  const results: SearchResult[] = data.map((item) => ({
    lat: Number(item.lat),
    lng: Number(item.lon),
    label: item.display_name,
  }));

  await kv.put(key, JSON.stringify(results), { expirationTtl: 60 * 60 * 24 * 7 });
  return results;
}
