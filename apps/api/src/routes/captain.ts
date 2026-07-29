import { Hono } from "hono";
import type { DbCaptain, DbTrip } from "../lib/types";
import { cellKey } from "../lib/pricing";
import {
  captainProfileSchema,
  captainOnlineSchema,
  captainLocationSchema,
  documentRegisterSchema,
} from "../lib/schemas";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody, rateLimit } from "../middleware/rateLimit";

export const captainRoutes = new Hono<AppEnv>();

captainRoutes.use("*", authMiddleware, requireRole("captain", "admin"));

captainRoutes.post("/profile", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, captainProfileSchema);
  if (isResponse(body)) return body;

  if (body.name || body.phone) {
    await c.env.DB.prepare(
      `UPDATE users SET name = COALESCE(?, name), phone = COALESCE(?, phone), updated_at = ? WHERE id = ?`,
    )
      .bind(body.name ?? null, body.phone ?? null, nowIso(), user.id)
      .run();
  }

  const existing = await c.env.DB.prepare(`SELECT user_id FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first();

  if (!existing) {
    await c.env.DB.prepare(
      `INSERT INTO captains (user_id, vehicle_make, vehicle_model, vehicle_plate, vehicle_color, license_number, approval_status)
       VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
    )
      .bind(
        user.id,
        body.vehicleMake ?? null,
        body.vehicleModel ?? null,
        body.vehiclePlate ?? null,
        body.vehicleColor ?? null,
        body.licenseNumber ?? null,
      )
      .run();
  } else {
    await c.env.DB.prepare(
      `UPDATE captains SET
        vehicle_make = COALESCE(?, vehicle_make),
        vehicle_model = COALESCE(?, vehicle_model),
        vehicle_plate = COALESCE(?, vehicle_plate),
        vehicle_color = COALESCE(?, vehicle_color),
        license_number = COALESCE(?, license_number),
        updated_at = ?
       WHERE user_id = ?`,
    )
      .bind(
        body.vehicleMake ?? null,
        body.vehicleModel ?? null,
        body.vehiclePlate ?? null,
        body.vehicleColor ?? null,
        body.licenseNumber ?? null,
        nowIso(),
        user.id,
      )
      .run();
  }

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  return c.json({ captain });
});

captainRoutes.post("/online", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, captainOnlineSchema);
  if (isResponse(body)) return body;

  const online = body.online !== false;
  const lat = body.lat;
  const lng = body.lng;
  const city = body.city || c.env.DEFAULT_CITY || "cairo";

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  if (!captain) return c.json({ error: "Complete captain profile first", code: "NO_PROFILE" }, 400);
  if (captain.approval_status !== "approved" && user.role !== "admin") {
    return c.json(
      {
        error: "Captain not approved yet",
        code: "NOT_APPROVED",
        approvalStatus: captain.approval_status,
      },
      403,
    );
  }

  if (online && (typeof lat !== "number" || typeof lng !== "number")) {
    return c.json({ error: "lat/lng required when going online", code: "LATLNG_REQUIRED" }, 400);
  }

  // Persist the captain's working city too — the offers endpoints filter on
  // it, so a captain is never shown trips from a city they are not in. NULL
  // out on the way offline so a stale city cannot follow them later.
  await c.env.DB.prepare(
    `UPDATE captains SET is_online = ?, last_lat = COALESCE(?, last_lat), last_lng = COALESCE(?, last_lng), last_seen_at = ?, city = ?, updated_at = ?
     WHERE user_id = ?`,
  )
    .bind(online ? 1 : 0, lat ?? null, lng ?? null, nowIso(), online ? city : null, nowIso(), user.id)
    .run();

  if (typeof lat === "number" && typeof lng === "number") {
    const key = cellKey(city, lat, lng);
    const stub = c.env.GEO_CELL.get(c.env.GEO_CELL.idFromName(key));
    if (online) {
      await stub.fetch("https://cell/heartbeat", {
        method: "POST",
        body: JSON.stringify({ userId: user.id, lat, lng, name: user.name }),
      });
    } else {
      await stub.fetch("https://cell/offline", {
        method: "POST",
        body: JSON.stringify({ userId: user.id }),
      });
    }
  }

  return c.json({ ok: true, online, city });
});

captainRoutes.post(
  "/location",
  rateLimit({
    prefix: "captain-loc",
    limit: 30,
    windowSec: 60,
    keyFn: (c) => c.get("user")?.id ?? "anon",
  }),
  async (c) => {
    const user = c.get("user");
    const body = await parseBody(c, captainLocationSchema);
    if (isResponse(body)) return body;

    const city = body.city || c.env.DEFAULT_CITY || "cairo";

    await c.env.DB.prepare(
      `UPDATE captains SET last_lat = ?, last_lng = ?, last_seen_at = ?, is_online = 1, city = ?, updated_at = ? WHERE user_id = ?`,
    )
      .bind(body.lat, body.lng, nowIso(), city, nowIso(), user.id)
      .run();

    const key = cellKey(city, body.lat, body.lng);
    const cellStub = c.env.GEO_CELL.get(c.env.GEO_CELL.idFromName(key));
    await cellStub.fetch("https://cell/heartbeat", {
      method: "POST",
      body: JSON.stringify({
        userId: user.id,
        lat: body.lat,
        lng: body.lng,
        name: user.name,
      }),
    });

    if (body.tripId) {
      const trip = await c.env.DB.prepare(
        `SELECT * FROM trips WHERE id = ? AND captain_id = ?`,
      )
        .bind(body.tripId, user.id)
        .first<DbTrip>();

      if (trip && ["assigned", "arrived", "in_progress"].includes(trip.status)) {
        await c.env.DB.prepare(
          `UPDATE trips SET captain_lat = ?, captain_lng = ?, updated_at = ? WHERE id = ?`,
        )
          .bind(body.lat, body.lng, nowIso(), trip.id)
          .run();

        // Path sampling: keep at most ~1 point / 30s
        const last = await c.env.DB.prepare(
          `SELECT recorded_at FROM trip_path_points WHERE trip_id = ? ORDER BY recorded_at DESC LIMIT 1`,
        )
          .bind(trip.id)
          .first<{ recorded_at: string }>();

        const lastMs = last ? new Date(last.recorded_at).getTime() : 0;
        if (!last || Date.now() - lastMs >= 30_000) {
          await c.env.DB.prepare(
            `INSERT INTO trip_path_points (id, trip_id, lat, lng, heading, recorded_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
          )
            .bind(id("pp"), trip.id, body.lat, body.lng, body.heading ?? null, nowIso())
            .run();
        }

        const room = c.env.TRIP_ROOM.get(c.env.TRIP_ROOM.idFromName(trip.id));
        await room.fetch("https://room/broadcast", {
          method: "POST",
          body: JSON.stringify({
            type: "location.captain",
            tripId: trip.id,
            lat: body.lat,
            lng: body.lng,
            heading: body.heading ?? null,
            at: nowIso(),
          }),
        });
      }
    }

    return c.json({ ok: true });
  },
);

captainRoutes.get("/earnings", async (c) => {
  const user = c.get("user");
  const from = c.req.query("from") || new Date(Date.now() - 7 * 864e5).toISOString();
  const to = c.req.query("to") || nowIso();

  const rows = await c.env.DB.prepare(
    `SELECT COUNT(*) as trips, COALESCE(SUM(final_fare), 0) as gross,
            COALESCE(SUM(commission), 0) as commission
     FROM trips
     WHERE captain_id = ? AND status = 'completed'
       AND completed_at >= ? AND completed_at <= ?`,
  )
    .bind(user.id, from, to)
    .first<{ trips: number; gross: number; commission: number }>();

  const gross = rows?.gross ?? 0;
  const commission = rows?.commission ?? 0;

  return c.json({
    from,
    to,
    trips: rows?.trips ?? 0,
    gross,
    commission,
    net: Math.round((gross - commission) * 100) / 100,
    currency: "EGP",
  });
});

captainRoutes.get("/nearby-requests", async (c) => {
  const user = c.get("user");
  const latParam = c.req.query("lat");
  const lngParam = c.req.query("lng");
  const radiusKm = Number(c.req.query("radius") || 15);

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  // Online guard: offline captains should not receive trip listings.
  if (captain && !captain.is_online && user.role !== "admin") {
    return c.json({ requests: [], captainLocation: { lat: captain.last_lat ?? 30.0444, lng: captain.last_lng ?? 31.2357 } });
  }

  const cLat = latParam ? Number(latParam) : captain?.last_lat ?? 30.0444;
  const cLng = lngParam ? Number(lngParam) : captain?.last_lng ?? 31.2357;

  // City scoping: only trips in the captain's working city. Without this the
  // queue showed every open request nationwide, so a captain in Alexandria
  // would be offered Cairo trips they could never serve. The city resolves
  // from the captain's row (set on /online and /location), falling back to
  // the deployment default for legacy rows with no city yet.
  const city =
    (captain as (DbCaptain & { city?: string | null }) | null)?.city ||
    c.env.DEFAULT_CITY ||
    "cairo";

  // Query searching/offered trips with rider details. duration_min is
  // selected explicitly: the offer card previously fell back to a rough
  // 20km/h guess while the real OSRM estimate sat in the row unread.
  const rows = await c.env.DB.prepare(
    `SELECT t.id, t.rider_id, u.name as rider_name, u.email as rider_email, u.phone as rider_phone,
            t.pickup_lat, t.pickup_lng, t.pickup_address,
            t.dropoff_lat, t.dropoff_lng, t.dropoff_address,
            t.distance_km, t.duration_min, t.offered_price, t.estimated_fare, t.created_at, t.city
     FROM trips t
     JOIN users u ON t.rider_id = u.id
     WHERE t.status IN ('searching', 'offered') AND t.city = ?
     ORDER BY t.created_at DESC LIMIT 30`
  )
    .bind(city)
    .all<{
    id: string;
    rider_id: string;
    rider_name: string | null;
    rider_email: string;
    rider_phone: string | null;
    pickup_lat: number;
    pickup_lng: number;
    pickup_address: string | null;
    dropoff_lat: number;
    dropoff_lng: number;
    dropoff_address: string | null;
    distance_km: number | null;
    duration_min: number | null;
    offered_price: number | null;
    estimated_fare: number | null;
    created_at: string;
    city: string;
  }>();

  // Haversine distance helper
  const haversineKm = (lat1: number, lon1: number, lat2: number, lon2: number) => {
    const R = 6371;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * (Math.PI / 180)) *
        Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Math.round(R * c * 10) / 10;
  };

  const requests = (rows.results || [])
    .map((r) => {
      const captainToPickupKm = haversineKm(cLat, cLng, r.pickup_lat, r.pickup_lng);
      return {
        id: r.id,
        rider_id: r.rider_id,
        rider_name: r.rider_name || "عميل GoDrive",
        rider_phone: r.rider_phone || "",
        rider_avatar: `https://api.dicebear.com/7.x/bottts/svg?seed=${r.rider_id}`,
        pickup_lat: r.pickup_lat,
        pickup_lng: r.pickup_lng,
        pickup_address: r.pickup_address || "موقع الانطلاق",
        dropoff_lat: r.dropoff_lat,
        dropoff_lng: r.dropoff_lng,
        dropoff_address: r.dropoff_address || "موقع الوصول",
        distance_km: r.distance_km || 5.0,
        duration_min: r.duration_min ?? null,
        offered_price: r.offered_price || r.estimated_fare || 25.0,
        captain_to_pickup_km: captainToPickupKm,
        created_at: r.created_at,
        city: r.city,
      };
    })
    .filter((r) => r.captain_to_pickup_km <= radiusKm);

  return c.json({ requests, captainLocation: { lat: cLat, lng: cLng } });
});

captainRoutes.get("/offers", async (c) => {
  const user = c.get("user");

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  // Online guard: offline captains should not receive trip offers.
  if (captain && !captain.is_online && user.role !== "admin") {
    return c.json({ trips: [], captainLocation: captain });
  }

  // City scoping mirrors /nearby-requests: offers are only for trips in the
  // captain's working city.
  const city =
    (captain as (DbCaptain & { city?: string | null }) | null)?.city ||
    c.env.DEFAULT_CITY ||
    "cairo";

  const trips = await c.env.DB.prepare(
    `SELECT * FROM trips WHERE status IN ('searching', 'offered') AND city = ?
     ORDER BY created_at DESC LIMIT 20`,
  )
    .bind(city)
    .all<DbTrip>();

  return c.json({ trips: trips.results ?? [], captainLocation: captain });
});

captainRoutes.get("/documents", async (c) => {
  const user = c.get("user");
  const docs = await c.env.DB.prepare(
    `SELECT * FROM driver_documents WHERE captain_id = ? ORDER BY created_at DESC`
  )
    .bind(user.id)
    .all();

  return c.json({ documents: docs.results ?? [] });
});

captainRoutes.post("/documents", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, documentRegisterSchema);
  if (isResponse(body)) return body;

  const r2Key = body.r2Key;

  // Reject registration when the file key points outside the captain's own
  // folder — the upload endpoint always writes under docs/<userId>/, so a
  // foreign prefix means the key was fabricated rather than uploaded.
  if (!r2Key.startsWith(`docs/${user.id}/`)) {
    return c.json({ error: "Invalid document key", code: "INVALID_KEY" }, 400);
  }

  const docId = id("doc");
  await c.env.DB.prepare(
    `INSERT INTO driver_documents (id, captain_id, type, r2_key, status, holder_full_name, national_id_number, expires_at, created_at)
     VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, ?)`,
  )
    .bind(
      docId,
      user.id,
      body.type,
      r2Key,
      body.holderFullName ?? null,
      body.nationalIdNumber ?? null,
      body.expiresAt ?? null,
      nowIso(),
    )
    .run();

  const doc = await c.env.DB.prepare(`SELECT * FROM driver_documents WHERE id = ?`)
    .bind(docId)
    .first();

  return c.json({ document: doc });
});

// POST /captain/upload — upload a file directly to R2 (multipart/form-data).
// Returns the R2 key which is then passed to POST /captain/documents.
captainRoutes.post("/upload", async (c) => {
  const user = c.get("user");
  const formData = await c.req.formData();
  const file = formData.get("file") as File | null;
  if (!file) return c.json({ error: "file required", code: "MISSING_FILE" }, 400);
  if (file.size > 10 * 1024 * 1024) return c.json({ error: "File too large (max 10MB)", code: "FILE_TOO_LARGE" }, 400);

  const ext = file.name.split(".").pop()?.toLowerCase() ?? "jpg";
  const key = `docs/${user.id}/${Date.now()}_${id("f")}.${ext}`;
  await c.env.FILES.put(key, file.stream(), {
    httpMetadata: { contentType: file.type || "image/jpeg" },
  });

  return c.json({ ok: true, r2Key: key, url: `/captain/file/${key}` });
});

// GET /captain/file/:key — serve a file from R2 (for the captain's own docs)
captainRoutes.get("/file/*", async (c) => {
  const user = c.get("user");
  const key = c.req.path.replace("/captain/file/", "");
  if (!key) return c.json({ error: "key required", code: "MISSING_KEY" }, 400);

  // Enforce IDOR protection: user can only view their own document folder unless they are an admin
  const userFolderPrefix = `docs/${user.id}/`;
  if (user.role !== "admin" && !key.startsWith(userFolderPrefix)) {
    return c.json({ error: "Access denied to requested document", code: "FORBIDDEN" }, 403);
  }

  const obj = await c.env.FILES.get(key);
  if (!obj) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  const headers = new Headers();
  headers.set("Content-Type", obj.httpMetadata?.contentType ?? "image/jpeg");
  headers.set("Cache-Control", "private, no-store");
  return new Response(obj.body, { headers });
});
