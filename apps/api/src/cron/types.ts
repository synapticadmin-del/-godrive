/**
 * Shared shape for the scheduled jobs in this directory.
 *
 * Split out of `scheduled.ts` so a job module never has to import the
 * dispatcher that calls it — the registry points one way only, and adding a
 * job cannot create an import cycle.
 */

export type CronJobInput = {
  env: Env;
  ctx: ExecutionContext;
  /**
   * One timestamp for the whole invocation.
   *
   * The pre-split handler computed `new Date().toISOString()` once at the top
   * and every job read that same value, so two jobs in one tick could not
   * disagree about "now". Passing it in preserves that exactly; a job that
   * called `new Date()` itself would be a behaviour change.
   */
  now: string;
};

export type CronJob = {
  /** Used in the failure log line and in the aggregated error. */
  readonly name: string;
  run(input: CronJobInput): Promise<void>;
};
