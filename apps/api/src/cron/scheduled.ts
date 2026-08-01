import { runCleanupJob } from "./cleanup";
import { runScheduledDispatchJob } from "./dispatch";
import { runMonthlyInvoiceJob } from "./invoices";
import type { CronJob } from "./types";

/**
 * Cron schedules, exactly as declared in `wrangler.toml` under `[triggers]`
 * and `[env.prod.triggers]`.
 *
 * These strings are matched against `event.cron`, so they have to stay
 * byte-identical to the toml. `wrangler.toml` belongs to E15 — if a schedule
 * there ever changes, this table has to change with it or the invocation
 * throws `no job registered` rather than quietly doing nothing.
 */
export const CRON_EVERY_MINUTE = "*/1 * * * *";
export const CRON_MONTHLY_INVOICES = "0 3 1 * *";

/**
 * Which jobs belong to which schedule.
 *
 * Before the split, one handler ran all three jobs on every tick because it
 * never looked at `event.cron`. The visible consequence was the invoice job
 * executing 1,440 times on the 1st of the month instead of once, held back
 * only by its own internal day guard. Routing each job to the trigger it was
 * written for is the point of this task.
 *
 * Adding a schedule needs a `[triggers]` entry in `wrangler.toml` (E15's file)
 * as well as a row here. A job with no trigger never runs; a trigger with no
 * row throws. Neither fails silently, which is the property that was missing.
 */
const CRON_JOBS: Record<string, readonly CronJob[]> = {
  [CRON_EVERY_MINUTE]: [
    { name: "cleanup", run: runCleanupJob },
    { name: "scheduled-dispatch", run: runScheduledDispatchJob },
  ],
  [CRON_MONTHLY_INVOICES]: [{ name: "company-invoices", run: runMonthlyInvoiceJob }],
};

/**
 * The `scheduled` handler: a dispatcher and nothing else.
 *
 * Two properties the previous handler did not have:
 *
 *  1. **A failing job fails the invocation.** Every job used to sit in its own
 *     `try/catch` that ended at `console.error`, so the handler always resolved
 *     and Cloudflare always recorded success — the dispatch cron could do
 *     nothing for weeks and the dashboard would look healthy (T22 F-22-03).
 *  2. **One job's failure does not skip its siblings.** Jobs on the same
 *     schedule all run; failures are collected and rethrown together at the
 *     end. Letting the first error propagate immediately would have made the
 *     cleanup job able to suppress the dispatch job, which is worse than what
 *     is being replaced.
 *
 * A job that wants to fail softly must catch its own error and say why. None
 * of the three currently do.
 */
export async function handleScheduled(
  event: ScheduledEvent,
  env: Env,
  ctx: ExecutionContext,
): Promise<void> {
  // One timestamp for the whole invocation — see the note on CronJobInput.
  const now = new Date().toISOString();

  const jobs = CRON_JOBS[event.cron];
  if (!jobs) {
    throw new Error(
      `cron: no job registered for schedule "${event.cron}". ` +
        `Add a module in src/cron/ and register it in CRON_JOBS, or remove the trigger from wrangler.toml.`,
    );
  }

  const failed: string[] = [];
  let firstError: unknown;

  for (const job of jobs) {
    try {
      await job.run({ env, ctx, now });
    } catch (e) {
      console.error(`cron job failed: ${job.name} (schedule "${event.cron}")`, e);
      failed.push(job.name);
      if (firstError === undefined) firstError = e;
    }
  }

  if (failed.length > 0) {
    throw new Error(
      `cron "${event.cron}": ${failed.length} of ${jobs.length} job(s) failed: ${failed.join(", ")}`,
      { cause: firstError },
    );
  }
}
