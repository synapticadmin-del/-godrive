import { Hono } from "hono";
import type { UserRole } from "@synaptic-go/shared";
import {
  hashToken,
  signAccessToken,
  signRefreshToken,
  verifyToken,
} from "../lib/jwt";
import { logAudit } from "../lib/audit";
import {
  requestOtpSchema,
  verifyOtpSchema,
  refreshSchema,
} from "../lib/schemas";
import type { DbCaptain, DbUser } from "../lib/types";
import { asBool, id, nowIso, otpCode, hashPassword, verifyPassword } from "../lib/utils";
import { authMiddleware, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody, rateLimit } from "../middleware/rateLimit";
import { sendWhatsAppOtp, sendEmailOtp } from "../lib/notifications";
import { verifyTurnstile } from "../lib/turnstile";

export const authRoutes = new Hono<AppEnv>();

async function issueTokens(env: Env, user: DbUser) {
  const authUser = {
    id: user.id,
    email: user.email,
    role: user.role,
    name: user.name,
  };

  const accessToken = await signAccessToken(authUser, env.JWT_SECRET, env.JWT_ISSUER);
  const jti = id("rt");
  const refreshToken = await signRefreshToken(
    authUser,
    env.JWT_SECRET,
    env.JWT_ISSUER,
    jti,
  );
  const tokenHash = await hashToken(refreshToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

  await env.DB.prepare(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)`,
  )
    .bind(jti, user.id, tokenHash, expiresAt)
    .run();

  return { accessToken, refreshToken, token: accessToken };
}

authRoutes.post(
  "/request-otp",
  rateLimit({ prefix: "otp", limit: 5, windowSec: 60 }),
  async (c) => {
    const body = await parseBody(c, requestOtpSchema);
    if (isResponse(body)) return body;

    const email = body.email?.trim().toLowerCase();
    const phone = body.phone;
    const role = body.role;

    // Turnstile anti-bot verification when a site key + secret are configured.
    if (body.turnstileToken) {
      const ts = await verifyTurnstile({
        token: body.turnstileToken,
        remoteIp: c.req.header("cf-connecting-ip"),
        env: c.env,
      });
      if (!ts.ok) {
        return c.json({ error: "تحقق الإنسانية فشل", code: "TURNSTILE_FAILED" }, 400);
      }
    }

    if (role === "admin") {
      const existingAdmin = await c.env.DB.prepare(
        "SELECT id FROM users WHERE role = 'admin' LIMIT 1",
      ).first();
      const thisAdmin = await c.env.DB.prepare(
        "SELECT id FROM users WHERE email = ? AND role = 'admin'",
      )
        .bind(email ?? "")
        .first();
      if (existingAdmin && !thisAdmin) {
        return c.json({ error: "Admin access denied for this email", code: "ADMIN_DENIED" }, 403);
      }
    }

    const code = otpCode();
    const otpId = id("otp");
    const expires = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    // Store OTP against the effective identifier (phone or email)
    const identKey = phone ?? email ?? "";
    await c.env.DB.prepare(
      `INSERT INTO otp_codes (id, email, code, role, expires_at) VALUES (?, ?, ?, ?, ?)`,
    )
      .bind(otpId, identKey, code, role, expires)
      .run();

    if (body.name) {
      await c.env.SESSIONS.put(`otp-name:${identKey}`, body.name, { expirationTtl: 600 });
    }

    // Delivery: WhatsApp OTP if phone given; otherwise email OTP. When secrets
    // are absent the channel returns `dev: code` so the flow keeps working
    // in dev. We always surface the devCode when DEV_OTP=true.
    let delivered = false;
    let devFromChannel: string | undefined;
    if (phone) {
      const res = await sendWhatsAppOtp({ env: c.env, phone, code, userId: identKey });
      delivered = res.ok;
      devFromChannel = res.dev;
    } else if (email) {
      const res = await sendEmailOtp({ env: c.env, email, code, userId: identKey });
      delivered = res.ok;
    }

    const payload: Record<string, unknown> = {
      ok: true,
      message: delivered ? "OTP sent" : "OTP generated (delivery deferred)",
      expiresAt: expires,
      channel: phone ? "whatsapp" : "email",
    };

    if (asBool(c.env.DEV_OTP, true) || devFromChannel) {
      payload.devCode = code;
      payload.note = "DEV_OTP enabled or channel not configured — use devCode to login";
    }

    return c.json(payload);
  },
);

authRoutes.post(
  "/verify-otp",
  rateLimit({ prefix: "otp-verify", limit: 10, windowSec: 60 }),
  async (c) => {
    const body = await parseBody(c, verifyOtpSchema);
    if (isResponse(body)) return body;

    const email = body.email?.trim().toLowerCase();
    const phone = body.phone;
    const identKey = (phone ?? email ?? "").trim();
    const code = body.code.trim();

    const row = await c.env.DB.prepare(
      `SELECT id, role, expires_at, consumed_at FROM otp_codes
       WHERE email = ? AND code = ?
       ORDER BY created_at DESC LIMIT 1`,
    )
      .bind(identKey, code)
      .first<{ id: string; role: UserRole; expires_at: string; consumed_at: string | null }>();

    if (!row) return c.json({ error: "Invalid code", code: "INVALID_OTP" }, 401);
    if (row.consumed_at) return c.json({ error: "Code already used", code: "OTP_USED" }, 401);
    if (new Date(row.expires_at).getTime() < Date.now()) {
      return c.json({ error: "Code expired", code: "OTP_EXPIRED" }, 401);
    }

    await c.env.DB.prepare(`UPDATE otp_codes SET consumed_at = ? WHERE id = ?`)
      .bind(nowIso(), row.id)
      .run();

    // Identity resolution: prefer phone (Egypt market) when given, else email.
    const phoneClause = phone ? `phone = ?` : null;
    const emailClause = email ? `email = ?` : null;
    const clause = phoneClause ?? emailClause ?? `email = ?`;
    const clauseValue = phone ?? email ?? identKey;

    let user = await c.env.DB.prepare(`SELECT * FROM users WHERE ${clause}`)
      .bind(clauseValue)
      .first<DbUser>();

    if (!user) {
      const pendingName = await c.env.SESSIONS.get(`otp-name:${identKey}`);
      const userId = id("usr");
      // Backwards-compat: otp_codes.email column holds phone OR email. We use
      // email column for the identifier; phone column gets the phone if any.
      await c.env.DB.prepare(
        `INSERT INTO users (id, email, name, role, status, phone) VALUES (?, ?, ?, ?, 'active', ?)`,
      )
        .bind(
          userId,
          email ?? identKey,
          pendingName,
          row.role,
          phone ?? null,
        )
        .run();

      if (row.role === "captain") {
        await c.env.DB.prepare(
          `INSERT INTO captains (user_id, approval_status) VALUES (?, 'pending')`,
        )
          .bind(userId)
          .run();
      }

      user = await c.env.DB.prepare(`SELECT * FROM users WHERE id = ?`)
        .bind(userId)
        .first<DbUser>();
    }

    if (!user) return c.json({ error: "Failed to create user", code: "USER_CREATE_FAILED" }, 500);
    if (user.status === "suspended") {
      return c.json({ error: "Account suspended", code: "SUSPENDED" }, 403);
    }

    const tokens = await issueTokens(c.env, user);

    let captain: DbCaptain | null = null;
    if (user.role === "captain") {
      captain =
        (await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
          .bind(user.id)
          .first<DbCaptain>()) ?? null;
    }

    await logAudit(c.env.DB, {
      actorId: user.id,
      action: "auth.login",
      entityType: "user",
      entityId: user.id,
      ip: c.req.header("cf-connecting-ip"),
      userAgent: c.req.header("user-agent"),
    });

    return c.json({
      ...tokens,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        role: user.role,
        status: user.status,
      },
      captain,
    });
  },
);

authRoutes.post(
  "/refresh",
  rateLimit({ prefix: "refresh", limit: 20, windowSec: 60 }),
  async (c) => {
    const body = await parseBody(c, refreshSchema);
    if (isResponse(body)) return body;

    let payload: Awaited<ReturnType<typeof verifyToken>>;
    try {
      payload = await verifyToken(body.refreshToken, c.env.JWT_SECRET, c.env.JWT_ISSUER);
    } catch {
      return c.json({ error: "Invalid refresh token", code: "INVALID_REFRESH" }, 401);
    }

    if (payload.typ !== "refresh" || !payload.jti) {
      return c.json({ error: "Not a refresh token", code: "WRONG_TOKEN_TYPE" }, 401);
    }

    const tokenHash = await hashToken(body.refreshToken);
    const stored = await c.env.DB.prepare(
      `SELECT id, user_id, expires_at, revoked_at FROM refresh_tokens WHERE id = ? AND token_hash = ?`,
    )
      .bind(payload.jti, tokenHash)
      .first<{ id: string; user_id: string; expires_at: string; revoked_at: string | null }>();

    if (!stored || stored.revoked_at) {
      return c.json({ error: "Refresh token revoked", code: "REFRESH_REVOKED" }, 401);
    }
    if (new Date(stored.expires_at).getTime() < Date.now()) {
      return c.json({ error: "Refresh token expired", code: "REFRESH_EXPIRED" }, 401);
    }

    // Rotate: revoke old
    await c.env.DB.prepare(`UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?`)
      .bind(nowIso(), stored.id)
      .run();

    const user = await c.env.DB.prepare(`SELECT * FROM users WHERE id = ?`)
      .bind(stored.user_id)
      .first<DbUser>();

    if (!user || user.status === "suspended") {
      return c.json({ error: "User not found or suspended", code: "USER_INVALID" }, 401);
    }

    const tokens = await issueTokens(c.env, user);
    return c.json({
      ...tokens,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        role: user.role,
        status: user.status,
      },
    });
  },
);

authRoutes.post("/logout", authMiddleware, async (c) => {
  const body = await c.req.json<{ refreshToken?: string }>().catch(() => ({}));
  if (body && typeof (body as { refreshToken?: string }).refreshToken === "string") {
    try {
      const rt = (body as { refreshToken: string }).refreshToken;
      const payload = await verifyToken(rt, c.env.JWT_SECRET, c.env.JWT_ISSUER);
      if (payload.jti) {
        await c.env.DB.prepare(`UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?`)
          .bind(nowIso(), payload.jti)
          .run();
      }
    } catch {
      /* ignore */
    }
  }

  // Also revoke all refresh tokens for this user (hard logout)
  const user = c.get("user");
  await c.env.DB.prepare(
    `UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL`,
  )
    .bind(nowIso(), user.id)
    .run();

  return c.json({ ok: true });
});

authRoutes.post("/register", rateLimit({ prefix: "register", limit: 10, windowSec: 60 }), async (c) => {
  const body = await c.req.json().catch(() => ({})) as {
    email?: string;
    name?: string;
    password?: string;
    role?: "rider" | "captain" | "admin";
  };
  if (!body.email || !body.password) {
    return c.json({ error: "email and password required", code: "VALIDATION_ERROR" }, 400);
  }
  const email = body.email.trim().toLowerCase();
  const existing = await c.env.DB.prepare(`SELECT id FROM users WHERE email = ?`).bind(email).first();
  if (existing) return c.json({ error: "Email already exists", code: "EMAIL_EXISTS" }, 409);
  const pwHash = await hashPassword(body.password);
  const userId = id("usr");
  await c.env.DB.prepare(
    `INSERT INTO users (id, email, password_hash, name, role, status, phone) VALUES (?, ?, ?, ?, ?, 'active', NULL)`,
  )
    .bind(userId, email, pwHash, body.name ?? "", body.role ?? "rider")
    .run();
  if ((body.role ?? "rider") === "captain") {
    await c.env.DB.prepare(`INSERT INTO captains (user_id, approval_status) VALUES (?, 'pending')`).bind(userId).run();
  }
  if ((body.role ?? "rider") === "admin") {
    // If this is the very first admin (default credentials), allow it silently.
    const adminCountRes = await c.env.DB.prepare(`SELECT COUNT(*) AS c FROM users WHERE role = 'admin'`).first<{ c: number }>();
    if (adminCountRes && (adminCountRes.c ?? 0) > 1) {
      return c.json({ error: "Admin already exists — use existing admin", code: "ADMIN_DENIED" }, 403);
    }
  }
  const user = await c.env.DB.prepare(`SELECT * FROM users WHERE id = ?`).bind(userId).first<DbUser>();
  if (!user) return c.json({ error: "User creation failed", code: "CREATE_FAILED" }, 500);
  const tokens = await issueTokens(c.env, user);
  await logAudit(c.env.DB, { actorId: user.id, action: "auth.register.email", entityType: "user", entityId: user.id, ip: c.req.header("cf-connecting-ip"), userAgent: c.req.header("user-agent") });
  return c.json({ ok: true, user: { id: user.id, email: user.email, role: user.role, name: user.name, status: user.status }, ...tokens });
});

authRoutes.post("/login", rateLimit({ prefix: "login", limit: 15, windowSec: 60 }), async (c) => {
  const body = await c.req.json().catch(() => ({})) as { email?: string; password?: string };
  if (!body.email || !body.password) {
    return c.json({ error: "email and password required", code: "VALIDATION_ERROR" }, 400);
  }
  const email = body.email.trim().toLowerCase();
  const user = await c.env.DB.prepare(`SELECT * FROM users WHERE email = ?`).bind(email).first<DbUser>();
  if (!user || !user.password_hash) {
    return c.json({ error: "Invalid credentials", code: "INVALID_CREDENTIALS" }, 401);
  }
  const pwOk = await verifyPassword(body.password, user.password_hash);
  if (!pwOk) return c.json({ error: "Invalid credentials", code: "INVALID_CREDENTIALS" }, 401);
  if (user.status === "suspended") return c.json({ error: "Account suspended", code: "SUSPENDED" }, 403);
  const authUser = { id: user.id, email: user.email, role: user.role, name: user.name };
  const accessToken = await signAccessToken(authUser, c.env.JWT_SECRET, c.env.JWT_ISSUER);
  const jti = id("rt");
  const refreshToken = await signRefreshToken(authUser, c.env.JWT_SECRET, c.env.JWT_ISSUER, jti);
  const tokenHash = await hashToken(refreshToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  await c.env.DB.prepare(`INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)`).bind(jti, user.id, tokenHash, expiresAt).run();
  await logAudit(c.env.DB, { actorId: user.id, action: "auth.login.email", entityType: "user", entityId: user.id, ip: c.req.header("cf-connecting-ip"), userAgent: c.req.header("user-agent") });
  let captain: DbCaptain | null = null;
  if (user.role === "captain") {
    captain = (await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`).bind(user.id).first<DbCaptain>()) ?? null;
  }
  return c.json({ accessToken, refreshToken, user: { id: user.id, email: user.email, name: user.name, phone: user.phone, role: user.role, status: user.status }, captain, token: accessToken });
});

// POST /auth/admin/setup — one-time admin creation (only when no admin exists).
// Intended for initial dashboard access. Protect with a setup token in prod,
// but here it checks if admin count is zero.
authRoutes.post("/admin/setup", rateLimit({ prefix: "admin-setup", limit: 3, windowSec: 300 }), async (c) => {
  const existing = await c.env.DB.prepare(`SELECT id FROM users WHERE role = 'admin'`).first();
  if (existing) {
    return c.json({ error: "Admin already exists", code: "ADMIN_EXISTS" }, 403);
  }
  const body = await c.req.json().catch(() => ({})) as {
    email?: string;
    name?: string;
    password?: string;
  };
  if (!body.email || !body.password) {
    return c.json({ error: "email and password required", code: "VALIDATION_ERROR" }, 400);
  }
  const pwHash = await hashPassword(body.password);
  const adminId = id("adm");
  await c.env.DB.prepare(
    `INSERT INTO users (id, email, password_hash, name, role, status, created_at, updated_at) VALUES (?, ?, ?, ?, 'admin', 'active', datetime('now'), datetime('now'))`,
  )
    .bind(adminId, body.email.trim().toLowerCase(), pwHash, body.name ?? "Administrator")
    .run();
  const admin = await c.env.DB.prepare(`SELECT * FROM users WHERE id = ?`).bind(adminId).first<DbUser>();
  const authUser = { id: admin!.id, email: admin!.email, role: admin!.role, name: admin!.name };
  const accessToken = await signAccessToken(authUser, c.env.JWT_SECRET, c.env.JWT_ISSUER);
  return c.json({ ok: true, user: { id: admin!.id, email: admin!.email, role: admin!.role, name: admin!.name, status: admin!.status }, accessToken, token: accessToken });
});

authRoutes.get("/me", authMiddleware, async (c) => {
  const auth = c.get("user");
  const user = await c.env.DB.prepare(`SELECT * FROM users WHERE id = ?`)
    .bind(auth.id)
    .first<DbUser>();
  if (!user) return c.json({ error: "User not found", code: "NOT_FOUND" }, 404);

  let captain: DbCaptain | null = null;
  if (user.role === "captain") {
    captain =
      (await c.env.DB.prepare(`SELECT * FROM captains WHERE user_id = ?`)
        .bind(user.id)
        .first<DbCaptain>()) ?? null;
  }

  return c.json({ user, captain });
});
