import { Hono } from "hono";
import { z } from "zod";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";
import { logAudit } from "../lib/audit";

export const walletRoutes = new Hono<AppEnv>();

walletRoutes.use("*", authMiddleware);

const topUpSchema = z.object({
  amount: z.number().min(1).max(50000),
});

// GET /user/wallet — balance + last 50 transactions (real ledger)
walletRoutes.get("/user/wallet", async (c) => {
  const user = c.get("user");
  const userRow = await c.env.DB.prepare(
    `SELECT wallet_balance, wallet_updated_at FROM users WHERE id = ?`,
  )
    .bind(user.id)
    .first<{ wallet_balance: number; wallet_updated_at: string | null }>();
  const balance = userRow?.wallet_balance ?? 0;

  const tx = await c.env.DB.prepare(
    `SELECT id, type, direction, amount, currency, trip_id, payment_ref, note, status, created_at
     FROM wallet_transactions WHERE user_id = ? ORDER BY created_at DESC LIMIT 50`,
  )
    .bind(user.id)
    .all();

  return c.json({
    balance,
    currency: "EGP",
    updatedAt: userRow?.wallet_updated_at,
    transactions: tx.results ?? [],
  });
});

// GET /user/wallet/transactions?limit=50&offset=0 — paginated history
walletRoutes.get("/user/wallet/transactions", async (c) => {
  const user = c.get("user");
  const limit = Math.min(Number(c.req.query("limit") ?? 50), 200);
  const offset = Math.max(Number(c.req.query("offset") ?? 0), 0);
  const tx = await c.env.DB.prepare(
    `SELECT id, type, direction, amount, currency, trip_id, payment_ref, note, status, created_at
     FROM wallet_transactions WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?`,
  )
    .bind(user.id, limit, offset)
    .all();
  return c.json({ transactions: tx.results ?? [] });
});

// GET /captain/wallet — net earnings, scheduled next payout, commission total
walletRoutes.get("/captain/wallet", requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const earnings = await c.env.DB.prepare(
    `SELECT COALESCE(SUM(amount), 0) AS total_credits
     FROM wallet_transactions
     WHERE user_id = ? AND direction = 'credit' AND type IN ('commission','payout','adjustment')`,
  )
    .bind(user.id)
    .first<{ total_credits: number }>();
  const paidOut = await c.env.DB.prepare(
    `SELECT COALESCE(SUM(amount), 0) AS total_out
     FROM wallet_transactions WHERE user_id = ? AND direction = 'debit' AND type = 'payout'`,
  )
    .bind(user.id)
    .first<{ total_out: number }>();

  const net = (earnings?.total_credits ?? 0) - (paidOut?.total_out ?? 0);

  // Find trips completed today/week by this captain for earnings summary.
  const week = await c.env.DB.prepare(
    `SELECT COUNT(*) AS trips, COALESCE(SUM(commission), 0) AS commission
     FROM trips WHERE captain_id = ? AND status = 'completed'
       AND completed_at >= datetime('now','-7 days')`,
  )
    .bind(user.id)
    .first<{ trips: number; commission: number }>();

  return c.json({
    balance: net,
    currency: "EGP",
    weekTrips: week?.trips ?? 0,
    weekCommission: week?.commission ?? 0,
    nextPayoutWindow: "every Monday 10:00",
  });
});

// ---------------------------------------------------------------------------
// Payouts — gate item 4
//
// A payout request used to debit `users.wallet_balance` on the spot and record
// the money as a `wallet_transactions` row with `status = 'pending'`. Nothing in
// the product could ever action that row: there is no disbursement API and no
// bank-account storage, so the captain's money left their balance and stopped
// there. T03 (F-03-08), T04 (F-04-06) and T11 (F-11-04) each filed it.
//
// A request is now a durable row in `payout_requests` and moves no money. The
// balance changes exactly once, when an operator settles the request through
// `settlePayoutRequest()` below. That is the only debit path, and E14's console
// must call it rather than reproduce it — hand-rolled money movement is root R1,
// fifteen findings across six tracks.
// ---------------------------------------------------------------------------

export type PayoutMethod = "bank_transfer" | "vodafone_cash" | "instapay" | "fawry";
export type PayoutStatus = "requested" | "paid" | "rejected";

export interface PayoutRequestRow {
  id: string;
  user_id: string;
  amount: number;
  amount_piastres: number;
  currency: string;
  method: PayoutMethod;
  account_info: string;
  status: PayoutStatus;
  idempotency_key: string;
  wallet_transaction_id: string | null;
  decided_by: string | null;
  decided_at: string | null;
  decision_reason: string | null;
  created_at: string;
  updated_at: string;
}

export type PayoutDecisionResult =
  | { ok: true; request: PayoutRequestRow; walletTransactionId: string | null }
  | {
      ok: false;
      code: "NOT_FOUND" | "NOT_OPEN" | "INSUFFICIENT_BALANCE" | "REASON_REQUIRED";
      message: string;
      request: PayoutRequestRow | null;
    };

const PAYOUT_SELECT = `SELECT id, user_id, amount, amount_piastres, currency, method, account_info,
       status, idempotency_key, wallet_transaction_id, decided_by, decided_at,
       decision_reason, created_at, updated_at
  FROM payout_requests`;

/**
 * Read one payout request. E14's console uses this for the detail view.
 *
 * The queue itself is a plain query and does not need a helper — it is
 * `${PAYOUT_SELECT} WHERE status = 'requested' ORDER BY created_at` and the
 * `idx_payout_requests_queue` index covers it.
 */
export async function getPayoutRequest(
  db: D1Database,
  requestId: string,
): Promise<PayoutRequestRow | null> {
  return await db
    .prepare(`${PAYOUT_SELECT} WHERE id = ?`)
    .bind(requestId)
    .first<PayoutRequestRow>();
}

/**
 * Settle a payout request: move the money and mark it paid. **This is the only
 * code path in the product that may debit a captain's balance for a payout.**
 *
 * The three writes run as one `batch()`, which D1 executes as a single
 * transaction, and each is guarded so the set is self-consistent:
 *
 *  1. the ledger row is inserted with `INSERT OR IGNORE` on `idempotency_key`,
 *     which is the codebase's own money-movement idiom (`trips.ts:1019-1035`).
 *     The unique index `idx_wt_idem` turns that insert into a compare-and-swap:
 *     the second caller inserts nothing. The insert also carries the "request is
 *     still open" and "balance covers it" predicates, so a closed request or an
 *     insufficient balance produces no ledger row.
 *  2. the balance moves only where a row bearing *this call's* freshly generated
 *     transaction id exists — which only step 1 can have created.
 *  3. the request flips to `paid` under the same condition.
 *
 * A caller that loses the race writes nothing at all, rather than paying twice.
 */
export async function settlePayoutRequest(
  db: D1Database,
  opts: { requestId: string; actorId: string; reason: string },
): Promise<PayoutDecisionResult> {
  const reason = (opts.reason ?? "").trim();
  if (!reason) {
    return {
      ok: false,
      code: "REASON_REQUIRED",
      message: "سبب القرار مطلوب",
      request: null,
    };
  }

  const req = await getPayoutRequest(db, opts.requestId);
  if (!req) {
    return { ok: false, code: "NOT_FOUND", message: "طلب السحب غير موجود", request: null };
  }
  if (req.status !== "requested") {
    return {
      ok: false,
      code: "NOT_OPEN",
      message: "تم البت في هذا الطلب بالفعل",
      request: req,
    };
  }

  const txnId = id("wt");
  const idemKey = `payout_req:${req.id}`;
  const now = nowIso();
  const note = `تحويل مستحقات — ${req.method}`;

  await db.batch([
    db
      .prepare(
        `INSERT OR IGNORE INTO wallet_transactions
           (id, user_id, type, direction, amount, amount_piastres, idempotency_key, note, status, created_at)
         SELECT ?, pr.user_id, 'payout', 'debit', pr.amount, pr.amount_piastres, ?, ?, 'settled', ?
           FROM payout_requests pr
          WHERE pr.id = ?
            AND pr.status = 'requested'
            AND (SELECT COALESCE(wallet_balance, 0) FROM users WHERE id = pr.user_id) >= pr.amount`,
      )
      .bind(txnId, idemKey, note, now, req.id),
    db
      .prepare(
        `UPDATE users
            SET wallet_balance = COALESCE(wallet_balance, 0) - ?,
                wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?,
                wallet_updated_at = ?
          WHERE id = ?
            AND EXISTS (SELECT 1 FROM wallet_transactions WHERE id = ?)`,
      )
      .bind(req.amount, req.amount_piastres, now, req.user_id, txnId),
    db
      .prepare(
        `UPDATE payout_requests
            SET status = 'paid',
                wallet_transaction_id = ?,
                decided_by = ?,
                decided_at = ?,
                decision_reason = ?,
                updated_at = ?
          WHERE id = ?
            AND status = 'requested'
            AND EXISTS (SELECT 1 FROM wallet_transactions WHERE id = ?)`,
      )
      .bind(txnId, opts.actorId, now, reason, now, req.id, txnId),
  ]);

  const after = await getPayoutRequest(db, req.id);
  if (after?.status === "paid" && after.wallet_transaction_id === txnId) {
    return { ok: true, request: after, walletTransactionId: txnId };
  }
  if (after && after.status !== "requested") {
    // Another operator decided it between our read and our batch.
    return {
      ok: false,
      code: "NOT_OPEN",
      message: "تم البت في هذا الطلب بالفعل",
      request: after,
    };
  }
  // Still open ⇒ the only guard left that can have filtered the insert.
  return {
    ok: false,
    code: "INSUFFICIENT_BALANCE",
    message: "رصيد الكابتن لا يغطي المبلغ المطلوب",
    request: after,
  };
}

/**
 * Reject a payout request. Records who and why, and moves no money — the
 * balance was never debited, so there is nothing to return.
 */
export async function rejectPayoutRequest(
  db: D1Database,
  opts: { requestId: string; actorId: string; reason: string },
): Promise<PayoutDecisionResult> {
  const reason = (opts.reason ?? "").trim();
  if (!reason) {
    return {
      ok: false,
      code: "REASON_REQUIRED",
      message: "سبب الرفض مطلوب",
      request: null,
    };
  }

  const now = nowIso();
  const res = await db
    .prepare(
      `UPDATE payout_requests
          SET status = 'rejected',
              decided_by = ?,
              decided_at = ?,
              decision_reason = ?,
              updated_at = ?
        WHERE id = ? AND status = 'requested'`,
    )
    .bind(opts.actorId, now, reason, now, opts.requestId)
    .run();

  const after = await getPayoutRequest(db, opts.requestId);
  if (res.meta && res.meta.changes === 1 && after) {
    return { ok: true, request: after, walletTransactionId: null };
  }
  if (!after) {
    return { ok: false, code: "NOT_FOUND", message: "طلب السحب غير موجود", request: null };
  }
  return { ok: false, code: "NOT_OPEN", message: "تم البت في هذا الطلب بالفعل", request: after };
}

// POST /captain/wallet/payout — queue a payout request. Moves no money.
const payoutSchema = z.object({
  amount: z.number().min(1),
  method: z.enum(["bank_transfer", "vodafone_cash", "instapay", "fawry"]),
  account_info: z.string().min(3),
});
walletRoutes.post("/captain/wallet/payout", requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, payoutSchema);
  if (isResponse(body)) return body;

  // Available = recorded balance minus everything already queued. The
  // reservation is the point: without it, "stop debiting on request" would just
  // move the unbounded liability from the balance to the queue, and an operator
  // working the queue would pay the same money out several times over.
  const funds = await c.env.DB.prepare(
    `SELECT COALESCE(u.wallet_balance, 0) AS balance,
            COALESCE((SELECT SUM(pr.amount) FROM payout_requests pr
                       WHERE pr.user_id = u.id AND pr.status = 'requested'), 0) AS reserved
       FROM users u WHERE u.id = ?`,
  )
    .bind(user.id)
    .first<{ balance: number; reserved: number }>();

  const balance = funds?.balance ?? 0;
  const reserved = funds?.reserved ?? 0;
  const available = balance - reserved;
  if (available < body.amount) {
    return c.json(
      {
        error: "رصيد غير كافٍ للسحب",
        code: "INSUFFICIENT_BALANCE",
        available,
        pendingRequests: reserved,
      },
      400,
    );
  }

  // Idempotency. `Idempotency-Key` wins when the client sends one; otherwise the
  // request's own content is the key, so the double-tap that used to produce two
  // debits now produces one row. Both forms are namespaced by user id so two
  // captains cannot collide. The unique index is partial — scoped to open
  // requests — so an identical amount may legitimately be requested again once
  // this one has been paid or rejected.
  const headerKey = c.req.header("Idempotency-Key")?.trim();
  const idempotencyKey = headerKey
    ? `payout_req:${user.id}:hdr:${headerKey}`
    : `payout_req:${user.id}:${Math.round(body.amount * 100)}:${body.method}:${body.account_info}`;

  const requestId = id("pr");
  const now = nowIso();

  const ins = await c.env.DB.prepare(
    `INSERT OR IGNORE INTO payout_requests
       (id, user_id, amount, amount_piastres, currency, method, account_info,
        status, idempotency_key, created_at, updated_at)
     VALUES (?, ?, ?, CAST(ROUND(? * 100) AS INTEGER), 'EGP', ?, ?, 'requested', ?, ?, ?)`,
  )
    .bind(
      requestId,
      user.id,
      body.amount,
      body.amount,
      body.method,
      body.account_info,
      idempotencyKey,
      now,
      now,
    )
    .run();

  if (!ins.meta || ins.meta.changes !== 1) {
    // An identical request is already open. Return it rather than a duplicate.
    const existing = await c.env.DB.prepare(
      `${PAYOUT_SELECT} WHERE idempotency_key = ? AND status = 'requested'`,
    )
      .bind(idempotencyKey)
      .first<PayoutRequestRow>();
    if (existing) {
      return c.json({
        ok: true,
        payoutId: existing.id,
        status: existing.status,
        duplicate: true,
        message: "طلب السحب مسجّل بالفعل وقيد المراجعة",
      });
    }
    return c.json(
      { error: "تعذّر تسجيل طلب السحب، حاول مرة أخرى", code: "PAYOUT_REQUEST_CONFLICT" },
      409,
    );
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "wallet.payout.request",
    entityType: "payout_request",
    entityId: requestId,
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
    // The destination account lives on the row this entry points at; copying it
    // into the audit payload as well would duplicate it for no reader.
    payload: { amount: body.amount, method: body.method },
  });

  return c.json({
    ok: true,
    payoutId: requestId,
    status: "requested",
    duplicate: false,
    message: "تم تسجيل طلب السحب وسيُراجع قبل التحويل",
  });
});
