/**
 * Trip settlement — the balance moves that a completed trip causes.
 *
 * Lifted verbatim out of the `POST /trips/:id/complete` handler in
 * `routes/trips.ts` (lines 985-1055 at base `b0c0866`, still 985-1055 at
 * `f58f227` — E02 did not touch this file). This is E03, a pure structural
 * pass: the block moved, nothing in it changed.
 *
 * **The known bugs moved with it, deliberately.** The rider debit and the
 * captain credit are not one transaction: when the rider has insufficient
 * balance the debit writes `status = 'failed'` and execution continues to
 * credit the captain anyway, so the platform mints the fare. That is gate
 * item 6 and it belongs to **E08**, which owns this file next. Fixing it here
 * would have made this PR unreviewable as a refactor — see PROTOCOL-EXEC §4,
 * "pure refactors ship alone".
 *
 * One mechanical rename on the way across: `c.env.DB` became the `db`
 * parameter. No conditional, no ordering, no SQL string, and no bound value
 * differs from the original.
 */

import type { DbTrip } from "./types";
import { id, nowIso } from "./utils";

export type SettleTripCompletionInput = {
  db: D1Database;
  /** The trip row as read *before* the completion UPDATE, exactly as the handler had it. */
  trip: DbTrip;
  tripId: string;
  finalFare: number;
  commission: number;
  captainPayout: number;
};

/**
 * Apply the wallet consequences of a completed trip.
 *
 * Caller keeps ownership of the `trips` UPDATE, the `trip_events` write and
 * the completion push notifications; this function is only the money.
 */
export async function settleTripCompletion({
  db,
  trip,
  tripId,
  finalFare,
  commission,
  captainPayout,
}: SettleTripCompletionInput): Promise<void> {
  // Wallet handling:
  //  - Wallet (rider): debit the rider, credit the captain's payout.
  //  - Company-billed (B2B): no rider debit; finance is collected monthly.
  //  - Cash: the captain collected the fare in hand, so DEBIT the platform
  //    commission from the captain instead of crediting a payout. Crediting
  //    here would pay the captain twice and forfeit the commission.
  // All wallet moves are keyed by idempotency_key (unique index idx_wt_idem)
  // so a retried completion cannot double-apply a balance change.
  if (trip.payment_method === "wallet" && !trip.billed_to_company && trip.rider_id) {
    const idemKey = `trip_debit:${tripId}`;
    const finalFarePiastres = Math.round(finalFare * 100);

    const debitRes = await db.prepare(
      `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
    )
      .bind(finalFare, finalFarePiastres, nowIso(), trip.rider_id, finalFare)
      .run();

    const txnStatus = (debitRes.meta && debitRes.meta.changes === 1) ? 'settled' : 'failed';

    await db.prepare(
      `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
       VALUES (?, ?, 'trip_payment', 'debit', ?, ?, ?, ?, ?, ?, datetime('now'))`,
    )
      .bind(id("wt"), trip.rider_id, finalFare, finalFarePiastres, tripId, idemKey, txnStatus === 'settled' ? 'رحلة مكتملة' : 'فشل الخصم - رصيد غير كافٍ', txnStatus)
      .run();
  }
  if (trip.captain_id) {
    if (trip.payment_method === "cash") {
      // Cash: the captain already collected the full fare in hand from the rider.
      // The platform is owed its commission, so debit that amount from the
      // captain's wallet instead of crediting a payout.
      const commissionPiastres = Math.round(commission * 100);
      if (commission > 0) {
        const idemKey = `trip_commission_debit:${tripId}`;
        const ins = await db.prepare(
          `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
           VALUES (?, ?, 'commission', 'debit', ?, ?, ?, ?, 'عمولة المنصة على رحلة نقدية', 'settled', datetime('now'))`,
        )
          .bind(id("wt"), trip.captain_id, commission, commissionPiastres, tripId, idemKey)
          .run();

        // Only move the balance if this is the first time we recorded the debit.
        if (ins.meta && ins.meta.changes === 1) {
          await db.prepare(
            `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?, wallet_updated_at = ? WHERE id = ?`,
          )
            .bind(commission, commissionPiastres, nowIso(), trip.captain_id)
            .run();
        }
      }
    } else {
      // Non-cash: the platform collected the fare, so credit the captain's payout.
      const payoutPiastres = Math.round(captainPayout * 100);
      const idemKey = `trip_payout:${tripId}`;
      const ins = await db.prepare(
        `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
         VALUES (?, ?, 'commission', 'credit', ?, ?, ?, ?, 'أرباح رحلة مكتملة', 'settled', datetime('now'))`,
      )
        .bind(id("wt"), trip.captain_id, captainPayout, payoutPiastres, tripId, idemKey)
        .run();

      if (ins.meta && ins.meta.changes === 1) {
        await db.prepare(
          `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) + ?, wallet_updated_at = ? WHERE id = ?`,
        )
          .bind(captainPayout, payoutPiastres, nowIso(), trip.captain_id)
          .run();
      }
    }
  }
}
