import { Hono } from "hono";
import { z } from "zod";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";
import { logAudit } from "../lib/audit";
import { createPaymobIntention, verifyPaymobHmacAsync, type PaymobBillingData } from "../lib/paymob";
import { pushToUser } from "../lib/notifications";

export const paymentRoutes = new Hono<AppEnv>();

const intentionSchema = z.object({
  amount: z.number().min(1),
  currency: z.string().default("EGP"),
  paymentMethod: z.enum(["card", "wallet", "cash"]).default("card"),
  purpose: z.enum(["wallet_topup", "trip_payment", "intercity_booking"]).default("wallet_topup"),
  tripId: z.string().optional(),
});

// POST /payments/paymob/intention — create a Paymob payment intention
// that returns an iframe URL the client opens in a WebView. HMAC verified
// in the webhook credits the wallet / marks trip paid.
paymentRoutes.post("/paymob/intention", authMiddleware, async (c) => {
  const user = c.get("user");
  const body = await parseBody(c, intentionSchema);
  if (isResponse(body)) return body;

  const merchantRef = `${user.id.slice(0, 8)}_${Date.now().toString(36)}`;
  const billing: PaymobBillingData = {
    email: (user as { email?: string }).email ?? "guest@synapticstudio.tech",
    first_name: (user as { name?: string }).name?.split(" ")[0] ?? "Rider",
    last_name: (user as { name?: string }).name?.split(" ").slice(1).join(" ") ?? "Synaptic",
    phone_number: "01000000000",
    apartment: "NA",
    floor: "NA",
    street: "NA",
    building: "NA",
    city: "Cairo",
    country: "EG",
    state: "Cairo",
  };

  try {
    const intention = await createPaymobIntention({
      env: c.env,
      amountEgp: body.amount,
      merchantRef,
      billing,
    });

    // Record payment_method entry for tracking; webhook will mark settled.
    // (Legacy bookkeeping — payment_intentions below is now the source of truth.)
    const paymentId = id("pay");
    await c.env.DB.prepare(
      `INSERT INTO payment_methods (id, user_id, type, provider, token, last4, created_at)
       VALUES (?, ?, ?, 'paymob', ?, ?, ?)`,
    )
      .bind(paymentId, user.id, body.paymentMethod, intention.orderId, intention.stubbed ? "0000" : "", nowIso())
      .run();

    // Source-of-truth record: the webhook verifies amount + purpose against
    // this row before crediting anything (migration 0011).
    await c.env.DB.prepare(
      `INSERT INTO payment_intentions (id, user_id, order_id, amount_piastres, currency, purpose, trip_id, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`,
    )
      .bind(
        id("pint"),
        user.id,
        intention.orderId,
        Math.round(body.amount * 100),
        body.currency,
        body.purpose,
        body.tripId ?? null,
        nowIso(),
      )
      .run();

    return c.json({
      ok: true,
      paymentId,
      orderId: intention.orderId,
      amount: body.amount,
      currency: body.currency,
      iframeUrl: intention.iframeUrl,
      clientSecret: intention.paymentKey,
      stubbed: intention.stubbed,
      purpose: body.purpose,
    });
  } catch (e) {
    return c.json({ error: (e as Error).message, code: "PAYMOB_INTENTION_FAILED" }, 502);
  }
});

// POST /payments/paymob/webhook — Paymob callback. HMAC-SHA512 verified.
// Returns 200 immediately once accepted (Paymob retries on non-2xx).
paymentRoutes.post("/paymob/webhook", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
  const obj = (body?.obj ?? body) as Record<string, unknown> | undefined;
  if (!obj) return c.json({ status: "ignored", reason: "empty" });

  // Paymob passes hmac as ?hmac= query OR inside body hmac.
  const providedHmac = (c.req.query("hmac") ?? (body.hmac as string | undefined)) ?? undefined;
  const verify = await verifyPaymobHmacAsync({ body: obj as Record<string, unknown>, providedHmac, env: c.env });
  if (!verify.ok) {
    await logAudit(c.env.DB, {
      actorId: "paymob",
      action: "payment.webhook.rejected",
      ip: c.req.header("cf-connecting-ip"),
      userAgent: c.req.header("user-agent"),
      payload: JSON.stringify({ reason: verify.reason, orderId: obj?.order }),
    });
    return c.json({ status: "rejected", reason: verify.reason }, 401);
  }

  const successRaw = obj?.success;
  const successBool = successRaw === true || successRaw === "true";
  const orderId = (obj?.order as { id?: string | number } | string | undefined);
  const orderIdStr =
    typeof orderId === "string" ? orderId : (orderId as { id?: string })?.id?.toString() ?? String(obj?.id ?? "");
  const txnId = String(obj?.id ?? "");
  const amountCents = Number(obj?.amount_cents ?? 0);

  if (!txnId) {
    return c.json({ status: "ignored", reason: "missing_txn_id" }, 200);
  }

  // Look up the source-of-truth intention stored at /paymob/intention time.
  // Fall back to the legacy payment_methods row for intentions created before
  // migration 0011 was applied (they never got a payment_intentions row).
  const intention = await c.env.DB.prepare(
    `SELECT id, user_id, order_id, amount_piastres, purpose, trip_id, status FROM payment_intentions WHERE order_id = ? LIMIT 1`,
  )
    .bind(orderIdStr)
    .first<{
      id: string;
      user_id: string;
      order_id: string;
      amount_piastres: number;
      purpose: string;
      trip_id: string | null;
      status: string;
    }>();

  if (intention) {
    // Amount tamper check: what Paymob actually charged must equal what the
    // user asked to pay. On mismatch, refuse to credit anything.
    if (amountCents !== intention.amount_piastres) {
      await logAudit(c.env.DB, {
        actorId: "paymob",
        action: "payment.webhook.amount_mismatch",
        entityType: "payment_intention",
        entityId: intention.id,
        ip: c.req.header("cf-connecting-ip"),
        userAgent: c.req.header("user-agent"),
        payload: JSON.stringify({
          orderId: orderIdStr,
          expected: intention.amount_piastres,
          received: amountCents,
        }),
      });
      return c.json({ status: "rejected", reason: "amount_mismatch" }, 400);
    }

    // Idempotency at the intention level: Paymob retries must not double-credit.
    if (intention.status === "settled") {
      return c.json({ status: "duplicate_ignored" }, 200);
    }

    const amountEgp = amountCents / 100;

    if (successBool) {
      if (intention.purpose === "wallet_topup") {
        const idempotencyKey = `paymob:${orderIdStr}:${txnId}`;
        await c.env.DB.prepare(
          `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, idempotency_key, status, created_at)
           VALUES (?, ?, 'topup', 'credit', ?, ?, ?, ?, 'settled', datetime('now'))`,
        )
          .bind(id("wt"), intention.user_id, amountEgp, amountCents, orderIdStr, idempotencyKey)
          .run();

        await c.env.DB.prepare(
          `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) + ?, wallet_updated_at = ? WHERE id = ?`,
        )
          .bind(amountEgp, amountCents, nowIso(), intention.user_id)
          .run();

        // Notify the user their top-up succeeded.
        await pushToUser({
          env: c.env,
          userId: intention.user_id,
          topic: "wallet.topup.success",
          title: "تم شحن المحفظة",
          body: `تم إضافة ${amountEgp} ج.م إلى محفظتك.`,
          data: { amount: String(amountEgp), ref: orderIdStr },
        });
      } else if (intention.purpose === "trip_payment") {
        // Mark the trip paid; record an audit wallet_transactions row.
        // No wallet credit — the money went to the trip fare.
        if (intention.trip_id) {
          await c.env.DB.prepare(
            `UPDATE trips SET payment_status = 'paid' WHERE id = ?`,
          )
            .bind(intention.trip_id)
            .run();
        }
        await c.env.DB.prepare(
          `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, status, created_at)
           VALUES (?, ?, 'trip_payment', 'debit', ?, ?, ?, 'settled', datetime('now'))`,
        )
          .bind(id("wt"), intention.user_id, amountEgp, amountCents, orderIdStr)
          .run();
      } else if (intention.purpose === "intercity_booking") {
        // Audit row only; seat accounting lives in intercity_bookings.
        await c.env.DB.prepare(
          `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, status, created_at)
           VALUES (?, ?, 'intercity_booking', 'debit', ?, ?, ?, 'settled', datetime('now'))`,
        )
          .bind(id("wt"), intention.user_id, amountEgp, amountCents, orderIdStr)
          .run();
      }

      await c.env.DB.prepare(
        `UPDATE payment_intentions SET status = 'settled', settled_at = ? WHERE id = ?`,
      )
        .bind(nowIso(), intention.id)
        .run();
    } else {
      await c.env.DB.prepare(
        `UPDATE payment_intentions SET status = 'failed' WHERE id = ?`,
      )
        .bind(intention.id)
        .run();
      await c.env.DB.prepare(
        `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, payment_ref, status, created_at)
         VALUES (?, ?, 'topup', 'credit', ?, ?, 'failed', datetime('now'))`,
      )
        .bind(id("wt"), intention.user_id, amountEgp, orderIdStr)
        .run();
      await pushToUser({
        env: c.env,
        userId: intention.user_id,
        topic: "wallet.topup.failed",
        title: "فشل الشحن",
        body: "تعذّر إتمام عملية الشحن. جرّب مرة أخرى.",
      });
    }
  } else {
    // Legacy fallback path — pre-migration intentions only exist as
    // payment_methods rows keyed by the Paymob order id.
    const pmRow = await c.env.DB.prepare(
      `SELECT id, user_id, token FROM payment_methods WHERE token = ? ORDER BY created_at DESC LIMIT 1`,
    )
      .bind(orderIdStr)
      .first<{ id: string; user_id: string; token: string }>();

    if (successBool && pmRow) {
      const amountEgp = amountCents / 100;
      const idempotencyKey = `paymob:${orderIdStr}:${txnId}`;

      const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, idempotency_key, status, created_at)
         VALUES (?, ?, 'topup', 'credit', ?, ?, ?, ?, 'settled', datetime('now'))`,
      )
        .bind(id("wt"), pmRow.user_id, amountEgp, amountCents, orderIdStr, idempotencyKey)
        .run();

      if (ins.meta && ins.meta.changes === 0) {
        return c.json({ status: "duplicate_ignored" }, 200);
      }

      await c.env.DB.prepare(
        `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) + ?, wallet_updated_at = ? WHERE id = ?`,
      )
        .bind(amountEgp, amountCents, nowIso(), pmRow.user_id)
        .run();

      // Notify the user their top-up succeeded.
      await pushToUser({
        env: c.env,
        userId: pmRow.user_id,
        topic: "wallet.topup.success",
        title: "تم شحن المحفظة",
        body: `تم إضافة ${amountEgp} ج.م إلى محفظتك.`,
        data: { amount: String(amountEgp), ref: orderIdStr },
      });
    } else if (!successBool && pmRow) {
      await c.env.DB.prepare(
        `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, payment_ref, status, created_at)
         VALUES (?, ?, 'topup', 'credit', ?, ?, 'failed', datetime('now'))`,
      )
        .bind(id("wt"), pmRow.user_id, amountCents / 100, orderIdStr)
        .run();
      await pushToUser({
        env: c.env,
        userId: pmRow.user_id,
        topic: "wallet.topup.failed",
        title: "فشل الشحن",
        body: "تعذّر إتمام عملية الشحن. جرّب مرة أخرى.",
      });
    }
  }

  await logAudit(c.env.DB, {
    actorId: "paymob",
    action: "payment.webhook.verified",
    ip: c.req.header("cf-connecting-ip"),
    userAgent: c.req.header("user-agent"),
    payload: JSON.stringify({ success: successBool, orderId: orderIdStr, amountCents }),
  });

  return c.json({ status: "verified", success: successBool, orderId: orderIdStr });
});
