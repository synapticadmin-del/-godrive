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
): Promise<SearchResult[]> {
  const q = query.trim().slice(0, 120);
  if (!q) return [];

  const key = `geosearch:${q.toLowerCase()}`;
  const cached = await kv.get(key, "json");
  if (Array.isArray(cached)) return cached as SearchResult[];

  // Bias towards Egypt
  const url =
    `https://nominatim.openstreetmap.org/search?format=jsonv2` +
    `&q=${encodeURIComponent(q)}` +
    `&countrycodes=eg&limit=${limit}&accept-language=ar,en`;

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
