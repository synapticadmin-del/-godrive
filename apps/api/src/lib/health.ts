/**
 * `/health` — extracted from `index.ts` so the endpoint can grow without
 * reopening a frozen file.
 *
 * Today this is the same static literal `index.ts` used to return inline: it
 * touches no binding, so it answers 200 while D1, KV or R2 are broken, and it
 * is the only gate in the deploy smoke test (T22 F-22-02). Making it a real
 * probe is E12's job, and E12 owns this file next.
 *
 * The signature is deliberately wider than today's body needs:
 *
 *  - it is **async**, so E12 can await binding probes without changing the
 *    call site in `index.ts`;
 *  - it returns an explicit **status** alongside the body, so E12 can answer
 *    503 on a broken binding — its acceptance criterion — again without
 *    changing the call site.
 *
 * `index.ts` freezes when this task merges, so the shape it delegates through
 * is the shape E12 inherits. Behaviour is unchanged: 200, same four fields.
 */

export type HealthCheck = {
  ok: boolean;
  /** Populated by E12; omitted while the probe is still a literal. */
  error?: string;
};

export type HealthReport = {
  ok: boolean;
  service: string;
  version: string;
  time: string;
  /** Per-binding results. E12 fills this in; absent today. */
  checks?: Record<string, HealthCheck>;
};

export type HealthResult = {
  status: 200 | 503;
  body: HealthReport;
};

export async function checkHealth(env: Env): Promise<HealthResult> {
  return {
    status: 200,
    body: {
      ok: true,
      service: "synaptic-go-api",
      version: env.APP_VERSION ?? "0.3.0",
      time: new Date().toISOString(),
    },
  };
}
