import { Hono } from "hono";
import { reverseGeocode, searchPlaces } from "../lib/geocode";
import type { AppEnv } from "../middleware/auth";
import { rateLimit } from "../middleware/rateLimit";

export const geocodeRoutes = new Hono<AppEnv>();

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
    const results = await searchPlaces(q, c.env.SESSIONS, 5);
    return c.json({ results });
  },
);
