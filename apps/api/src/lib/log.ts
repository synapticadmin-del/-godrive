/**
 * Structured logging — the single telemetry sink for this Worker.
 *
 * §5.4 of the execution plan rules that T22's pipeline is the only sink and
 * that every other track's observability item becomes a *producer* within it.
 * Six tracks each specified their own emission path (T21 geo counters, T18
 * `risk_events`, T19 `analytics_events`, T24 metrics, T03 reconciliation
 * alerts, T11 the audit-failure counter). None of them get their own pipe.
 * If you are adding telemetry, add it here.
 *
 * Findings this closes: F-22-04 (no correlation id anywhere in the stack) and
 * F-22-08 (all 22 log statements are unstructured strings, and the five
 * highest-value route files emit none at all).
 *
 * ## Why `console.log` and not Analytics Engine
 *
 * `wrangler.toml` has `[observability] enabled = true`, so everything written
 * here lands in Workers Logs, where it can be filtered and counted by field.
 * A real Analytics Engine dataset would need an `[[analytics_engine_datasets]]`
 * binding — and `wrangler.toml` belongs to E15, not to this task. Emitting
 * through the log stream keeps the seam inside `owns:` and keeps the call sites
 * identical if a dataset is bound later: only this file changes.
 *
 * ## Do not enable Logpush
 *
 * T22's own constraint, restated in this task's brief: Logpush stays off until
 * the `?token=` WebSocket parameter is gone (`middleware/auth.ts`), or JWTs get
 * persisted to storage. Until then, shipping logs off-platform ships tokens
 * with them. `scrub()` below is defence in depth, not a licence to skip that.
 */

export type LogLevel = "debug" | "info" | "warn" | "error";

export type LogFields = Record<string, unknown>;

/** A single emitted line. Flat by design: nested objects do not filter well. */
export type LogEntry = LogFields & {
  level: LogLevel;
  event: string;
  time: string;
};

/**
 * Keys whose values never appear in a log line, matched case-insensitively as
 * substrings. A bearer token in a log is a credential in a log.
 */
const REDACT = [
  "authorization",
  "token",
  "secret",
  "password",
  "jwt",
  "apikey",
  "api_key",
  "cookie",
  "otp",
];

function isSensitive(key: string): boolean {
  const k = key.toLowerCase();
  return REDACT.some((needle) => k.includes(needle));
}

/**
 * Flatten and redact. Values that cannot be serialised are described rather
 * than dropped, because a log line that silently loses a field is worse than
 * one that says it could not render it.
 */
function scrub(fields: LogFields): LogFields {
  const out: LogFields = {};
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined) continue;
    if (isSensitive(key)) {
      out[key] = "[redacted]";
      continue;
    }
    if (value instanceof Error) {
      out[key] = value.message;
      continue;
    }
    if (
      value === null ||
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean"
    ) {
      out[key] = value;
      continue;
    }
    try {
      out[key] = JSON.stringify(value);
    } catch {
      out[key] = "[unserialisable]";
    }
  }
  return out;
}

/**
 * Emit one line of JSON.
 *
 * Never throws: a logger that can break the request it is describing is worse
 * than no logger. `warn` and `error` go to stderr so they can be separated
 * without parsing, but both streams carry the same JSON shape.
 */
export function log(level: LogLevel, event: string, fields: LogFields = {}): void {
  const entry: LogEntry = {
    ...scrub(fields),
    level,
    event,
    time: new Date().toISOString(),
  };

  let line: string;
  try {
    line = JSON.stringify(entry);
  } catch {
    line = JSON.stringify({ level, event, time: entry.time, error: "log serialisation failed" });
  }

  if (level === "error" || level === "warn") {
    console.error(line);
  } else {
    console.log(line);
  }
}

export const logDebug = (event: string, fields?: LogFields): void => log("debug", event, fields);
export const logInfo = (event: string, fields?: LogFields): void => log("info", event, fields);
export const logWarn = (event: string, fields?: LogFields): void => log("warn", event, fields);
export const logError = (event: string, fields?: LogFields): void => log("error", event, fields);

/**
 * A counter someone can see.
 *
 * Emits `event: "metric"` with a `metric` name and a numeric `value`, so a
 * Workers Logs query filtered to `metric = "audit_write_failed"` counts them,
 * and an alert can be built on the same predicate. This is the mechanism E12's
 * acceptance criterion means by "increments a counter someone can see", and it
 * is the shape §5.7 asks for when an availability control fails open.
 */
export function counter(metric: string, value = 1, fields: LogFields = {}): void {
  log("info", "metric", { ...fields, metric, value });
}

/**
 * Bind a request id (and optionally a route) onto every line from one request.
 *
 * `middleware/requestId.ts` builds one of these per request; anything deeper in
 * the stack that has the context can rebuild it with `getRequestId(c)`.
 */
export type BoundLogger = {
  debug: (event: string, fields?: LogFields) => void;
  info: (event: string, fields?: LogFields) => void;
  warn: (event: string, fields?: LogFields) => void;
  error: (event: string, fields?: LogFields) => void;
  counter: (metric: string, value?: number, fields?: LogFields) => void;
};

export function loggerFor(requestId: string, route?: string): BoundLogger {
  const base: LogFields = { requestId, route };
  return {
    debug: (event, fields) => log("debug", event, { ...base, ...fields }),
    info: (event, fields) => log("info", event, { ...base, ...fields }),
    warn: (event, fields) => log("warn", event, { ...base, ...fields }),
    error: (event, fields) => log("error", event, { ...base, ...fields }),
    counter: (metric, value = 1, fields) =>
      log("info", "metric", { ...base, ...fields, metric, value }),
  };
}

// ---------------------------------------------------------------------------
// Cron dead-man's switch
// ---------------------------------------------------------------------------

/**
 * Read a string off `env` without requiring it to be declared on the `Env`
 * interface.
 *
 * `worker-configuration.d.ts` is generated by `wrangler types` and is not in
 * this task's `owns:`, so the dead-man URLs cannot be added to `Env` here. The
 * cast is contained to this one function on purpose: callers pass their plain
 * `env` and nothing else in the codebase has to know.
 */
function envString(env: unknown, key: string): string | undefined {
  if (typeof env !== "object" || env === null) return undefined;
  const value = (env as Record<string, unknown>)[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/** `scheduled-dispatch` → `SCHEDULED_DISPATCH` */
function envSuffix(job: string): string {
  return job.replace(/[^a-zA-Z0-9]+/g, "_").toUpperCase();
}

export type DeadManOutcome = {
  /** Did the job itself succeed? A failed job still pings, marked `ok: false`. */
  ok?: boolean;
  durationMs?: number;
  /** Anything worth seeing next to the heartbeat — row counts, ids processed. */
  detail?: LogFields;
};

export type DeadManResult = {
  /** True only when an HTTP heartbeat was actually delivered. */
  pinged: boolean;
  status?: number;
  /** Why no ping was sent, or why it failed. Absent on success. */
  reason?: string;
};

const DEAD_MAN_TIMEOUT_MS = 5_000;

/**
 * Tell an external monitor that a cron job just completed.
 *
 * **This is the seam E07 and E09 call.** `cron/invoices.ts` belongs to E07 and
 * `cron/dispatch.ts` to E09; E12 exports this and must not edit either file, so
 * the call sites land with those tasks. Both briefs say "call E12's
 * `pingDeadMan()` from the success path".
 *
 *     await pingDeadMan("company-invoices", env, { ok: true, durationMs });
 *
 * Job names are the ones registered in `cron/scheduled.ts`: `cleanup`,
 * `scheduled-dispatch`, `company-invoices`.
 *
 * ## Why a cron needs this at all
 *
 * F-22-03: a cron that stops running is invisible. E02 fixed the half of that
 * which was inside the Worker — the handler now switches on `event.cron` and a
 * failing job fails the invocation instead of being swallowed. But a Worker
 * whose *trigger* stops firing produces no invocation at all, so there is no
 * failure to record and the dashboard stays green. Only something outside
 * Cloudflare noticing the silence can catch that. That is what a dead-man's
 * switch is: the monitor pages when the ping *stops*.
 *
 * ## Configuration
 *
 * Per-job URL first, then a shared base:
 *
 *   - `DEADMAN_URL_COMPANY_INVOICES`, `DEADMAN_URL_SCHEDULED_DISPATCH`, …
 *   - `DEADMAN_URL_BASE` → `<base>/<job>`
 *
 * Set with `wrangler secret put`. **No monitor exists yet in any file** —
 * F-22-01, and creating one is a console/vendor action no agent can perform.
 * Until a URL is set this function is inert but *visible*: it still emits the
 * `cron.heartbeat` line, so an alert can be built on the log stream alone
 * ("no `cron.heartbeat` with job=cleanup in 15 minutes") with no secret at all.
 *
 * ## Never throws
 *
 * A monitoring call that fails a money job has made things worse. Every failure
 * path here returns a `DeadManResult` and emits a counter instead of raising.
 */
export async function pingDeadMan(
  job: string,
  env?: unknown,
  outcome: DeadManOutcome = {},
): Promise<DeadManResult> {
  const ok = outcome.ok ?? true;

  // The heartbeat is a log line first and an HTTP call second. The line is
  // emitted unconditionally so the switch has value before anyone configures it.
  log(ok ? "info" : "error", "cron.heartbeat", {
    job,
    ok,
    durationMs: outcome.durationMs,
    ...(outcome.detail ?? {}),
  });
  counter("cron_run", 1, { job, ok });

  const url =
    envString(env, `DEADMAN_URL_${envSuffix(job)}`) ??
    (envString(env, "DEADMAN_URL_BASE")
      ? `${envString(env, "DEADMAN_URL_BASE")!.replace(/\/+$/, "")}/${job}`
      : undefined);

  if (!url) {
    return { pinged: false, reason: "unconfigured" };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEAD_MAN_TIMEOUT_MS);
  try {
    // A failed run must not ping the healthy endpoint, or the monitor learns
    // nothing: most services expose `/fail` for exactly this.
    const target = ok ? url : `${url.replace(/\/+$/, "")}/fail`;
    const res = await fetch(target, { method: "POST", signal: controller.signal });
    if (!res.ok) {
      counter("cron_deadman_failed", 1, { job, status: res.status });
      logWarn("cron.deadman.rejected", { job, status: res.status });
      return { pinged: false, status: res.status, reason: `http ${res.status}` };
    }
    return { pinged: true, status: res.status };
  } catch (e) {
    const reason = e instanceof Error ? e.message : "unknown error";
    counter("cron_deadman_failed", 1, { job });
    logWarn("cron.deadman.unreachable", { job, reason });
    return { pinged: false, reason };
  } finally {
    clearTimeout(timer);
  }
}
