/**
 * The one way money moves.
 *
 * ## Why this file exists
 *
 * Root **R1** of the execution plan: the codebase already contains a correct
 * idiom for moving a balance, and uses it in two branches while three other
 * call sites hand-roll it wrong. Fifteen findings across five tracks are the
 * same mistake written five times. This file writes it **once**, and
 * `lib/settlement.ts` is the first caller.
 *
 * ## The idiom, and why the order matters
 *
 * A balance move is two writes that must not come apart:
 *
 *   1. `INSERT OR IGNORE` the `wallet_transactions` row. `idx_wt_idem`
 *      (`migrations/0005:5`) is a **unique** index on `idempotency_key`, so the
 *      insert is the lock: it succeeds exactly once per key, ever.
 *   2. `UPDATE users` — guarded by `EXISTS (SELECT 1 FROM wallet_transactions
 *      WHERE id = ?)` against the id generated for *this* call. On a retry the
 *      insert is ignored, that id never appears, and the balance does not move.
 *
 * Both statements go through one `db.batch([...])`, which D1 runs as a single
 * transaction, so a crash between them cannot leave a ledger row without its
 * balance move.
 *
 * **The order is the whole point.** The rider debit this file replaces did it
 * backwards — `UPDATE` first, then `INSERT OR IGNORE` — which means a retried
 * completion debited the rider a second time and *then* silently discarded the
 * duplicate ledger row. The comment above it claimed the opposite:
 * *"All wallet moves are keyed by idempotency_key … so a retried completion
 * cannot double-apply a balance change."* It could, and only for that branch.
 *
 * ## Floors
 *
 * A debit defaults to `floor: 0` — **no debit may drive a wallet negative.**
 * The floor is enforced inside the `INSERT`'s `WHERE`, not in a prior read, so
 * there is no window between checking the balance and taking it. The cash
 * commission debit was the one debit in the codebase with no floor at all
 * (F-03-11 / F-04-12, promoted to G1); under the cash-only launch shape it is
 * also the only live money path.
 *
 * ## Integer money
 *
 * `migrations/0005` added `*_piastres` integer columns for
 * "zero-floating-point financial accounting". The floor comparison is done in
 * **piastres**, as integers, so a balance of `10.00` cannot fail a `>= 10`
 * check because it is stored as `9.999999999999998`. The REAL column is kept in
 * step and rounded to 2dp on every write.
 */

import { id, nowIso } from "./utils";

/** `wallet_transactions.type` — the CHECK constraint from `migrations/0003:30`. */
export type MoneyType =
  | "topup"
  | "trip_payment"
  | "refund"
  | "commission"
  | "payout"
  | "adjustment"
  | "promo_credit";

export type MoneyDirection = "credit" | "debit";

export type MoveMoneyInput = {
  db: D1Database;
  /** `users.id` whose wallet moves. */
  userId: string;
  type: MoneyType;
  direction: MoneyDirection;
  /** Positive amount in EGP. A zero or negative amount is refused, not clamped. */
  amount: number;
  /**
   * The uniqueness key. One key = one balance move, forever. Collides against
   * `idx_wt_idem`, which is what makes this safe to retry.
   */
  idempotencyKey: string;
  note?: string | null;
  tripId?: string | null;
  paymentRef?: string | null;
  /**
   * Debits only. The balance may not fall below this many EGP.
   *
   * Defaults to `0`. Pass `null` to disable the floor — nothing in this
   * codebase should, and a caller that does needs to say why on its PR.
   */
  floor?: number | null;
};

export type MoveMoneyReason =
  /** The key was already used. The balance moved on the first call, not this one. */
  | "duplicate"
  /** The floor refused it, or the user row does not exist. Nothing was written. */
  | "insufficient_funds"
  /** `amount <= 0`, or not a finite number. Nothing was written. */
  | "non_positive_amount";

export type MoveMoneyResult = {
  /** True only when **this** call moved the balance. Retries return false. */
  moved: boolean;
  reason?: MoveMoneyReason;
  /** The id generated for this attempt, whether or not it landed. */
  transactionId: string;
  amount: number;
  amountPiastres: number;
};

/** EGP → piastres, the only rounding site. */
export function toPiastres(egp: number): number {
  return Math.round(egp * 100);
}

/**
 * Move one balance, once.
 *
 * Never throws for an expected refusal — an insufficient balance, a duplicate
 * key and a non-positive amount all come back as `moved: false` with a
 * `reason`. D1 transport failures still throw; a caller that must not fail the
 * request around them should catch.
 */
export async function moveMoney({
  db,
  userId,
  type,
  direction,
  amount,
  idempotencyKey,
  note = null,
  tripId = null,
  paymentRef = null,
  floor = 0,
}: MoveMoneyInput): Promise<MoveMoneyResult> {
  const amountPiastres = toPiastres(amount);
  const transactionId = id("wt");

  if (!Number.isFinite(amount) || amountPiastres <= 0) {
    return {
      moved: false,
      reason: "non_positive_amount",
      transactionId,
      amount,
      amountPiastres,
    };
  }

  const now = nowIso();

  // Balance as an integer, falling back to the REAL column for any row the
  // 0005 backfill did not reach.
  const balancePiastres = `COALESCE(u.wallet_balance_piastres, CAST(ROUND(COALESCE(u.wallet_balance, 0) * 100) AS INTEGER))`;

  const applyFloor = direction === "debit" && floor !== null && floor !== undefined;
  const guard = applyFloor ? ` AND ${balancePiastres} - ? >= ?` : "";

  // 1. The lock. `INSERT … SELECT FROM users` also refuses a move against a
  //    user that does not exist, which the previous `INSERT … VALUES` did not.
  const insert = db
    .prepare(
      `INSERT OR IGNORE INTO wallet_transactions
         (id, user_id, type, direction, amount, amount_piastres, trip_id, payment_ref, idempotency_key, note, status, created_at)
       SELECT ?, u.id, ?, ?, ?, ?, ?, ?, ?, ?, 'settled', ?
         FROM users u
        WHERE u.id = ?${guard}`,
    )
    .bind(
      ...[
        transactionId,
        type,
        direction,
        amount,
        amountPiastres,
        tripId,
        paymentRef,
        idempotencyKey,
        note,
        now,
        userId,
      ],
      ...(applyFloor ? [amountPiastres, toPiastres(floor as number)] : []),
    );

  // 2. The balance, gated on the lock this call took.
  const sign = direction === "credit" ? "+" : "-";
  const update = db
    .prepare(
      `UPDATE users
          SET wallet_balance = ROUND(COALESCE(wallet_balance, 0) ${sign} ?, 2),
              wallet_balance_piastres = COALESCE(wallet_balance_piastres, CAST(ROUND(COALESCE(wallet_balance, 0) * 100) AS INTEGER)) ${sign} ?,
              wallet_updated_at = ?
        WHERE id = ?
          AND EXISTS (SELECT 1 FROM wallet_transactions WHERE id = ?)`,
    )
    .bind(amount, amountPiastres, now, userId, transactionId);

  const results = await db.batch([insert, update]);
  const moved = (results[1]?.meta?.changes ?? 0) === 1;

  if (moved) {
    return { moved: true, transactionId, amount, amountPiastres };
  }

  // Only on the failure path: separate "already done" from "could not do it".
  const existing = await db
    .prepare(`SELECT id FROM wallet_transactions WHERE idempotency_key = ?`)
    .bind(idempotencyKey)
    .first<{ id: string }>();

  return {
    moved: false,
    reason: existing && existing.id !== transactionId ? "duplicate" : "insufficient_funds",
    transactionId,
    amount,
    amountPiastres,
  };
}

/**
 * Record an attempted move that did **not** happen, for the ledger's sake.
 *
 * Writes a `status = 'failed'` row and touches no balance. This exists so the
 * "rider could not pay" case keeps leaving the trace it left before, while the
 * rule that *every balance-moving statement goes through `moveMoney`* stays
 * literally true — this function moves nothing.
 *
 * Idempotent on its own key, so a retried settlement does not stack failures.
 */
export async function recordFailedMove({
  db,
  userId,
  type,
  direction,
  amount,
  idempotencyKey,
  note = null,
  tripId = null,
}: Omit<MoveMoneyInput, "floor" | "paymentRef">): Promise<{ recorded: boolean; transactionId: string }> {
  const transactionId = id("wt");

  const res = await db
    .prepare(
      `INSERT OR IGNORE INTO wallet_transactions
         (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'failed', ?)`,
    )
    .bind(
      transactionId,
      userId,
      type,
      direction,
      amount,
      toPiastres(amount),
      tripId,
      idempotencyKey,
      note,
      nowIso(),
    )
    .run();

  return { recorded: (res.meta?.changes ?? 0) === 1, transactionId };
}
