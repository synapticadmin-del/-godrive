/**
 * Paymob (accept.paymob.com) integration — Egyptian market standard.
 *
 * Two halves:
 *   1) Paymob Hassadin / Intention API for creating a payment intention
 *      that returns a client secret + iframe URL.
 *   2) Webhook callback verification via HMAC-SHA512 using the Merchant's
 *      "HMAC Secret" (from Paymob dashboard → Security → HMAC Signature).
 *
 * Required secrets (set via `wrangler secret put`):
 *   PAYMOB_API_KEY    — Accept API key
 *   PAYMOB_HMAC       — HMAC secret for webhook signature verification
 *   PAYMOB_IFRAME_ID  — the iframe ID from Paymob dashboard
 *
 * In dev (no secrets) endpoints return a stub payment so the flow keeps working.
 * The HMAC verification below rejects unsigned webhooks in prod with 401.
 */
import { id, nowIso } from "./utils";

export const PAYMOB_INTEGRATION_ID_CARD = 3990172; // default card integration; override via env

export async function paymobAuthToken(env: Env): Promise<string> {
  const apiKey = env.PAYMOB_API_KEY;
  if (!apiKey) throw new Error("PAYMOB_API_KEY not set");
  const res = await fetch("https://accept.paymob.com/api/auth/tokens", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: apiKey }),
  });
  const data = (await res.json()) as { token?: string; detail?: string };
  if (!res.ok || !data.token) throw new Error(data.detail ?? "paymob_auth_failed");
  return data.token;
}

export async function paymobOrder(env: Env, authToken: string, amountCents: number, merchantId: string): Promise<string> {
  const res = await fetch("https://accept.paymob.com/api/ecommerce/orders", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      auth_token: authToken,
      delivery_needed: "false",
      amount_cents: amountCents,
      currency: "EGP",
      merchant_order_id: merchantId,
      items: [],
    }),
  });
  const data = (await res.json()) as { id?: number; success?: boolean; detail?: string };
  if (!res.ok || !data.id) throw new Error(data.detail ?? "paymob_order_failed");
  return String(data.id);
}

export async function paymobPaymentKey(
  env: Env,
  params: {
    authToken: string;
    orderId: string;
    amountCents: number;
    integrationId: number;
    billingData: PaymobBillingData;
  },
): Promise<string> {
  const res = await fetch("https://accept.paymob.com/api/acceptance/payment_keys", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      auth_token: params.authToken,
      amount_cents: params.amountCents,
      expiration: 3600,
      order_id: params.orderId,
      billing_data: params.billingData,
      currency: "EGP",
      integration_id: params.integrationId,
      lock_order_when_paid: "true",
    }),
  });
  const data = (await res.json()) as { token?: string; detail?: string };
  if (!res.ok || !data.token) throw new Error(data.detail ?? "paymob_payment_key_failed");
  return data.token;
}

export interface PaymobBillingData {
  apartment?: string;
  email: string;
  floor?: string;
  first_name: string;
  last_name: string;
  street?: string;
  building?: string;
  phone_number: string;
  shipping_method?: string;
  postal_code?: string;
  city?: string;
  country?: string;
  state?: string;
}

/**
 * Create a full Paymob intention that yields an iframe URL.
 * Falls back to a deterministic stub URL if secrets aren't set (dev mode).
 */
export async function createPaymobIntention(args: {
  env: Env;
  amountEgp: number;
  merchantRef: string;
  billing: PaymobBillingData;
  integrationId?: number;
}): Promise<{
  iframeUrl: string;
  paymentKey: string;
  orderId: string;
  stubbed: boolean;
}> {
  const { env, amountEgp, merchantRef, billing, integrationId } = args;
  const apiKey = env.PAYMOB_API_KEY;
  const iframeId = env.PAYMOB_IFRAME_ID;
  if (!apiKey || !iframeId) {
    // Dev stub — keeps end-to-end flow intact without keys.
    const stubKey = `stub_pk_${id()}`;
    const stubOrder = `PM_${merchantRef}_${Date.now().toString(36)}`;
    return {
      iframeUrl: `https://accept.paymob.com/api/acceptance/iframes/${iframeId ?? "stub"}?payment_token=${stubKey}`,
      paymentKey: stubKey,
      orderId: stubOrder,
      stubbed: true,
    };
  }
  const authToken = await paymobAuthToken(env);
  const amountCents = Math.round(amountEgp * 100);
  const orderId = await paymobOrder(env, authToken, amountCents, merchantRef);
  const paymentKey = await paymobPaymentKey(env, {
    authToken,
    orderId,
    amountCents,
    integrationId: integrationId ?? PAYMOB_INTEGRATION_ID_CARD,
    billingData: billing,
  });
  return {
    iframeUrl: `https://accept.paymob.com/api/acceptance/iframes/${iframeId}?payment_token=${paymentKey}`,
    paymentKey,
    orderId,
    stubbed: false,
  };
}

/**
 * Verify a Paymob webhook HMAC signature.
 *
 * Paymob signs callbacks with an HMAC-SHA512 over the concatenated values of
 * specific fields in a fixed order ("amount_cents", "created_at",
 * "currency", "error_occured", "has_parent_transaction", "id",
 * "integration_id", "is_hmac_attributed_transaction", "is_refunded",
 * "is_standalone_payment", "is_voided", "order.id" or "order",
 * "owner", "pending", "source_data.pan", "source_data.sub_type",
 * "source_data.type", "success", "currency_ops.transaction_count",
 * "currency_ops.total_cents_capture", "currency_ops.total_cents_refund").
 *
 * The server passes the HMAC in the "hmac" query string param OR body hmac.
 * We verify by recomputing over the smaller set included in the body and
 * require the secret to be present in prod.
 */
const HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
];

export async function computePaymobHmacAsync(body: Record<string, unknown>, secret: string): Promise<string> {
  const parts: string[] = [];
  for (const path of HMAC_FIELDS) {
    const value = readPath(body, path);
    parts.push(String(value ?? ""));
  }
  const concatenated = parts.join("");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(concatenated));
  const bytes = new Uint8Array(sig);
  let hex = "";
  for (const b of bytes) hex += b.toString(16).padStart(2, "0");
  return hex;
}

function readPath(obj: unknown, path: string): unknown {
  return path.split(".").reduce<unknown>((acc, key) => {
    if (acc && typeof acc === "object" && key in (acc as Record<string, unknown>)) {
      return (acc as Record<string, unknown>)[key];
    }
    // Paymob sometimes nests a flat order object; for "order" we want
    // the "order.id" value when present, falling back to "order".
    return acc;
  }, obj);
}

export async function verifyPaymobHmacAsync(args: {
  body: Record<string, unknown>;
  providedHmac: string | undefined;
  env: Env;
}): Promise<{ ok: boolean; reason?: string }> {
  const { body, providedHmac, env } = args;
  const secret = env.PAYMOB_HMAC;
  if (!secret) return { ok: false, reason: "PAYMOB_HMAC not set" };
  if (!providedHmac) return { ok: false, reason: "missing hmac" };
  const computed = await computePaymobHmacAsync(body, secret);
  if (timingSafeEqual(providedHmac.toLowerCase(), computed.toLowerCase())) {
    return { ok: true };
  }
  return { ok: false, reason: "hmac_mismatch" };
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}