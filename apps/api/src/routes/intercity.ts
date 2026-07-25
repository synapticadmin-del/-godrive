import { Hono } from "hono";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";
import {
  intercityRouteSchema,
  intercityScheduleSchema,
  intercityBookingSchema,
} from "../lib/schemas";
import { pushToUser } from "../lib/notifications";
import { logAudit } from "../lib/audit";

export const intercityRoutes = new Hono<AppEnv>();

// Public discovery endpoints
intercityRoutes.get("/routes", async (c) => {
  const from = c.req.query("from");
  const to = c.req.query("to");
  let q = `SELECT * FROM intercity_routes WHERE active = 1`;
  const binds: unknown[] = [];
  if (from) {
    q += ` AND origin_city LIKE ?`;
    binds.push(`%${from}%`);
  }
  if (to) {
    q += ` AND destination_city LIKE ?`;
    binds.push(`%${to}%`);
  }
  q += ` ORDER BY origin_city, destination_city`;
  const res = await c.env.DB.prepare(q).bind(...binds).all();
  return c.json({ routes: res.results ?? [] });
});

intercityRoutes.get("/routes/:id", async (c) => {
  const route = await c.env.DB.prepare(`SELECT * FROM intercity_routes WHERE id = ?`)
    .bind(c.req.param("id"))
    .first();
  if (!route) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  return c.json({ route });
});

// GET /intercity/schedules?routeId=&from=&date=
intercityRoutes.get("/schedules", async (c) => {
  const routeId = c.req.query("routeId");
  const date = c.req.query("date");
  let q = `SELECT s.*, r.origin_city, r.destination_city, r.base_price, r.duration_minutes
           FROM intercity_schedules s
           JOIN intercity_routes r ON r.id = s.route_id
           WHERE s.status = 'open'`;
  const binds: unknown[] = [];
  if (routeId) {
    q += ` AND s.route_id = ?`;
    binds.push(routeId);
  }
  if (date) {
    // date = YYYY-MM-DD; match depart_at >= start of day, < next day
    q += ` AND date(s.depart_at) = date(?)`;
    binds.push(date);
  }
  q += ` ORDER BY s.depart_at ASC LIMIT 100`;
  const res = await c.env.DB.prepare(q).bind(...binds).all();
  return c.json({ schedules: res.results ?? [] });
});

intercityRoutes.get("/schedules/:id", async (c) => {
  const s = await c.env.DB.prepare(
    `SELECT s.*, r.origin_city, r.destination_city, r.base_price, r.duration_minutes
     FROM intercity_schedules s
     JOIN intercity_routes r ON r.id = s.route_id
     WHERE s.id = ?`,
  )
    .bind(c.req.param("id"))
    .first();
  if (!s) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  return c.json({ schedule: s });
});

// ---- Rider booking (auth required) ----
intercityRoutes.use("/bookings/*", authMiddleware);

// POST /intercity/bookings — book seats on a schedule
intercityRoutes.post("/bookings", async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, intercityBookingSchema);
  if (isResponse(body)) return body;

  const schedule = await c.env.DB.prepare(
    `SELECT id, route_id, depart_at, seats_total, seats_booked, status, captain_id
     FROM intercity_schedules WHERE id = ?`,
  )
    .bind(body.scheduleId)
    .first<{ id: string; route_id: string; depart_at: string; seats_total: number; seats_booked: number; status: string; captain_id: string | null }>();
  if (!schedule) return c.json({ error: "Schedule not found", code: "NOT_FOUND" }, 404);
  if (schedule.status !== "open") return c.json({ error: "Schedule closed", code: "SCHEDULE_CLOSED" }, 400);
  if (schedule.seats_booked + body.seats > schedule.seats_total) {
    return c.json({ error: "Not enough seats available", code: "NO_SEATS" }, 400);
  }
  if (new Date(schedule.depart_at).getTime() < Date.now()) {
    return c.json({ error: "Schedule already departed", code: "DEPARTED" }, 400);
  }

  const route = await c.env.DB.prepare(`SELECT base_price FROM intercity_routes WHERE id = ?`)
    .bind(schedule.route_id)
    .first<{ base_price: number }>();
  const fare = (route?.base_price ?? 0) * body.seats;

  const bookingId = id("intb");
  const qrToken = id("qrtk");
  await c.env.DB.prepare(
    `INSERT INTO intercity_bookings
      (id, schedule_id, rider_id, seats, pickup_station, dropoff_station, fare, payment_method, status, qr_token, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'booked', ?, ?)`,
  )
    .bind(
      bookingId,
      body.scheduleId,
      user.id,
      body.seats,
      body.pickupStation ?? null,
      body.dropoffStation ?? null,
      fare,
      body.paymentMethod,
      qrToken,
      nowIso(),
    )
    .run();
  await c.env.DB.prepare(
    `UPDATE intercity_schedules SET seats_booked = seats_booked + ? WHERE id = ?`,
  )
    .bind(body.seats, body.scheduleId)
    .run();

  // If wallet payment, debit the rider's wallet immediately. Otherwise cash onboard.
  if (body.paymentMethod === "wallet") {
    const balRow = await c.env.DB.prepare(`SELECT wallet_balance FROM users WHERE id = ?`)
      .bind(user.id)
      .first<{ wallet_balance: number }>();
    if ((balRow?.wallet_balance ?? 0) < fare) {
      // Roll back the booking — wasn't enough funds.
      await c.env.DB.prepare(`DELETE FROM intercity_bookings WHERE id = ?`).bind(bookingId).run();
      await c.env.DB.prepare(
        `UPDATE intercity_schedules SET seats_booked = seats_booked - ? WHERE id = ?`,
      )
        .bind(body.seats, body.scheduleId)
        .run();
      return c.json({ error: "رصيد المحفظة غير كافٍ", code: "INSUFFICIENT_BALANCE" }, 400);
    }
    await c.env.DB.prepare(
      `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, trip_id, note, status, created_at)
       VALUES (?, ?, 'trip_payment', 'debit', ?, NULL, ?, 'settled', datetime('now'))`,
    )
      .bind(id("wt"), user.id, fare, `intercity:${bookingId}`)
      .run();
    await c.env.DB.prepare(
      `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_updated_at = ? WHERE id = ?`,
    )
      .bind(fare, nowIso(), user.id)
      .run();
  }

  // Notify the captain assigned (if any) that they have a new booking.
  if (schedule.captain_id) {
    await pushToUser({
      env: c.env,
      userId: schedule.captain_id,
      topic: "intercity.booking.new",
      title: "حجز_seat جديد",
      body: `تم حجز ${body.seats} مقعد على رحلتك القادمة.`,
      data: { bookingId, scheduleId: body.scheduleId, seats: String(body.seats) },
    });
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "intercity.book",
    entityType: "intercity_booking",
    entityId: bookingId,
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
  });

  return c.json({
    ok: true,
    bookingId,
    fare,
    qrToken,
    status: "booked",
    departure: schedule.depart_at,
  });
});

// GET /intercity/bookings — list the rider's bookings
intercityRoutes.get("/bookings", async (c) => {
  const user = c.get("user");
  const res = await c.env.DB.prepare(
    `SELECT b.*, s.depart_at, r.origin_city, r.destination_city
     FROM intercity_bookings b
     JOIN intercity_schedules s ON s.id = b.schedule_id
     JOIN intercity_routes r ON r.id = s.route_id
     WHERE b.rider_id = ?
     ORDER BY b.created_at DESC LIMIT 100`,
  )
    .bind(user.id)
    .all();
  return c.json({ bookings: res.results ?? [] });
});

// ---- Captain side — passenger list on their assigned schedule ----
intercityRoutes.get("/captain/schedules", authMiddleware, requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const res = await c.env.DB.prepare(
    `SELECT s.*, r.origin_city, r.destination_city, r.base_price
     FROM intercity_schedules s
     JOIN intercity_routes r ON r.id = s.route_id
     WHERE s.captain_id = ? AND s.status IN ('open','boarding')
     ORDER BY s.depart_at ASC`,
  )
    .bind(user.id)
    .all();
  return c.json({ schedules: res.results ?? [] });
});

intercityRoutes.get("/captain/schedules/:id/passengers", authMiddleware, requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const scheduleId = c.req.param("id");
  // Captain must own this schedule
  const sched = await c.env.DB.prepare(
    `SELECT captain_id FROM intercity_schedules WHERE id = ?`,
  )
    .bind(scheduleId)
    .first<{ captain_id: string | null }>();
  if (!sched) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  if (sched.captain_id !== user.id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }
  const res = await c.env.DB.prepare(
    `SELECT b.id, b.rider_id, u.name, b.seats, b.pickup_station, b.dropoff_station,
            b.fare, b.payment_method, b.status, b.qr_token
     FROM intercity_bookings b
     JOIN users u ON u.id = b.rider_id
     WHERE b.schedule_id = ?
     ORDER BY b.created_at ASC`,
  )
    .bind(scheduleId)
    .all();
  return c.json({ passengers: res.results ?? [] });
});

// Captain marks a passenger as boarded (attends via QR token if scanned)
intercityRoutes.post("/captain/board/:bookingId", authMiddleware, requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const bookingId = c.req.param("bookingId");
  const body = (await c.req.json().catch(() => ({}))) as { qrToken?: string };
  const booking = await c.env.DB.prepare(
    `SELECT b.id, b.status, b.qr_token, s.captain_id
     FROM intercity_bookings b
     JOIN intercity_schedules s ON s.id = b.schedule_id
     WHERE b.id = ?`,
  )
    .bind(bookingId)
    .first<{ id: string; status: string; qr_token: string; captain_id: string | null }>();
  if (!booking) return c.json({ error: "Booking not found", code: "NOT_FOUND" }, 404);
  if (booking.captain_id !== user.id && user.role !== "admin") {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }
  if (body.qrToken && body.qrToken !== booking.qr_token) {
    return c.json({ error: "Invalid QR", code: "QR_MISMATCH" }, 400);
  }
  if (booking.status === "boarded") return c.json({ ok: true, already: true });
  await c.env.DB.prepare(`UPDATE intercity_bookings SET status = 'boarded' WHERE id = ?`)
    .bind(bookingId)
    .run();
  return c.json({ ok: true });
});

// ---- Admin — manage routes + schedules ----
intercityRoutes.use("/admin/*", authMiddleware, requireRole("admin"));

intercityRoutes.post("/admin/routes", async (c) => {
  const body = await parseBody(c, intercityRouteSchema);
  if (isResponse(body)) return body;
  const routeId = id("intr");
  await c.env.DB.prepare(
    `INSERT INTO intercity_routes
      (id, origin_city, destination_city, distance_km, base_price, vehicle_type_id, duration_minutes, active, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 1, datetime('now'))`,
  )
    .bind(
      routeId,
      body.originCity,
      body.destinationCity,
      body.distanceKm ?? null,
      body.basePrice,
      body.vehicleTypeId ?? null,
      body.durationMinutes ?? null,
    )
    .run();
  return c.json({ ok: true, routeId });
});

intercityRoutes.patch("/admin/routes/:id", async (c) => {
  const id_ = c.req.param("id");
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
  const fields = ["originCity", "destinationCity", "distanceKm", "basePrice", "durationMinutes", "active"]
    .filter((k) => k in body);
  if (!fields.length) return c.json({ error: "No fields", code: "VALIDATION_ERROR" }, 400);
  const assignments = fields
    .map((f) => `${f.replace(/[A-Z]/g, (m) => "_" + m.toLowerCase())} = ?`)
    .join(", ");
  await c.env.DB.prepare(`UPDATE intercity_routes SET ${assignments} WHERE id = ?`)
    .bind(...fields.map((f) => body[f]), id_)
    .run();
  return c.json({ ok: true });
});

intercityRoutes.post("/admin/schedules", async (c) => {
  const body = await parseBody(c, intercityScheduleSchema);
  if (isResponse(body)) return body;
  const schedId = id("ints");
  await c.env.DB.prepare(
    `INSERT INTO intercity_schedules
      (id, route_id, depart_at, seats_total, seats_booked, status, created_at)
     VALUES (?, ?, ?, ?, 0, 'open', datetime('now'))`,
  )
    .bind(schedId, body.routeId, body.departAt, body.seatsTotal)
    .run();
  return c.json({ ok: true, scheduleId: schedId });
});

intercityRoutes.post("/admin/schedules/:id/assign", async (c) => {
  const schedId = c.req.param("id");
  const body = (await c.req.json().catch(() => ({}))) as { captainId?: string };
  if (!body.captainId) return c.json({ error: "captainId required", code: "VALIDATION_ERROR" }, 400);
  await c.env.DB.prepare(`UPDATE intercity_schedules SET captain_id = ? WHERE id = ?`)
    .bind(body.captainId, schedId)
    .run();
  await pushToUser({
    env: c.env,
    userId: body.captainId,
    topic: "intercity.assignment",
    title: "تم تكليفك برحلة بين المحافظات",
    body: "افتح تطبيق الكابتن لتفاصيل الرحلة والمقاعد المحجوزة.",
    data: { scheduleId: schedId },
  });
  return c.json({ ok: true });
});