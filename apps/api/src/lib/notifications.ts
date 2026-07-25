/**
 * Notifications library for Synaptic Go.
 *
 * Three channels, each with a graceful fallback when secrets are absent so the
 * API keeps working in dev (returns devCode / logs):
 *   1. WhatsApp Business API (OTP + trip push)   — Meta Cloud API or 360dialog
 *   2. Email OTP                                — Resend (or Brevo compatible)
 *   3. Firebase Cloud Messaging HTTP v1         — service-account JWT sign
 *
 * Secrets (set via `wrangler secret put`):
 *   WHATSAPP_TOKEN            — Meta/360dialog access token
 *   WHATSAPP_PHONE_NUMBER_ID  — Meta phone number id
 *   WHATSAPP_TEMPLATE_LANG    — e.g. "ar" (defaults to en)
 *   EMAIL_RESEND_API_KEY      — Resend API key
 *   EMAIL_FROM                — verified sender (Synaptic Go <no-reply@...>)
 *   FCM_CLIENT_EMAIL          — service account client email
 *   FCM_PRIVATE_KEY           — service account private key (PEM, with \n)
 *   FCM_PROJECT_ID            — Firebase project id (e.g. "delivery-bf0d6")
 *
 * Storage in D1: notification_log (per-channel delivery audit).
 */
import { id, nowIso } from "./utils";

type NotificationChannel = "whatsapp" | "email" | "fcm" | "in_app";
type NotificationStatus = "queued" | "sent" | "failed" | "dropped";

interface NotificationContext {
  DB: D1Database;
  userId: string;
  topic: string;
  channel: NotificationChannel;
  payload?: Record<string, unknown>;
}

async function logNotification(
  ctx: NotificationContext,
  status: NotificationStatus,
  providerRef?: string,
  lastError?: string,
  attempts = 1,
): Promise<void> {
  try {
    await ctx.DB.prepare(
      `INSERT INTO notification_log
        (id, user_id, channel, topic, payload, status, provider_ref, attempts, last_error, created_at, sent_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        id("ntf"),
        ctx.userId,
        ctx.channel,
        ctx.topic,
        ctx.payload ? JSON.stringify(ctx.payload) : null,
        status,
        providerRef ?? null,
        attempts,
        lastError ?? null,
        nowIso(),
        status === "sent" ? nowIso() : null,
      )
      .run();
  } catch {
    /* notification logging is best-effort */
  }
}

/* ------------------------------------------------------------------ */
/* 1) WhatsApp OTP — Meta Cloud API / 360dialog (same payload shape)  */
/* ------------------------------------------------------------------ */

export async function sendWhatsAppOtp(args: {
  env: Env;
  phone: string;           // e.g. +2010xxxxxxxx
  code: string;
  userId: string;
}): Promise<{ ok: boolean; dev?: string; error?: string }> {
  const { env, phone, code, userId } = args;
  const token = env.WHATSAPP_TOKEN;
  const phoneNumberId = env.WHATSAPP_PHONE_NUMBER_ID;

  // Fallback: no credentials → behave like dev mode (return code) so the flow
  // keeps working. In prod, set secrets via `wrangler secret put`.
  if (!token || !phoneNumberId) {
    await logNotification(
      { DB: env.DB, userId, channel: "whatsapp", topic: "auth.otp" },
      "dropped",
      undefined,
      "WHATSAPP_TOKEN/PHONE_NUMBER_ID not set",
    );
    return { ok: false, dev: code, error: "whatsapp_not_configured" };
  }

  const lang = env.WHATSAPP_TEMPLATE_LANG || "ar";
  // Use a template named "synaptic_go_otp" with one body param {{1}} = code
  const body = {
    messaging_product: "whatsapp",
    to: phone.replace(/\s+/g, ""),
    type: "template",
    template: {
      namespace: "synaptic_go",
      language: { code: lang },
      name: "synaptic_go_otp",
      components: [
        {
          type: "body",
          parameters: [{ type: "text", text: code }],
        },
      ],
    },
  };

  try {
    const res = await fetch(
      `https://graph.facebook.com/v20.0/${phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      },
    );
    const data = (await res.json()) as { messages?: { id: string }[]; error?: { message: string } };
    if (!res.ok) {
      await logNotification(
        { DB: env.DB, userId, channel: "whatsapp", topic: "auth.otp" },
        "failed",
        undefined,
        data.error?.message ?? `HTTP ${res.status}`,
      );
      return { ok: false, error: data.error?.message ?? `HTTP ${res.status}` };
    }
    const ref = data.messages?.[0]?.id;
    await logNotification(
      { DB: env.DB, userId, channel: "whatsapp", topic: "auth.otp" },
      "sent",
      ref,
    );
    return { ok: true };
  } catch (e) {
    await logNotification(
      { DB: env.DB, userId, channel: "whatsapp", topic: "auth.otp" },
      "failed",
      undefined,
      (e as Error).message,
    );
    return { ok: false, error: (e as Error).message };
  }
}

/* ------------------------------------------------------------------ */
/* 2) Email OTP — Resend (or any Brevo-compatible POST /emails)       */
/* ------------------------------------------------------------------ */

export async function sendEmailOtp(args: {
  env: Env;
  email: string;
  code: string;
  userId: string;
}): Promise<{ ok: boolean; error?: string }> {
  const { env, email, code, userId } = args;
  const apiKey = env.EMAIL_RESEND_API_KEY;
  if (!apiKey) {
    await logNotification(
      { DB: env.DB, userId, channel: "email", topic: "auth.otp" },
      "dropped",
      undefined,
      "EMAIL_RESEND_API_KEY not set",
    );
    return { ok: false, error: "email_not_configured" };
  }
  const from = env.EMAIL_FROM || "Synaptic Go <no-reply@synapticstudio.tech>";
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: email,
        subject: "رمز الدخول — Synaptic Go",
        html: `<p>رمز التحقق الخاص بك هو:</p><h2>${code}</h2><p>صالح لمدة 10 دقائق.</p>`,
      }),
    });
    const data = (await res.json()) as { id?: string; error?: { message: string } };
    if (!res.ok) {
      await logNotification(
        { DB: env.DB, userId, channel: "email", topic: "auth.otp" },
        "failed",
        undefined,
        data.error?.message ?? `HTTP ${res.status}`,
      );
      return { ok: false, error: data.error?.message ?? `HTTP ${res.status}` };
    }
    await logNotification(
      { DB: env.DB, userId, channel: "email", topic: "auth.otp" },
      "sent",
      data.id,
    );
    return { ok: true };
  } catch (e) {
    await logNotification(
      { DB: env.DB, userId, channel: "email", topic: "auth.otp" },
      "failed",
      undefined,
      (e as Error).message,
    );
    return { ok: false, error: (e as Error).message };
  }
}

/* ------------------------------------------------------------------ */
/* 3) FCM HTTP v1 — sign a service-account JWT and POST to the token   */
/* ------------------------------------------------------------------ */

// Cache: 50-min access token (Google access tokens last 1h).
let cachedFcmToken: { token: string; exp: number } | null = null;

async function base64url(input: ArrayBuffer | ArrayBufferView): Promise<string> {
  const buffer = input instanceof ArrayBuffer ? input : input.buffer;
  const bytes = new Uint8Array(buffer);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  let s = btoa(bin);
  s = s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return s;
}

async function buildGoogleJwt(env: Env): Promise<{ token: string; exp: number }> {
  const clientEmail = env.FCM_CLIENT_EMAIL;
  const privateKeyPem = env.FCM_PRIVATE_KEY?.replace(/\\n/g, "\n");
  const projectId = env.FCM_PROJECT_ID;
  if (!clientEmail || !privateKeyPem || !projectId) {
    throw new Error("fcm_not_configured");
  }

  // Import the PEM private key
  const key = (await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  )) as CryptoKey;

  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };
  const header = { alg: "RS256", typ: "JWT" };
  const enc = (o: unknown) =>
    base64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${enc(header)}.${enc(claims)}`;
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const signature = await base64url(sig);
  const jwt = `${unsigned}.${signature}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenData = (await tokenRes.json()) as { access_token?: string; expires_in?: number; error?: string };
  if (!tokenRes.ok || !tokenData.access_token) {
    throw new Error(tokenData.error ?? "fcm_token_failed");
  }
  return {
    token: tokenData.access_token,
    exp: (tokenData.expires_in ?? 3600) + now,
  };
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer as ArrayBuffer;
}

async function getFcmAccessToken(env: Env): Promise<string> {
  if (cachedFcmToken && Date.now() / 1000 < cachedFcmToken.exp - 60) {
    return cachedFcmToken.token;
  }
  cachedFcmToken = await buildGoogleJwt(env);
  return cachedFcmToken.token;
}

export interface FcmMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  androidChannelId?: string;
}

export async function sendFcm(args: {
  env: Env;
  message: FcmMessage;
  userId: string;
  topic: string;
}): Promise<{ ok: boolean; error?: string }> {
  const { env, message, userId, topic } = args;
  try {
    const accessToken = await getFcmAccessToken(env);
    const projectId = env.FCM_PROJECT_ID!;
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: message.token,
            notification: { title: message.title, body: message.body },
            android: {
              priority: "high",
              notification: {
                channel_id: message.androidChannelId ?? "synaptic_go_default",
                default_vibrate_timings: true,
              },
            },
            data: message.data ?? {},
          },
        }),
      },
    );
    const data = (await res.json()) as { name?: string; error?: { message: string } };
    if (!res.ok) {
      await logNotification(
        { DB: env.DB, userId, channel: "fcm", topic, payload: { token: message.token } as unknown as Record<string, unknown> },
        "failed",
        undefined,
        data.error?.message ?? `HTTP ${res.status}`,
      );
      return { ok: false, error: data.error?.message ?? `HTTP ${res.status}` };
    }
    await logNotification(
      { DB: env.DB, userId, channel: "fcm", topic, payload: { token: message.token } as unknown as Record<string, unknown> },
      "sent",
      data.name,
    );
    return { ok: true };
  } catch (e) {
    const msg = (e as Error).message;
    await logNotification(
      { DB: env.DB, userId, channel: "fcm", topic, payload: { token: message.token } as unknown as Record<string, unknown> },
      e instanceof Error && msg === "fcm_not_configured" ? "dropped" : "failed",
      undefined,
      msg,
    );
    return { ok: false, error: msg };
  }
}

/**
 * Fan out a notification to every active device token for a user.
 * Each token gets its own FCM attempt.
 */
export async function pushToUser(args: {
  env: Env;
  userId: string;
  topic: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}): Promise<void> {
  const tokens = await args.env.DB.prepare(
    `SELECT token FROM device_tokens WHERE user_id = ? ORDER BY last_seen_at DESC`,
  )
    .bind(args.userId)
    .all<{ token: string }>();
  if (!tokens.results?.length) return;
  await Promise.all(
    tokens.results.map((row) =>
      sendFcm({
        env: args.env,
        userId: args.userId,
        topic: args.topic,
        message: {
          token: row.token,
          title: args.title,
          body: args.body,
          data: args.data,
        },
      }),
    ),
  );
}