import { runExpiredDataCleanup } from "../lib/cleanup";
import type { CronJobInput } from "./types";

/**
 * Daily expired-data cleanup.
 *
 * Registered against the every-minute trigger, so it gates on a KV last-run
 * key (24h TTL) to run once a day. Lifted verbatim out of the `scheduled`
 * handler in `index.ts`; the only change is that the `try/catch` which
 * swallowed every failure into `console.error` is gone. Errors now propagate
 * to the dispatcher, which logs them and fails the invocation — Cloudflare
 * used to record 100% success no matter what happened in here (T22 F-22-03).
 */
export async function runCleanupJob({ env, now }: CronJobInput): Promise<void> {
  const lastRun = await env.SESSIONS.get("cleanup:last-run");
  if (lastRun) return;

  const result = await runExpiredDataCleanup(env);
  await env.SESSIONS.put("cleanup:last-run", now, { expirationTtl: 86400 });
  console.log("cleanup: daily run complete", JSON.stringify(result));
}
