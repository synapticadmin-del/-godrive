/**
 * Cloudflare Turnstile verification helper.
 *
 * Set via `wrangler secret put TURNSTILE_SECRET_KEY`. When absent or empty,
 * validation is skipped (so dev still works) — TURNSTILE_SITE_KEY drives the
 * widget in the frontend (safe to expose; put it in [vars]).
 */
import { id, nowIso } from "./utils";

export async function verifyTurnstile(args: {
  token?: string;
  remoteIp?: string;
  env: Env;
}): Promise<{ ok: boolean; error?: string }> {
  const { token, remoteIp, env } = args;
  const secret = env.TURNSTILE_SECRET_KEY;
  if (!secret) {
    // No secret in dev → skip but record a synthetic "verified:true" entry so
    // the audit trail still exists.
    await env.DB.prepare(
      `INSERT INTO turnstile_verifications (id, token, ip, verified, error, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(id("ts"), token ?? "skipped", remoteIp ?? null, 1, "no_secret_skip", nowIso())
      .run();
    return { ok: true };
  }
  if (!token) return { ok: false, error: "missing_token" };
  try {
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        secret,
        response: token,
        remoteip: remoteIp ?? "",
      }),
    });
    const data = (await res.json()) as { success?: boolean; "error-codes"?: string[] };
    const ok = Boolean(data.success);
    await env.DB.prepare(
      `INSERT INTO turnstile_verifications (id, token, ip, verified, error, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        id("ts"),
        token,
        remoteIp ?? null,
        ok ? 1 : 0,
        ok ? null : JSON.stringify(data["error-codes"] ?? []),
        nowIso(),
      )
      .run();
    return { ok, error: ok ? undefined : "turnstile_failed" };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
}