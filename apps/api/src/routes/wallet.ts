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

// POST /captain/wallet/payout — request a payout (admin reviews/pays)
const payoutSchema = z.object({
  amount: z.number().min(1),
  method: z.enum(["bank_transfer", "vodafone_cash", "instapay", "fawry"]),
  account_info: z.string().min(3),
});
walletRoutes.post("/captain/wallet/payout", requireRole("captain", "admin"), async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, payoutSchema);
  if (isResponse(body)) return body;

  // Check available balance
  const balance = await c.env.DB.prepare(
    `SELECT COALESCE(wallet_balance, 0) AS b FROM users WHERE id = ?`,
  )
    .bind(user.id)
    .first<{ b: number }>();
  if ((balance?.b ?? 0) < body.amount) {
    return c.json({ error: "رصيد غير كافٍ للسحب", code: "INSUFFICIENT_BALANCE" }, 400);
  }

  const updateRes = await c.env.DB.prepare(
    `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
  )
    .bind(body.amount, nowIso(), user.id, body.amount)
    .run();

  if (updateRes.meta && updateRes.meta.changes === 0) {
    return c.json({ error: "رصيد غير كافٍ للسحب أو تم تغيير الرصيد بالتزامن", code: "INSUFFICIENT_BALANCE" }, 409);
  }

  const txnId = id("wt");
  await c.env.DB.prepare(
    `INSERT INTO wallet_transactions
      (id, user_id, type, direction, amount, amount_piastres, note, status, created_at)
     VALUES (?, ?, 'payout', 'debit', ?, ?, ?, 'pending', datetime('now'))`,
  )
    .bind(txnId, user.id, body.amount, Math.round(body.amount * 100), `${body.method}:${body.account_info}`)
    .run();

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "wallet.payout.request",
    entityType: "wallet_transaction",
    entityId: txnId,
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
    payload: JSON.stringify(body),
  });

  return c.json({ ok: true, payoutId: txnId, message: "تم تقديم طلب السحب وسيُعالج خلال 24 ساعة" });
});