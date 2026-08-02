import { pingDeadMan } from "../lib/log";
import { id as invId } from "../lib/utils";
import type { CronJobInput } from "./types";

/**
 * B2B company invoicing — **switched off** (execution plan gate item 5, E07).
 *
 * ## Why this job is off rather than fixed
 *
 * It bills paying customers automatically, unalerted, and it bills them wrong:
 *
 *  - **F-08-01 — the same period means two different things in two statements.**
 *    The `SUM` wrapped both sides in `datetime()`; the settling `UPDATE` compared
 *    raw strings. `trips.created_at` carries the table default's
 *    `'YYYY-MM-DD HH:MM:SS'` (`0001_init.sql:80` — the `INSERT` in `trips.ts:405`
 *    never binds the column), while both statements bound a JS
 *    `toISOString()` `'YYYY-MM-DDTHH:MM:SS.sssZ'`. A space sorts before `'T'`,
 *    so every trip created on the *first day* of the period failed the raw
 *    compare, was never marked settled, and was re-invoiced on the next run.
 *  - **F-08-20 — a second generator with the mirror defect.** `POST
 *    /companies/admin/:id/invoice` (`routes/companies.ts:200`, cited as `:167`
 *    in the brief before E04's guard shifted it) ran the same arithmetic with
 *    the raw compare on *both* statements, so it under-billed instead.
 *  - **F-20-16 — T20 reproduced all three billing outcomes in SQLite.**
 *
 * Before E02 routed this job to `0 3 1 * *`, it ran on the every-minute trigger:
 * 1,440 invocations on the 1st, held back only by the `getUTCDate() === 1` guard
 * below, each one re-issuing the first-day trips. Nothing in the schema stops
 * the duplicate — `company_invoices` has no `UNIQUE(company_id, period_start)`
 * (`0003_global_transport.sql:144`), and that constraint is wave 2 per
 * `MIGRATION-LOCK.md` §2, not this task.
 *
 * ## What is still true with the job off
 *
 * Trips keep accumulating with `billed_to_company = 1` (`trips.ts:412`). Nothing
 * is lost, nothing is written, and the backlog is invoiceable by hand from the
 * period query below. Turning the job off does not forgive the debt; it stops
 * the machine that was computing it wrongly.
 *
 * The B2B vertical itself is already unreachable over HTTP — E04 answers 501 on
 * every `/companies` handler and E02 unmounted the router so the public sees a
 * 404. This job is the one B2B code path that does **not** go through the
 * router, which is why it needs its own switch.
 *
 * ## Re-enabling
 *
 * Delete the guard block in `runMonthlyInvoiceJob` — it is marked, it is
 * contiguous, and deleting it is the whole act. There is deliberately no flag to
 * flip and no environment variable to set: a boolean someone can toggle from a
 * dashboard is how an unverified money path comes back at 03:00 on a Sunday.
 *
 * Do not delete it until all four hold:
 *
 *  1. `UNIQUE(company_id, period_start)` exists on `company_invoices`, so a
 *     double run is refused by the database rather than by this code being right.
 *  2. The money question below is settled — this generator sums the legacy
 *     `REAL` columns, and `0005` made piastres the integer source of truth.
 *  3. The B2B vertical is back in the launch shape (E04's `COMPANIES_ENABLED`),
 *     because an invoice nobody can fetch over HTTP is not a feature.
 *  4. Someone has re-run the reproduction against a restored copy of production
 *     (E18's rehearsed restore) and counted the duplicate rows already there.
 *
 * ## The money question, left open on purpose
 *
 * `generateCompanyInvoice` sums `COALESCE(final_fare, estimated_fare, 0)` —
 * `REAL` EGP. Migration `0005` introduced `final_fare_piastres` /
 * `estimated_fare_piastres` as the integer source of truth for exactly the
 * float-accumulation reason this sum demonstrates, and E08 moved settlement onto
 * a single integer-piastre primitive (`lib/money.ts`). This file was **not**
 * migrated to piastres here: `trips.ts:878` still writes the `REAL` columns and
 * not their piastre counterparts, so switching the sum today would bill zero.
 * Reconciling the two is a money change that belongs with the money primitive
 * and its owner, not smuggled into a shutdown. Named, not fixed.
 */

/** A billing window, as the two half-open bounds the SQL binds. */
export type CompanyInvoicePeriod = {
  /** Inclusive lower bound. */
  readonly start: string;
  /** Exclusive upper bound. */
  readonly end: string;
};

export type CompanyInvoiceResult = {
  readonly companyId: string;
  readonly invoiceId: string;
  readonly trips: number;
  readonly total: number;
};

/**
 * The previous whole UTC month, relative to the invocation timestamp.
 *
 * The shipped code built this from `new Date(y, m - 1, 1)` — a **local-time**
 * constructor — and used `new Date()` itself as the upper bound. Two consequences,
 * both fixed here because a "collapse to one generator" that kept them would be
 * collapsing onto the broken one:
 *
 *  - the upper bound was *now*, not the month boundary, so a run at 03:00 on the
 *    1st swept the first three hours of the new month into the old month's invoice;
 *  - `now` came from `new Date()` rather than the invocation's shared timestamp,
 *    which `CronJobInput` exists to provide (see the note in `cron/types.ts`).
 */
export function previousUtcMonth(nowIso: string): CompanyInvoicePeriod {
  const now = new Date(nowIso);
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  return { start: start.toISOString(), end: end.toISOString() };
}

/**
 * **The single invoice generator.** Unreachable today; see the guard.
 *
 * The collapse the brief asks for: one function, one definition of the period,
 * one predicate. The two statements now agree, which is the whole of F-08-01:
 *
 *  - both wrap **both** sides in `datetime()`, so neither depends on how
 *    `created_at` happens to be spelled;
 *  - the `UPDATE` carries `billed_to_company = 1`, so it settles exactly the rows
 *    the `SUM` counted rather than every trip in the window.
 *
 * `routes/companies.ts` is E04's file and its copy is **not** touched from here —
 * it is dead by E04's 501 guard and E02's unmount, not by an edit of mine.
 *
 * Not idempotent on its own: called twice for one period it writes two invoices.
 * That is precondition 1 above, and it is a schema job, not a code job.
 */
export async function generateCompanyInvoice(
  db: D1Database,
  companyId: string,
  period: CompanyInvoicePeriod,
): Promise<CompanyInvoiceResult | null> {
  const sum = await db
    .prepare(
      `SELECT COUNT(*) AS trips, COALESCE(SUM(COALESCE(final_fare, estimated_fare, 0)), 0) AS total
       FROM trips WHERE company_id = ? AND billed_to_company = 1
         AND datetime(created_at) >= datetime(?) AND datetime(created_at) < datetime(?)`,
    )
    .bind(companyId, period.start, period.end)
    .first<{ trips: number; total: number }>();

  if (!sum || sum.trips <= 0) return null;

  const invoiceId = invId("inv");
  await db
    .prepare(
      `INSERT INTO company_invoices
        (id, company_id, period_start, period_end, total_trips, total_amount, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 'issued', datetime('now'))`,
    )
    .bind(invoiceId, companyId, period.start, period.end, sum.trips, sum.total)
    .run();

  await db
    .prepare(
      `UPDATE trips SET billed_to_company = 0
       WHERE company_id = ? AND billed_to_company = 1
         AND datetime(created_at) >= datetime(?) AND datetime(created_at) < datetime(?)`,
    )
    .bind(companyId, period.start, period.end)
    .run();

  return { companyId, invoiceId, trips: sum.trips, total: sum.total };
}

/**
 * The registered `company-invoices` job (`cron/scheduled.ts`, schedule `0 3 1 * *`).
 *
 * Still registered on purpose. An unregistered schedule produces no invocation,
 * and no invocation is indistinguishable from a Worker whose triggers have
 * stopped firing — the silence F-22-03 is about. Registered-and-refusing emits a
 * `cron.heartbeat` every month, so the dead-man switch keeps proving the cron
 * plumbing is alive while the billing behind it is off.
 */
export async function runMonthlyInvoiceJob({ env, now }: CronJobInput): Promise<void> {
  const startedAt = Date.now();

  // ─── GUARD — B2B invoicing is OFF (gate item 5). DELETE THIS BLOCK TO RE-ENABLE. ───
  //
  // Read the four preconditions in the module comment first. Deleting this block
  // down to the marked line restores the job exactly as it is written below.
  //
  // `pingDeadMan` is documented never to throw, so the heartbeat cannot be the
  // thing that fails a money job.
  await pingDeadMan("company-invoices", env, {
    ok: true,
    durationMs: Date.now() - startedAt,
    detail: {
      billing: "disabled",
      gate_item: 5,
      task: "E07",
      findings: "F-08-01, F-08-20, F-20-16",
      reason: "period predicate disagreed between SUM and settling UPDATE; re-billed first-day trips",
    },
  });
  return;
  // ─── END GUARD — delete to here ───────────────────────────────────────────────

  // The `getUTCDate() === 1` check is E02's, kept deliberately. This job is now
  // registered only against `0 3 1 * *`, so it is redundant — and it was the only
  // thing standing between the old every-minute handler and 1,440 invoice runs on
  // the 1st. It costs one comparison a month.
  const day = new Date(now).getUTCDate();
  if (day !== 1) return;

  const period = previousUtcMonth(now);
  const companies = await env.DB.prepare(
    `SELECT id FROM companies WHERE status = 'active'`,
  ).all<{ id: string }>();

  const issued: CompanyInvoiceResult[] = [];
  for (const cmp of companies.results ?? []) {
    const result = await generateCompanyInvoice(env.DB, cmp.id, period);
    if (result) issued.push(result);
  }

  await pingDeadMan("company-invoices", env, {
    ok: true,
    durationMs: Date.now() - startedAt,
    detail: {
      billing: "enabled",
      companies: (companies.results ?? []).length,
      invoices: issued.length,
      period_start: period.start,
      period_end: period.end,
    },
  });
}
