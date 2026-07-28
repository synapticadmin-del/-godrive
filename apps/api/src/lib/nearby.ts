import { cellKey } from "./pricing";
import { geohashCellSpan } from "@synaptic-go/shared";

/**
 * Nearby-captain discovery across the geohash neighbourhood.
 *
 * GeoCell stores one Durable Object per geohash cell (precision 5 ≈ a
 * 4.9km×4.9km square). Matching used to ask only the pickup's own cell for
 * captains, so a captain sitting literally across the street — but over the
 * cell boundary — was invisible to dispatch, and riders near cell edges saw
 * "no captains nearby" while several idled a block away.
 *
 * We now fan out to the pickup's cell plus its 8 surrounding cells and merge
 * by userId keeping the closest reading. Every cell is queried in parallel,
 * and one failing cell does not blind the whole neighbourhood.
 *
 * The same helper backs both trip dispatch (POST /trips) and cancellation
 * fanout, so a withdrawn offer reaches exactly the captains it reached on
 * the way in.
 */

/** Tiny nudge used to step across a cell boundary when probing. */
const EDGE_EPS = 1e-7;

/**
 * The distinct cell keys for a point and its 8-cell neighbourhood.
 *
 * The previous version probed a fixed 0.00135° (~150m) ring around the
 * point. That step is much smaller than a geohash-5 cell (~4.9km), so from
 * any single rider position the ring touched at most 4 of the 9 cells: a
 * captain idling in a neighbouring cell but near that cell's far edge (up
 * to ~4km from the rider) stayed invisible — the exact boundary bug the
 * neighbourhood search was supposed to fix.
 *
 * Instead we derive the actual cell span from the geohash bit-interleaving
 * scheme and probe the 8 points around the rider at exactly one full cell
 * step (centre-to-centre), which is guaranteed to land inside each adjacent
 * cell no matter where the rider sits within their own cell.
 */
export function neighbourhoodCellKeys(city: string, lat: number, lng: number): string[] {
  const { latSpan, lngSpan } = geohashCellSpan(5);
  const keys = new Set<string>();
  for (const dLat of [-latSpan, 0, latSpan]) {
    for (const dLng of [-lngSpan, 0, lngSpan]) {
      // The nudge keeps a probe that lands exactly on a boundary from
      // falling back into the cell it just left.
      const probeLat = lat + dLat + (dLat > 0 ? EDGE_EPS : dLat < 0 ? -EDGE_EPS : 0);
      const probeLng = lng + dLng + (dLng > 0 ? EDGE_EPS : dLng < 0 ? -EDGE_EPS : 0);
      keys.add(cellKey(city, probeLat, probeLng));
    }
  }
  return [...keys];
}

export type NearbyCaptain = {
  userId: string;
  distanceKm: number;
  name?: string | null;
};

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
