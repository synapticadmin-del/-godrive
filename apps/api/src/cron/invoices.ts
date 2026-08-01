import { id as invId } from "../lib/utils";
import type { CronJobInput } from "./types";

/**
 * On the 1st of each month, generate B2B invoices for active companies.
 *
 * Lifted verbatim out of the `scheduled` handler in `index.ts`. The swallowing
 * `try/catch` is gone and `await import("../lib/utils")` became a module-level
 * import; the SQL and the money arithmetic are untouched.
 *
 * The `getUTCDate() === 1` guard is kept even though this job is now
 * registered only against `0 3 1 * *`. It was the *only* thing standing
 * between the old every-minute handler and 1,440 invoice runs on the 1st, and
 * removing it while changing the trigger in the same pass would mean the
 * schedule and the guard were never both true at once. Defence in depth, and
 * one less thing for the verifier to take on trust.
 *
 * Gate item 5 (E07) disables B2B invoicing altogether and owns this file next.
 * The double-billing constraint `UNIQUE(company_id, period_start)` is wave 2
 * per MIGRATION-LOCK §2 — not added here.
 */
export async function runMonthlyInvoiceJob({ env }: CronJobInput): Promise<void> {
  const day = new Date().getUTCDate();
  if (day !== 1) return;

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
