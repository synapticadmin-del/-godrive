import { Hono } from "hono";
import { reverseGeocode, searchPlaces, type NearPoint } from "../lib/geocode";
import type { AppEnv } from "../middleware/auth";
import { rateLimit } from "../middleware/rateLimit";

export const geocodeRoutes = new Hono<AppEnv>();

/**
 * Optional bias point for `/search`.
 *
 * Same `lat`/`lng` query parameters `/reverse` already uses, so the clients
 * need no new vocabulary. Absent or malformed values are ignored rather than
 * rejected: the search still works without a location, it is just biased to
 * the country instead of to the caller's map view. Out-of-range values are
 * dropped for the same reason — a bad bias must never turn into a 400 on a
 * search that would otherwise have succeeded.
 */
function nearFromQuery(lat: string | undefined, lng: string | undefined): NearPoint | undefined {
  const nlat = Number(lat);
  const nlng = Number(lng);
  if (!Number.isFinite(nlat) || !Number.isFinite(nlng)) return undefined;
  if (nlat < -90 || nlat > 90 || nlng < -180 || nlng > 180) return undefined;
  return { lat: nlat, lng: nlng };
}

geocodeRoutes.get(
  "/reverse",
  rateLimit({ prefix: "geocode-rev", limit: 20, windowSec: 60 }),
  async (c) => {
    const lat = Number(c.req.query("lat"));
    const lng = Number(c.req.query("lng"));
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return c.json({ error: "lat and lng required", code: "LATLNG_REQUIRED" }, 400);
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return c.json({ error: "lat/lng out of range", code: "LATLNG_RANGE" }, 400);
    }

    const result = await reverseGeocode(lat, lng, c.env.SESSIONS);
    return c.json(result);
  },
);

geocodeRoutes.get(
  "/search",
  rateLimit({ prefix: "geocode-search", limit: 15, windowSec: 60 }),
  async (c) => {
    const q = c.req.query("q")?.trim() ?? "";
    if (q.length < 2) {
      return c.json({ error: "q must be at least 2 chars", code: "QUERY_TOO_SHORT" }, 400);
    }
    const near = nearFromQuery(c.req.query("lat"), c.req.query("lng"));
    const results = await searchPlaces(q, c.env.SESSIONS, 5, near);
    return c.json({ results });
  },
);
