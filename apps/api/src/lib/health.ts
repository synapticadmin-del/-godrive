/**
 * `/health` — a probe that actually touches its dependencies.
 *
 * Closes F-22-02: this was a static literal returning 200 while D1, KV or R2
 * were broken, and it is the **only gate in the deploy smoke test**. A health
 * check that cannot fail is not a check; it is a a green light wired to nothing,
 * and it was the thing standing between a broken binding and production.
 *
 * The call site in `index.ts` is unchanged and cannot change — that file froze
 * when E02 merged. E02 sized this signature for exactly this rewrite: `async`
 * so bindings can be awaited, and status-carrying so a broken binding can answer
 * 503. Both are used now. `checkHealth(env)` keeps its name, its argument and
 * its return shape; only the body grew.
 *
 * ## What "healthy" means here
 *
 * One cheap operation per binding, chosen so that a *missing or misconfigured*
 * binding fails while a merely *empty* one passes:
 *
 *   - **D1** — `select 1`. Proves the database answers, touches no table, so it
 *     cannot be broken by a migration.
 *   - **KV** — a `get` of a key that does not exist. `null` is success: the read
 *     round-tripped. Writing would make the probe mutate state on every call.
 *   - **R2** — a `head` of a key that does not exist, for the same reason.
 *
 * None of them assert on data, because a health check that fails when a table is
 * empty pages someone on a quiet night.
 */

import { counter, logError } from "./log";

export type HealthCheck = {
  ok: boolean;
  /** Populated when the probe failed. */
  error?: string;
  /** Round-trip time for this binding, in milliseconds. */
  ms?: number;
};

export type HealthReport = {
  ok: boolean;
  service: string;
  version: string;
  time: string;
  /** Per-binding results, so a 503 says *which* dependency is down. */
  checks?: Record<string, HealthCheck>;
};

export type HealthResult = {
  status: 200 | 503;
  body: HealthReport;
};

/**
 * Per-binding ceiling.
 *
 * A hung binding must not hold the health endpoint open — the smoke test would
 * time out with no answer instead of getting a 503 naming the culprit, and an
 * uptime monitor cannot tell a slow probe from a dead one.
 */
const PROBE_TIMEOUT_MS = 2_000;

function withTimeout<T>(work: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    work.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err: unknown) => {
        clearTimeout(timer);
        reject(err instanceof Error ? err : new Error(String(err)));
      },
    );
  });
}

/** Run one probe, never throw, always report how long it took. */
async function probe(name: string, run: () => Promise<unknown>): Promise<HealthCheck> {
  const startedAt = Date.now();
  try {
    await withTimeout(run(), PROBE_TIMEOUT_MS, name);
    return { ok: true, ms: Date.now() - startedAt };
  } catch (e) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : String(e),
      ms: Date.now() - startedAt,
    };
  }
}

/** A key no caller will ever create; the probe wants the miss, not the value. */
const PROBE_KEY = "__health_probe__";

export async function checkHealth(env: Env): Promise<HealthResult> {
  const [db, kv, r2] = await Promise.all([
    probe("d1", async () => {
      if (!env.DB) throw new Error("binding DB is not configured");
      const row = await env.DB.prepare("select 1 as ok").first<{ ok: number }>();
      if (!row || row.ok !== 1) throw new Error("unexpected response from D1");
      return row;
    }),
    probe("kv", async () => {
      if (!env.SESSIONS) throw new Error("binding SESSIONS is not configured");
      // A miss returns null and that is a pass — the round trip is the check.
      return env.SESSIONS.get(PROBE_KEY);
    }),
    probe("r2", async () => {
      if (!env.FILES) throw new Error("binding FILES is not configured");
      return env.FILES.head(PROBE_KEY);
    }),
  ]);

  const checks: Record<string, HealthCheck> = { d1: db, kv: kv, r2: r2 };
  const ok = db.ok && kv.ok && r2.ok;

  if (!ok) {
    // The 503 is what the smoke test reads; these make it diagnosable after the
    // fact, and give the alert rule a predicate that names the binding.
    for (const [name, check] of Object.entries(checks)) {
      if (check.ok) continue;
      logError("health.binding_failed", { binding: name, reason: check.error, ms: check.ms });
      counter("health_binding_failed", 1, { binding: name });
    }
  }

  return {
    status: ok ? 200 : 503,
    body: {
      ok,
      service: "synaptic-go-api",
      version: env.APP_VERSION ?? "0.3.0",
      time: new Date().toISOString(),
      checks,
    },
  };
}
