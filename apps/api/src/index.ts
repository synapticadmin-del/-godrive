import { Hono } from "hono";
import type { Context } from "hono";
import { cors } from "hono/cors";
import { TripRoom } from "./durable-objects/TripRoom";
import { GeoCell } from "./durable-objects/GeoCell";
import { CaptainInbox } from "./durable-objects/CaptainInbox";
import { OfferScheduler } from "./durable-objects/OfferScheduler";
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
// `intercityRoutes` and `companyRoutes` are deliberately NOT imported: both
// verticals are unmounted for launch (§2.1 of the execution plan, gate item 3).
// The route modules still exist and are E04's to reject at the schema level;
// unmounting here is what makes /intercity/* and /companies/* 404 today.
// These are G1‡ — disabled, not fixed — and nothing in wave 1 re-mounts them.
import { authMiddleware, type AppEnv } from "./middleware/auth";
import { rateLimit } from "./middleware/rateLimit";
import { checkHealth } from "./lib/health";
import { handleScheduled } from "./cron/scheduled";

export { TripRoom, GeoCell, CaptainInbox, OfferScheduler };

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

// ---------------------------------------------------------------------------
// Reserved mount point: request-correlation id — E12.
//
// Registered ahead of every other middleware and every route, which is the
// position E12's brief asks for ("mounted ahead of all routes (E02 left the
// mount point)"). It is a passthrough today because `middleware/requestId.ts`
// does not exist yet and belongs to E12.
//
// SEAM — read this before assuming E12 can just merge. The two public route
// mounts further down late-bind through `await import()` because their target
// *modules* already exist and only the export is missing. That trick is not
// available here: the module itself is absent, so a literal `import()` of it
// fails to bundle and fails `tsc` today. Activating this therefore needs the
// one thing this file is about to forbid — an edit to `index.ts` after the
// freeze. Flagged on the PR; E12 needs an explicit one-line exemption rather
// than a quiet reach across the boundary.
app.use("*", async (_c, next) => {
  await next();
});

app.use(
  "*",
  cors({
    origin: (origin) => {
      if (!origin) return "*";
      if (ALLOWED_ORIGINS.includes(origin)) return origin;
      if (origin.endsWith(".synapticstudio.tech")) return origin;
      // Deliberately NOT trusting all of *.pages.dev: anyone can deploy a site
      // on that shared domain and would then be same-origin-trusted by this API.
      // The project's own Pages deployment is listed in ALLOWED_ORIGINS above.
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
      // "intercity" and "b2b-companies" are no longer advertised here: both
      // are unmounted for launch and every path under them answers 404.
      // Advertising a 404 as a feature is the same class of untruth as the
      // "authorities are notified" SOS copy E05 deleted.
      "safety-sos",
      "trip-share",
      "in-call-chat",
    ],
  }),
);

// Delegates to lib/health.ts. That module is E12's next, and its signature
// already carries an awaitable body and an explicit status so a real probe can
// answer 503 on a broken binding without reopening this file.
app.get("/health", async (c) => {
  const { status, body } = await checkHealth(c.env);
  return c.json(body, status);
});

// ---------------------------------------------------------------------------
// Public mounts — the paths that must resolve without a JWT.
//
// Both point at exports that are not on `main` yet: `publicUserRoutes` is
// written and waiting in E16's PR #92, and `publicSafetyRoutes` is E13's,
// which has not started. This file freezes when this task merges, so this is
// the last opportunity to create either mount at all.
//
// Why they late-bind instead of importing normally: a static
// `import { publicUserRoutes } from "./routes/user"` does not compile against
// `main` today, and CI gates on `tsc --noEmit`. Copying the handlers in here
// instead would fork the exact payload E13 is tasked with redacting, into a
// file nobody may edit afterwards. So the target module — which does exist, so
// the bundle resolves — is probed for the export at request time. While the
// export is absent the request falls through to the authenticated router,
// which is precisely today's behaviour, and no route changes meaning.
//
// CONTRACT for E13 and E16. Paths inside a public router are relative to the
// mount prefix, i.e. ordinary `app.route(prefix, router)` semantics:
//     routes/user.ts    → export const publicUserRoutes    with "/deletion-request"
//     routes/safety.ts  → export const publicSafetyRoutes  with "/track/:token"
// E16's PR #92 already matches this exactly. E13 can lift its existing
// `safetyRoutes.get("/track/:token")` handler across unchanged.
// ---------------------------------------------------------------------------

// Derived from Hono's own Context rather than the global workers-types
// `ExecutionContext`. The two have drifted — workers-types now carries a
// `tracing` member Hono's does not — and the object actually being passed here
// is the one Hono hands us, so taking the type from the same place keeps this
// correct across future type-package bumps.
type HonoExecutionContext = Context<AppEnv>["executionCtx"];

type MountableRouter = {
  fetch: (
    request: Request,
    env: Env,
    ctx: HonoExecutionContext,
  ) => Response | Promise<Response>;
};

async function resolveOptionalRouter(
  load: () => Promise<Record<string, unknown>>,
  exportName: string,
): Promise<MountableRouter | null> {
  const candidate = (await load())[exportName] as MountableRouter | undefined;
  return candidate && typeof candidate.fetch === "function" ? candidate : null;
}

/** Re-address the request the way a sub-router sees it: without the mount prefix. */
function withoutMountPrefix(c: Context<AppEnv>, prefix: string): Request {
  const url = new URL(c.req.url);
  url.pathname = url.pathname.slice(prefix.length) || "/";
  return new Request(url, c.req.raw);
}

// GET/POST /user/deletion-request — the unauthenticated deletion entry point
// the app stores require. Without it the store-listing URL answers 401 and the
// listing is rejected (gate item 12). Falls through to the authenticated
// userRoutes, and so still 401s, until E16 merges.
app.use("/user/deletion-request", async (c, next) => {
  const router = await resolveOptionalRouter(() => import("./routes/user"), "publicUserRoutes");
  if (!router) return next();
  return router.fetch(withoutMountPrefix(c, "/user"), c.env, c.executionCtx);
});

// GET /safety/track/:token — the one /safety path that must be public. Today
// it sits behind `safetyRoutes.use("*", authMiddleware)` (safety.ts:11), so the
// family member holding a share link gets a 401 instead of the trip. Mounted
// ahead of the authenticated router; inert until E13 exports the handler.
app.use("/safety/track/*", async (c, next) => {
  const router = await resolveOptionalRouter(() => import("./routes/safety"), "publicSafetyRoutes");
  if (!router) return next();
  return router.fetch(withoutMountPrefix(c, "/safety"), c.env, c.executionCtx);
});

// ---------------------------------------------------------------------------
// Launch shape: /intercity and /companies are off (gate item 3).
//
// Dropping the two `app.route(...)` mounts is necessary but NOT sufficient, and
// this is the one part of the task that does not work the obvious way.
// `searchRoutes` and `walletRoutes` are both mounted at "/" and both open with
// `use("*", authMiddleware)` — a `*` at the root matches every path in the app.
// So an unmounted path is still matched by that middleware and answers
// 401 UNAUTHORIZED long before it can reach `app.notFound()`. Verified: with the
// mounts simply removed, `GET /intercity/quote` returns 401, not 404.
//
// 401 is the wrong answer for a vertical that no longer exists — it reads as
// "authenticate and try again", which is exactly the invitation the launch
// shape is meant to withdraw. These paths are therefore terminated explicitly,
// ahead of the "/" mounts. Registered before them, so they short-circuit.
//
// This block is the enforcement point for the client-side half E05 shipped; the
// schema-level rejection is still E04's.
for (const path of ["/intercity", "/intercity/*", "/companies", "/companies/*"]) {
  app.all(path, (c) => c.json({ error: "Not found", code: "NOT_FOUND" }, 404));
}

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
// /intercity and /companies are intentionally not mounted — see the import
// block. Both now fall through to app.notFound() and return 404.

// WebSocket upgrade for live trip room.
// Auth: the Authorization header or a (deprecated) ?token= query param are
// handled by authMiddleware. If neither is present the request still reaches
// the DO in a "pending auth" state: the client must send
// {"type":"auth","token":"<jwt>"} as its first message (10s timeout).
app.get("/ws/trips/:id", async (c) => {
  const upgrade = c.req.header("Upgrade");
  if (upgrade !== "websocket") {
    return c.json({ error: "Expected WebSocket upgrade", code: "UPGRADE_REQUIRED" }, 426);
  }

  const tripId = c.req.param("id");
  if (!tripId) return c.json({ error: "trip id required", code: "MISSING_ID" }, 400);

  const url = new URL("https://room/ws");

  const header = c.req.header("Authorization");
  const bearer = header?.startsWith("Bearer ") ? header.slice(7) : null;
  // DEPRECATED: ?token= leaks JWTs into access logs; kept only for old app
  // versions during rollout. New clients use the first-message auth flow.
  const queryToken = c.req.query("token") ?? null;
  const token = bearer ?? queryToken;

  if (token) {
    // Inline the same checks authMiddleware performs (the route no longer runs
    // the middleware so unauthenticated clients can reach the pending-auth
    // handoff below).
    const { verifyToken } = await import("./lib/jwt");
    try {
      const user = await verifyToken(token, c.env.JWT_SECRET, c.env.JWT_ISSUER);
      if (user.typ === "refresh") {
        return c.json({ error: "Use access token", code: "WRONG_TOKEN_TYPE" }, 401);
      }
      const trip = await c.env.DB.prepare(`SELECT rider_id, captain_id FROM trips WHERE id = ?`)
        .bind(tripId)
        .first<{ rider_id: string; captain_id: string }>();

      if (!trip) return c.json({ error: "Trip not found", code: "NOT_FOUND" }, 404);
      if (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id) {
        return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
      }

      url.searchParams.set("role", user.role);
      url.searchParams.set("userId", user.id);
    } catch {
      return c.json({ error: "Invalid or expired token", code: "INVALID_TOKEN" }, 401);
    }
  } else {
    // No credentials up front: let the DO accept the socket and authenticate
    // via the first client message. The DO enforces trip membership after
    // verifying the token and closes with 4401 on failure/timeout.
    url.searchParams.set("pendingAuth", "1");
    url.searchParams.set("tripId", tripId);
  }

  const id = c.env.TRIP_ROOM.idFromName(tripId);
  const stub = c.env.TRIP_ROOM.get(id);
  return stub.fetch(url.toString(), c.req.raw);
});

// WebSocket for captain live offers inbox.
// Same dual auth as /ws/trips/:id — header/deprecated query token, or a
// first-message {"type":"auth","token":"<jwt>"} when no token is supplied.
app.get("/ws/captain/offers", async (c) => {
  const upgrade = c.req.header("Upgrade");
  if (upgrade !== "websocket") {
    return c.json({ error: "Expected WebSocket upgrade", code: "UPGRADE_REQUIRED" }, 426);
  }

  const url = new URL("https://inbox/ws");

  const header = c.req.header("Authorization");
  const bearer = header?.startsWith("Bearer ") ? header.slice(7) : null;
  // DEPRECATED: ?token= leaks JWTs into access logs; kept only for old app
  // versions during rollout. New clients use the first-message auth flow.
  const queryToken = c.req.query("token") ?? null;
  const token = bearer ?? queryToken;

  if (token) {
    const { verifyToken } = await import("./lib/jwt");
    try {
      const user = await verifyToken(token, c.env.JWT_SECRET, c.env.JWT_ISSUER);
      if (user.typ === "refresh") {
        return c.json({ error: "Use access token", code: "WRONG_TOKEN_TYPE" }, 401);
      }
      if (user.role !== "captain" && user.role !== "admin") {
        return c.json({ error: "Captains only", code: "FORBIDDEN" }, 403);
      }

      const id = c.env.CAPTAIN_INBOX.idFromName(user.id);
      const stub = c.env.CAPTAIN_INBOX.get(id);
      url.searchParams.set("userId", user.id);
      return stub.fetch(url.toString(), c.req.raw);
    } catch {
      return c.json({ error: "Invalid or expired token", code: "INVALID_TOKEN" }, 401);
    }
  }

  // Pending-auth handoff: without a token we can't derive the per-captain DO
  // id yet, so a single well-known inbox instance accepts the socket, verifies
  // the first-message token, then proxies the socket pair to the captain's
  // own inbox (which skips the timeout there).
  const id = c.env.CAPTAIN_INBOX.idFromName("pending-auth");
  const stub = c.env.CAPTAIN_INBOX.get(id);
  url.searchParams.set("pendingAuth", "1");
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
  //
  // One dispatcher, in src/cron/. It switches on `event.cron` so each job runs
  // on the schedule it was written for, and a job that throws now fails the
  // invocation instead of being swallowed into console.error while Cloudflare
  // records success (T22 F-22-03). The job bodies moved across unchanged.
  scheduled: handleScheduled,
};
