import { Hono } from "hono";
import { cors } from "hono/cors";
import { TripRoom } from "./durable-objects/TripRoom";
import { GeoCell } from "./durable-objects/GeoCell";
import { CaptainInbox } from "./durable-objects/CaptainInbox";
import { authRoutes } from "./routes/auth";
import { captainRoutes } from "./routes/captain";
import { tripRoutes } from "./routes/trips";
import { adminRoutes } from "./routes/admin";
import { geocodeRoutes } from "./routes/geocode";
import { promoRoutes } from "./routes/promo";
import { userRoutes } from "./routes/user";
import { paymentRoutes } from "./routes/payments";
import { searchRoutes } from "./routes/search";
import { walletRoutes } from "./routes/wallet";
import { deviceRoutes } from "./routes/devices";
import { safetyRoutes } from "./routes/safety";
import { intercityRoutes } from "./routes/intercity";
import { companyRoutes } from "./routes/companies";
import { authMiddleware, type AppEnv } from "./middleware/auth";
import { rateLimit } from "./middleware/rateLimit";

export { TripRoom, GeoCell, CaptainInbox };

const app = new Hono<AppEnv>();

const ALLOWED_ORIGINS = [
  "https://admin.synapticstudio.tech",
  "https://synaptic-go-admin.pages.dev",
  "https://go.synapticstudio.tech",
  "https://captain.synapticstudio.tech",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  "http://localhost:4173",
  "http://127.0.0.1:4173",
];

app.use(
  "*",
  cors({
    origin: (origin) => {
      if (!origin) return "*";
      if (ALLOWED_ORIGINS.includes(origin)) return origin;
      if (origin.endsWith(".synapticstudio.tech")) return origin;
      if (origin.endsWith(".pages.dev")) return origin;
      return ALLOWED_ORIGINS[0];
    },
    allowHeaders: ["Content-Type", "Authorization"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    maxAge: 86400,
  }),
);

// Global soft rate limit (per IP)
app.use(
  "*",
  rateLimit({
    prefix: "global",
    limit: 120,
    windowSec: 60,
  }),
);

app.get("/", (c) =>
  c.json({
    service: "synaptic-go-api",
    name: c.env.APP_NAME ?? "Synaptic Go",
    version: c.env.APP_VERSION ?? "0.3.0",
    docs: "/health",
    features: [
      "otp-auth",
      "whatsapp-otp",
      "refresh-tokens",
      "rate-limit",
      "zod-validation",
      "osrm-routing",
      "geocode",
      "promos",
      "trip-path",
      "websockets",
      "captain-inbox",
      "fcm-push",
      "paymob-real",
      "internal-wallet",
      "scheduled-trips",
      "intercity",
      "b2b-companies",
      "safety-sos",
      "trip-share",
      "in-call-chat",
    ],
  }),
);

app.get("/health", (c) =>
  c.json({
    ok: true,
    service: "synaptic-go-api",
    version: c.env.APP_VERSION ?? "0.3.0",
    time: new Date().toISOString(),
  }),
);

app.route("/auth", authRoutes);
app.route("/captain", captainRoutes);
app.route("/trips", tripRoutes);
app.route("/admin", adminRoutes);
app.route("/geocode", geocodeRoutes);
app.route("/promos", promoRoutes);
app.route("/user", userRoutes);
app.route("/payments", paymentRoutes);
app.route("/", searchRoutes);
app.route("/", walletRoutes);
// New: comprehensive transport platform
app.route("/user", deviceRoutes);     // POST /user/device, DELETE /user/device
app.route("/safety", safetyRoutes);  // sos, share/track, chat
app.route("/intercity", intercityRoutes);
app.route("/companies", companyRoutes);

// WebSocket upgrade for live trip room
app.get("/ws/trips/:id", authMiddleware, async (c) => {
  const upgrade = c.req.header("Upgrade");
  if (upgrade !== "websocket") {
    return c.json({ error: "Expected WebSocket upgrade", code: "UPGRADE_REQUIRED" }, 426);
  }

  const tripId = c.req.param("id");
  if (!tripId) return c.json({ error: "trip id required", code: "MISSING_ID" }, 400);
  const user = c.get("user");

  const trip = await c.env.DB.prepare(`SELECT rider_id, captain_id FROM trips WHERE id = ?`)
    .bind(tripId)
    .first<{ rider_id: string; captain_id: string }>();

  if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
  if (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id) {
    return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
  }

  const id = c.env.TRIP_ROOM.idFromName(tripId);
  const stub = c.env.TRIP_ROOM.get(id);

  const url = new URL("https://room/ws");
  url.searchParams.set("role", user.role);
  url.searchParams.set("userId", user.id);

  return stub.fetch(url.toString(), c.req.raw);
});

// WebSocket for captain live offers inbox
app.get("/ws/captain/offers", authMiddleware, async (c) => {
  const upgrade = c.req.header("Upgrade");
  if (upgrade !== "websocket") {
    return c.json({ error: "Expected WebSocket upgrade", code: "UPGRADE_REQUIRED" }, 426);
  }

  const user = c.get("user");
  if (user.role !== "captain" && user.role !== "admin") {
    return c.json({ error: "Captains only", code: "FORBIDDEN" }, 403);
  }

  const id = c.env.CAPTAIN_INBOX.idFromName(user.id);
  const stub = c.env.CAPTAIN_INBOX.get(id);
  const url = new URL("https://inbox/ws");
  url.searchParams.set("userId", user.id);
  return stub.fetch(url.toString(), c.req.raw);
});

app.notFound((c) => c.json({ error: "Not found", code: "NOT_FOUND" }, 404));
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: err.message || "Internal error", code: "INTERNAL" }, 500);
});

// ---------------------------------------------------------------------------
// Queue consumer — fans out notification batch (writes handled by the
// notifications lib; this lets us retry/dlq without blocking route handlers)
// ---------------------------------------------------------------------------
export default {
  fetch: app.fetch,
  async queue(batch: Message[], env: Env): Promise<void> {
    for (const msg of batch) {
      // Each message carries { userId, topic, title, body, data }
      try {
        const payload = msg.body as {
          userId: string;
          topic: string;
          title: string;
          body: string;
          data?: Record<string, string>;
        };
        // Lazy import to avoid circular type concerns
        const { pushToUser } = await import("./lib/notifications");
        await pushToUser({ env, ...payload });
        msg.ack();
      } catch (e) {
        console.error("notification queue error", e);
        msg.retry();
      }
    }
  },

  // ---- Scheduled (cron) triggers ----
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    const now = new Date().toISOString();
    // Dispatch due scheduled trips: flip status to searching and send offers.
    try {
      const due = await env.DB.prepare(
        `SELECT d.id AS dispatch_id, d.trip_id, t.pickup_lat, t.pickup_lng, t.dropoff_lat,
                t.dropoff_lng, t.city, t.estimated_fare, t.currency
         FROM scheduled_trip_dispatch d
         JOIN trips t ON t.id = d.trip_id
         WHERE d.status = 'pending' AND d.scheduled_for <= ?
           AND t.status = 'searching'`,
      )
        .bind(now)
        .all();
      for (const row of (due.results ?? []) as Array<{
        dispatch_id: string;
        trip_id: string;
        pickup_lat: number;
        pickup_lng: number;
        dropoff_lat: number;
        dropoff_lng: number;
        city: string;
        estimated_fare: number;
        currency: string;
      }>) {
        // Mark dispatched to avoid duplicate processing
        await env.DB.prepare(
          `UPDATE scheduled_trip_dispatch SET status = 'dispatched', dispatched_at = ? WHERE id = ? AND status = 'pending'`,
        )
          .bind(now, row.dispatch_id)
          .run();
        // Push a notification to admins (the actual /trips create already
        // drives nearest-captain matching through GeoCell; scheduled trips
        // flip their status to `offered` automatically once a captain sees
        // them in their inbox).
        const admins = await env.DB.prepare(`SELECT id FROM users WHERE role = 'admin'`).all<{ id: string }>();
        const { pushToUser } = await import("./lib/notifications");
        for (const admin of admins.results ?? []) {
          await pushToUser({
            env,
            userId: admin.id,
            topic: "scheduled.trip.dispatch",
            title: "رحلة مجدولة نشطة الآن",
            body: `الرحلة ${row.trip_id} تم تفعيلها في ${row.city}.`,
            data: { tripId: row.trip_id },
          });
        }
      }
    } catch (e) {
      console.error("scheduled dispatch error", e);
    }

    // On the 1st of each month, generate B2B invoices for active companies.
    try {
      const day = new Date().getUTCDate();
      if (day === 1) {
        const companies = await env.DB.prepare(
          `SELECT id FROM companies WHERE status = 'active'`,
        ).all<{ id: string }>();
        const periodEnd = new Date();
        const periodStart = new Date(periodEnd.getFullYear(), periodEnd.getMonth() - 1, 1);
        for (const cmp of companies.results ?? []) {
          const sum = await env.DB.prepare(
            `SELECT COUNT(*) AS trips, COALESCE(SUM(COALESCE(final_fare, estimated_fare, 0)), 0) AS total
             FROM trips WHERE company_id = ? AND billed_to_company = 1
               AND datetime(created_at) >= datetime(?) AND datetime(created_at) < datetime(?)`,
          )
            .bind(cmp.id, periodStart.toISOString(), periodEnd.toISOString())
            .first<{ trips: number; total: number }>();
          if (sum && sum.trips > 0) {
            const { id: invId } = await import("./lib/utils");
            await env.DB.prepare(
              `INSERT INTO company_invoices
                (id, company_id, period_start, period_end, total_trips, total_amount, status, created_at)
               VALUES (?, ?, ?, ?, ?, ?, 'issued', datetime('now'))`,
            )
              .bind(invId("inv"), cmp.id, periodStart.toISOString(), periodEnd.toISOString(), sum.trips, sum.total)
              .run();
            // Mark the billed trips as settled so next month doesn't re-count.
            await env.DB.prepare(
              `UPDATE trips SET billed_to_company = 0 WHERE company_id = ? AND created_at >= ? AND created_at < ?`,
            )
              .bind(cmp.id, periodStart.toISOString(), periodEnd.toISOString())
              .run();
          }
        }
      }
    } catch (e) {
      console.error("monthly invoice error", e);
    }
  },
};
