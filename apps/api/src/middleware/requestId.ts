/**
 * Request-correlation id.
 *
 * Closes F-22-04: there is no correlation id anywhere in the stack — client,
 * Worker, or Durable Objects — so a report of "my trip never got a captain" has
 * no thread to pull. One id per request, on the context, echoed to the caller,
 * and stamped on every structured log line that request produces.
 *
 * ## Read this before assuming it is live: THE MOUNT IS MISSING
 *
 * `index.ts` reserves the position — first `app.use("*", …)`, ahead of CORS,
 * the rate limiter and every route — but it is a **passthrough**, and `index.ts`
 * froze when E02 merged (PROTOCOL-EXEC §8). E02 wrote the trap into the file
 * itself: the `await import()` late-bind that activates E13's and E16's public
 * mounts does not work here, because those modules already existed and only an
 * export was missing, whereas this module did not exist at all.
 *
 * Now it does. Activating it is one line, and it is an edit to a frozen file, so
 * it needs an explicit exemption rather than a quiet reach across the boundary —
 * E02's words, and this task takes them literally. The exact diff is in the PR.
 *
 * Until that line lands, everything below is dead code that compiles. Do not
 * read a green build as evidence that requests are being correlated.
 */

import type { Context, MiddlewareHandler } from "hono";
import { loggerFor, type BoundLogger } from "../lib/log";

/**
 * Response header name.
 *
 * Lowercase on the wire regardless; spelled this way to match the `X-Request-Id`
 * convention clients already expect. `packages/flutter_shared`'s `api_client`
 * should send the same header so a trace starts on the handset rather than at
 * the edge — that file is not in this task's `owns:`, so it is named in the PR
 * and not touched here.
 */
export const REQUEST_ID_HEADER = "X-Request-Id";

/** Context variables this middleware sets. */
export type RequestIdVariables = {
  requestId: string;
  logger: BoundLogger;
};

export type RequestIdEnv = {
  Bindings: Env;
  Variables: RequestIdVariables;
};

/**
 * Longest inbound id we will echo. Long enough for a UUID or a W3C traceparent,
 * short enough that a caller cannot use the header as free log storage.
 */
const MAX_ID_LENGTH = 128;

/** Conservative: an id ends up in log lines, so keep it to safe characters. */
const SAFE_ID = /^[A-Za-z0-9_.:-]+$/;

/**
 * Trust the caller's id when it is well-formed, otherwise mint one.
 *
 * Accepting a client id is what makes a trace span the handset and the Worker.
 * Accepting it *unvalidated* would let a caller inject newlines into the log
 * stream and forge entries, so the shape is checked before it is trusted.
 */
function normaliseInbound(raw: string | undefined): string | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_ID_LENGTH) return null;
  if (!SAFE_ID.test(trimmed)) return null;
  return trimmed;
}

function mint(): string {
  try {
    return crypto.randomUUID();
  } catch {
    // randomUUID is available in Workers; this is belt-and-braces for a
    // runtime where it is not, because an id is not worth an exception.
    return `req-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  }
}

/**
 * Read the id from anywhere that has the context.
 *
 * Deliberately tolerant: returns `""` rather than throwing when the middleware
 * is not mounted, so a caller cannot be broken by the missing mount described
 * above. The cast is because most route modules are typed against `AppEnv`
 * (`middleware/auth.ts`), which does not declare these variables — and that
 * file is not in this task's `owns:`.
 */
export function getRequestId(c: Context): string {
  const value = (c as unknown as Context<RequestIdEnv>).get("requestId");
  return typeof value === "string" ? value : "";
}

/**
 * Get a logger already bound to this request's id and route.
 *
 * Falls back to an unbound logger when the middleware is not mounted, so route
 * code can adopt it now and start correlating the moment the mount lands.
 */
export function getLogger(c: Context): BoundLogger {
  const existing = (c as unknown as Context<RequestIdEnv>).get("logger");
  if (existing) return existing;
  return loggerFor(getRequestId(c), c.req.routePath ?? c.req.path);
}

/**
 * The middleware. Mount first, ahead of everything.
 *
 * Emits exactly one `http.request` line per request, after the handler, with
 * the status and duration on it. One line rather than two (in/out) because a
 * paired-line format doubles log volume to say the same thing, and the pair
 * only reconciles if both survive.
 */
export function requestId(): MiddlewareHandler<RequestIdEnv> {
  return async (c, next) => {
    const inbound = normaliseInbound(c.req.header(REQUEST_ID_HEADER) ?? c.req.header("cf-ray"));
    const id = inbound ?? mint();

    c.set("requestId", id);
    // Bound with the concrete path: this middleware runs *before* routing, so
    // `routePath` is still the middleware's own pattern ("/*") at this point.
    // The access line below is emitted after `next()`, where it has resolved.
    c.set("logger", loggerFor(id, c.req.path));

    // Set early so it is present even if the handler throws and an error
    // response is produced somewhere above this middleware.
    c.header(REQUEST_ID_HEADER, id);

    const startedAt = Date.now();
    try {
      await next();
    } finally {
      const durationMs = Date.now() - startedAt;
      const status = c.res?.status;
      // Resolved now that routing has run. Keeps cardinality low: "/trips/:id",
      // not one distinct log dimension per trip id.
      const route = c.req.routePath ?? c.req.path;

      // `c.res` can be replaced by a downstream handler, which drops headers
      // set earlier. Re-stamping is cheap and makes the echo unconditional.
      try {
        c.res?.headers.set(REQUEST_ID_HEADER, id);
      } catch {
        // An immutable Response (e.g. a WebSocket upgrade) cannot be stamped.
        // The id is still on every log line, which is the part that matters.
      }

      const level = status && status >= 500 ? "error" : "info";
      const line = {
        requestId: id,
        method: c.req.method,
        route,
        path: c.req.path,
        status,
        durationMs,
      };
      if (level === "error") {
        loggerFor(id, route).error("http.request", line);
      } else {
        loggerFor(id, route).info("http.request", line);
      }

      // Gives the 5xx-rate alert the brief asks for a single predicate to sit
      // on, without needing a log-parsing rule per route.
      if (status && status >= 500) {
        loggerFor(id, route).counter("http_5xx", 1, { route, status });
      }
    }
  };
}
