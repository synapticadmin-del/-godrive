import { Hono } from "hono";
import {
  FILE_EXT_CONTENT_TYPE,
  isIsoBmffContainer,
  SNIFF_HEAD_BYTES,
  sniffFileExt,
  type StoredFileExt,
} from "@synaptic-go/shared";
import type { DbCaptain, DbTrip } from "../lib/types";
import { cellKey } from "../lib/pricing";
import {
  captainProfileSchema,
  captainOnlineSchema,
  captainLocationSchema,
  captainSearchRadiusSchema,
  documentRegisterSchema,
} from "../lib/schemas";
import { haversineKm, id, nowIso, resolveSearchRadiusKm } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";

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

  // Onboarding fields (migration 0014): partial updates only — COALESCE keeps
  // whatever earlier steps already saved. The year column is INTEGER, so the
  // numeric value is bound directly while everything else is text.
  await c.env.DB.prepare(
    `UPDATE captains SET
      first_name = COALESCE(?, first_name),
      father_name = COALESCE(?, father_name),
      grandfather_name = COALESCE(?, grandfather_name),
      family_name = COALESCE(?, family_name),
      birth_date = COALESCE(?, birth_date),
      national_id_number = COALESCE(?, national_id_number),
      license_expiry = COALESCE(?, license_expiry),
      vehicle_year = COALESCE(?, vehicle_year),
      updated_at = ?
     WHERE user_id = ?`,
  )
    .bind(
      body.firstName ?? null,
      body.fatherName ?? null,
      body.grandfatherName ?? null,
      body.familyName ?? null,
      body.birthDate ?? null,
      body.nationalIdNumber ?? null,
      body.licenseExpiry ?? null,
      body.vehicleYear ?? null,
      nowIso(),
      user.id,
    )
    .run();

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  return c.json({ captain });
});

// GET /captain/profile — what the onboarding flow pre-fills from: the captain
// row plus the display name on the user record. Reads are idempotent, so the
// flow can re-fetch on resume without side effects.
captainRoutes.get("/profile", async (c) => {
  const user = c.get("user");
  const captain = await c.env.DB.prepare(
    `SELECT c.*, u.name as user_name, u.email, u.phone as user_phone
     FROM captains c JOIN users u ON u.id = c.user_id WHERE c.user_id = ?`,
  )
    .bind(user.id)
    .first();
  return c.json({ captain: captain ?? null });
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
      // rateLimit:false — going online is a deliberate tap, not a stream of
      // fixes, and must not be refused because the location stream was busy.
      await stub.fetch("https://cell/heartbeat", {
        method: "POST",
        body: JSON.stringify({
          userId: user.id,
          lat,
          lng,
          name: user.name,
          rateLimit: false,
        }),
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

// POST /captain/location — the highest-frequency authorised request in the
// product, and the one that decides whether a captain is visible at all.
//
// Two things changed here (E11):
//
//  1. The rate-limit counter moved out of KV and into the GeoCell Durable
//     Object this request already contacts (T24 P0.3). The old
//     `rateLimit({ prefix: "captain-loc", limit: 30, windowSec: 60 })`
//     middleware cost a KV read plus a KV write on every fix; the DO does the
//     accounting in memory as a side effect of recording presence, for no
//     extra round trip.
//
//  2. Admission is decided *before* the expensive work. Previously a fix that
//     survived the rate limit went on to a D1 update, a second D1 read, an
//     optional D1 insert and a socket fanout; a fix that failed it was
//     rejected by middleware, which is correct but meant the limit was
//     protecting nothing that cost money. Now the cheap DO hop happens first
//     and a throttled fix returns 429 having touched no database at all.
//
// The client paces itself well inside this budget (see `minPublishIntervalMs`
// in the heartbeat response), so a 429 here means something is wrong rather
// than something is busy — a normal drive should never see one.
captainRoutes.post("/location", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, captainLocationSchema);
  if (isResponse(body)) return body;

  const city = body.city || c.env.DEFAULT_CITY || "cairo";

  const key = cellKey(city, body.lat, body.lng);
  const cellStub = c.env.GEO_CELL.get(c.env.GEO_CELL.idFromName(key));
  const presence = await cellStub.fetch("https://cell/heartbeat", {
    method: "POST",
    body: JSON.stringify({
      userId: user.id,
      lat: body.lat,
      lng: body.lng,
      name: user.name,
    }),
  });

  // The DO owns the budget, so it also owns the advice about how fast to
  // publish. Forwarding it means the app paces itself from one number that
  // lives in one place, instead of a client-side constant that silently drifts
  // out of step the day the limit changes.
  const presenceBody = await presence
    .json<{ minPublishIntervalMs?: number }>()
    .catch(() => ({}) as { minPublishIntervalMs?: number });

  if (presence.status === 429) {
    const retryAfter = presence.headers.get("Retry-After") ?? "2";
    return c.json(
      {
        error: "Too many location updates",
        code: "RATE_LIMITED",
        retryAfterSec: Number(retryAfter),
      },
      429,
      { "Retry-After": retryAfter },
    );
  }

  await c.env.DB.prepare(
    `UPDATE captains SET last_lat = ?, last_lng = ?, last_seen_at = ?, is_online = 1, city = ?, updated_at = ? WHERE user_id = ?`,
  )
    .bind(body.lat, body.lng, nowIso(), city, nowIso(), user.id)
    .run();

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

  return c.json({ ok: true, minPublishIntervalMs: presenceBody.minPublishIntervalMs });
});

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

// POST /captain/search-radius — persist how far out the captain wants work.
//
// The radius used to live only in the app's widget state, so it filtered the
// browsable queue and nothing else: dispatch kept pushing (and FCM kept
// notifying) trips from the whole 9-cell neighbourhood, and the offers inbox
// kept badging them. Storing it here makes one number govern every surface.
captainRoutes.post("/search-radius", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, captainSearchRadiusSchema);
  if (isResponse(body)) return body;

  const radiusKm = resolveSearchRadiusKm(body.radiusKm);

  const res = await c.env.DB.prepare(
    `UPDATE captains SET search_radius_km = ?, updated_at = ? WHERE user_id = ?`,
  )
    .bind(radiusKm, nowIso(), user.id)
    .run();

  if (res.meta && res.meta.changes === 0) {
    return c.json({ error: "Complete captain profile first", code: "NO_PROFILE" }, 400);
  }

  return c.json({ ok: true, searchRadiusKm: radiusKm });
});

captainRoutes.get("/nearby-requests", async (c) => {
  const user = c.get("user");
  const latParam = c.req.query("lat");
  const lngParam = c.req.query("lng");

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  // An explicit ?radius= still wins (the chips send one as they are tapped),
  // but the stored column is the fallback rather than a hardcoded 15 — so a
  // captain who picked 5km keeps 5km on a cold start, before the app has had
  // a chance to restate its preference.
  const radiusKm = resolveSearchRadiusKm(
    c.req.query("radius"),
    captain?.search_radius_km,
  );

  // Online guard: offline captains should not receive trip listings.
  if (captain && !captain.is_online && user.role !== "admin") {
    return c.json({
      requests: [],
      searchRadiusKm: radiusKm,
      captainLocation: { lat: captain.last_lat ?? 30.0444, lng: captain.last_lng ?? 31.2357 },
    });
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

  // Distance is measured with the shared haversineKm helper (lib/utils) so
  // this list, the pushed offers inbox and the dispatch fanout all agree on
  // whether a given trip is inside the captain's radius.
  const requests = (rows.results || [])
    .map((r) => {
      const captainToPickupKm = haversineKm(cLat, cLng, r.pickup_lat, r.pickup_lng);
      return {
        id: r.id,
        rider_id: r.rider_id,
        rider_name: r.rider_name || "عميل Tempo",
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

  return c.json({
    requests,
    // Echoed so the app can reconcile its chips with what the server actually
    // applied (a legacy row resolves to the default, a bad param is clamped).
    searchRadiusKm: radiusKm,
    captainLocation: { lat: cLat, lng: cLng },
  });
});

captainRoutes.get("/offers", async (c) => {
  const user = c.get("user");

  const captain = await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
    .bind(user.id)
    .first<DbCaptain>();

  // Online guard: offline captains should not receive trip offers.
  if (captain && !captain.is_online && user.role !== "admin") {
    return c.json({
      trips: [],
      searchRadiusKm: resolveSearchRadiusKm(captain.search_radius_km),
      captainLocation: captain,
    });
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

  // Radius scoping. City scoping alone let this endpoint hand back every open
  // request in Cairo, which is what put trips the captain had explicitly
  // excluded back on their screen: this list feeds the offers badge, so a
  // 40km-away request still lit up the "رحلات متاحة" tab for a captain
  // hunting inside 5km. Each row now carries its measured distance too, so a
  // client never has to re-derive it.
  const radiusKm = resolveSearchRadiusKm(captain?.search_radius_km);
  const cLat = captain?.last_lat;
  const cLng = captain?.last_lng;
  const rows = trips.results ?? [];

  // With no known position there is nothing to measure from. Falling back to
  // the city-wide list keeps a captain who has not pushed a fix yet from
  // seeing an empty queue they cannot explain.
  const scoped =
    typeof cLat === "number" && typeof cLng === "number"
      ? rows
          .map((t) => ({
            ...t,
            captain_to_pickup_km: haversineKm(cLat, cLng, t.pickup_lat, t.pickup_lng),
          }))
          .filter((t) => t.captain_to_pickup_km <= radiusKm)
      : rows;

  return c.json({
    trips: scoped,
    searchRadiusKm: radiusKm,
    captainLocation: captain,
  });
});

// GET /captain/document-types — the catalog that drives the onboarding upload
// grid. Only active types are returned, ordered the way the admin arranged
// them; each row tells the app whether the document is required or optional
// (اختياري) so it can badge the tile without any client-side hard-coding.
captainRoutes.get("/document-types", async (c) => {
  const rows = await c.env.DB.prepare(
    `SELECT id, title_ar, title_en, icon, required, sort_order
     FROM document_types WHERE active = 1 ORDER BY sort_order ASC, id ASC`,
  ).all();
  return c.json({ types: rows.results ?? [] });
});

captainRoutes.get("/documents", async (c) => {
  const user = c.get("user");
  const docs = await c.env.DB.prepare(
    `SELECT d.*,
            COALESCE(t.title_ar, d.type) as title_ar,
            COALESCE(t.title_en, '') as title_en,
            COALESCE(t.required, 1) as required
     FROM driver_documents d
     LEFT JOIN document_types t ON t.id = d.type
     WHERE d.captain_id = ? ORDER BY d.created_at DESC`
  )
    .bind(user.id)
    .all();

  return c.json({ documents: docs.results ?? [] });
});

captainRoutes.post("/documents", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, documentRegisterSchema);
  if (isResponse(body)) return body;

  // The type id comes from the admin-managed document_types catalog, so it is
  // validated as a slug by the schema and checked against the catalog below —
  // not against a hard-coded list that would reject any newly added type.
  const type = body.type;

  const r2Key = body.r2Key;

  // Reject registration when the file key points outside the captain's own
  // folder — the upload endpoint always writes under docs/<userId>/, so a
  // foreign prefix means the key was fabricated rather than uploaded.
  if (!r2Key.startsWith(`docs/${user.id}/`)) {
    return c.json({ error: "Invalid document key", code: "INVALID_KEY" }, 400);
  }

  // Validate against the catalog when it exists. Types predating the catalog
  // (or deactivated later) are still accepted so older app builds never break:
  // a row that is missing from document_types simply falls through. But a
  // known-inactive type is an admin decision — refuse new uploads for it.
  const typeRow = await c.env.DB.prepare(
    `SELECT id, active FROM document_types WHERE id = ?`,
  )
    .bind(type)
    .first<{ id: string; active: number }>();
  if (typeRow && !typeRow.active) {
    return c.json({ error: "Document type is not currently accepted", code: "TYPE_INACTIVE" }, 400);
  }

  // Re-uploading the same type must not stack duplicate rows: retire any
  // previous submission of this type (pending or rejected) and replace it with
  // the fresh upload, so the admin queue shows one row per document type per
  // captain — the latest. Approved documents are left untouched; the UI only
  // offers re-upload for missing/rejected types.
  await c.env.DB.prepare(
    `DELETE FROM driver_documents WHERE captain_id = ? AND type = ? AND status != 'approved'`,
  )
    .bind(user.id, type)
    .run();

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

// DELETE /captain/documents/:type — removes the captain's pending upload for
// a document type so an onboarding tile can truly reset when the captain taps
// "×". Only pending rows are touched: approved history stays (admins own it),
// and rejected rows keep the admin's feedback visible until the next upload.
captainRoutes.delete("/documents/:type", async (c) => {
  const user = c.get("user");
  const type = c.req.param("type");

  await c.env.DB.prepare(
    `DELETE FROM driver_documents WHERE captain_id = ? AND type = ? AND status = 'pending'`,
  )
    .bind(user.id, type)
    .run();

  return c.json({ ok: true });
});

// POST /captain/upload — upload a file directly to R2 (multipart/form-data).
// Returns the R2 key which is then passed to POST /captain/documents.
// Which declared types may act as a fallback when the bytes match no known
// signature, and what they resolve to. Only HEIC/HEIF, and only alongside a
// verified ISO-BMFF container (see the handler) — the brand registry is
// open-ended, so a real photo from an unusual encoder should not be refused.
// A declared type on its own is never sufficient.
const DOC_HEIC_DECLARED: Record<string, StoredFileExt> = {
  "image/heic": "heic",
  "image/heif": "heif",
};

captainRoutes.post("/upload", async (c) => {
  const user = c.get("user");
  const formData = await c.req.formData();
  const file = formData.get("file") as File | null;
  if (!file) return c.json({ error: "file required", code: "MISSING_FILE" }, 400);
  if (file.size === 0) return c.json({ error: "File is empty", code: "EMPTY_FILE" }, 400);
  if (file.size > 10 * 1024 * 1024) return c.json({ error: "File too large (max 10MB)", code: "FILE_TOO_LARGE" }, 400);

  // The bytes decide the type. The previous order checked the declared type
  // first and skipped sniffing on a hit, so a client could label anything
  // `image/png` and have it stored and served back under that type — the same
  // stored-content gap the filename version had, just moved one field along.
  const declaredType = (file.type || "").toLowerCase();
  const head = new Uint8Array(await file.slice(0, SNIFF_HEAD_BYTES).arrayBuffer());
  let ext: StoredFileExt | null = sniffFileExt(head);

  if (!ext) {
    // One tolerated fallback: an ISO-BMFF container whose brand is not in the
    // list above. The HEIC/HEIF brand set is open-ended, so a real photo from
    // an unusual encoder should not be refused — but it must still present a
    // container. A declared type on its own is never enough, which is what
    // stops arbitrary bytes being labelled `image/png` and stored as one.
    const declaredHeic = DOC_HEIC_DECLARED[declaredType];
    if (declaredHeic && isIsoBmffContainer(head)) ext = declaredHeic;
  }

  if (!ext) {
    return c.json(
      {
        error: "Unsupported file type. Use JPEG, PNG, WebP, HEIC or PDF.",
        code: "UNSUPPORTED_TYPE",
      },
      400,
    );
  }

  // Derived from the verified extension, never echoed back from the upload.
  const contentType = FILE_EXT_CONTENT_TYPE[ext];

  const key = `docs/${user.id}/${Date.now()}_${id("f")}.${ext}`;
  await c.env.FILES.put(key, file.stream(), {
    httpMetadata: { contentType },
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
  // Legacy objects predate stored contentType metadata; every one of them is an
  // image, because this endpoint accepted nothing else until PDF was added.
  const served = obj.httpMetadata?.contentType ?? "image/jpeg";
  headers.set("Content-Type", served);
  headers.set("Cache-Control", "private, no-store");
  // Belt and braces for anything already in the bucket from before the upload
  // guard tightened: nosniff stops a browser second-guessing the declared type,
  // and a PDF is handed over as a download rather than rendered in this origin.
  headers.set("X-Content-Type-Options", "nosniff");
  if (served === FILE_EXT_CONTENT_TYPE.pdf) {
    headers.set("Content-Disposition", "attachment");
  }
  return new Response(obj.body, { headers });
});
