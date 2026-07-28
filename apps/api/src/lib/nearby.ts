import { cellKey } from "./pricing";

/**
 * Nearby-captain discovery across the geohash neighbourhood.
 *
 * GeoCell stores one Durable Object per geohash cell (precision 5 ≈ a
 * 4.9km×4.9km square). Matching used to ask only the pickup's own cell for
 * captains, so a captain sitting literally across the street — but over the
 * cell boundary — was invisible to dispatch, and riders near cell edges saw
 * "no captains nearby" while several idled a block away.
 *
 * We now fan out to the pickup's cell plus its 8 surrounding cells: a ~150m
 * latitude/longitude ring of offsets around the point (0.00135°, roughly
 * one cell step), dedupe the cell keys (the ring collapses to 1–9 distinct
 * cells depending on where inside the cell the point sits), query every
 * cell in parallel, and merge by userId keeping the closest reading.
 *
 * The same helper backs both trip dispatch (POST /trips) and cancellation
 * fanout, so a withdrawn offer reaches exactly the captains it reached on
 * the way in.
 */

/** Roughly one geohash-5 cell step, in degrees (~150m). */
const CELL_STEP_DEG = 0.00135;

export type NearbyCaptain = {
  userId: string;
  distanceKm: number;
  name?: string | null;
};

/** The distinct cell keys for a point and its 8-cell neighbourhood. */
export function neighbourhoodCellKeys(city: string, lat: number, lng: number): string[] {
  const keys = new Set<string>();
  for (const dLat of [-CELL_STEP_DEG, 0, CELL_STEP_DEG]) {
    for (const dLng of [-CELL_STEP_DEG, 0, CELL_STEP_DEG]) {
      keys.add(cellKey(city, lat + dLat, lng + dLng));
    }
  }
  return [...keys];
}

/** Query every neighbourhood GeoCell and merge captains, closest-reading wins. */
export async function findNearbyCaptains(
  env: Env,
  city: string,
  lat: number,
  lng: number,
  limit = 10,
): Promise<NearbyCaptain[]> {
  const keys = neighbourhoodCellKeys(city, lat, lng);

  const settled = await Promise.all(
    keys.map(async (key) => {
      try {
        const cell = env.GEO_CELL.get(env.GEO_CELL.idFromName(key));
        const res = await cell.fetch(
          `https://cell/nearby?lat=${lat}&lng=${lng}&limit=${limit}`,
        );
        const data = (await res.json()) as {
          captains?: Array<{ userId: string; distanceKm: number; name?: string | null }>;
        };
        return data.captains ?? [];
      } catch (e) {
        // One bad cell must not blind the whole neighbourhood.
        console.error("nearby cell fetch failed", key, e);
        return [] as Array<{ userId: string; distanceKm: number; name?: string | null }>;
      }
    }),
  );

  // Merge by userId — a captain can only live in one cell at a time, but a
  // heartbeat straddling a boundary move may briefly echo in two.
  const byId = new Map<string, NearbyCaptain>();
  for (const captains of settled) {
    for (const c of captains) {
      const existing = byId.get(c.userId);
      if (!existing || c.distanceKm < existing.distanceKm) {
        byId.set(c.userId, c);
      }
    }
  }

  const merged = [...byId.values()];
  merged.sort((a, b) => a.distanceKm - b.distanceKm);
  return merged.slice(0, limit);
}
