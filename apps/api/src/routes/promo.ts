import { Hono } from "hono";
import { createPromoSchema, validatePromoSchema } from "../lib/schemas";
import { logAudit } from "../lib/audit";
import { nowIso } from "../lib/utils";
import { authMiddleware, requireStaff, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";

export const promoRoutes = new Hono<AppEnv>();

promoRoutes.post("/validate", authMiddleware, async (c) => {
  const body = await parseBody(c, validatePromoSchema);
  if (isResponse(body)) return body;

  const promo = await c.env.DB.prepare(
    `SELECT * FROM promo_codes WHERE code = ? AND active = 1`,
  )
    .bind(body.code.toUpperCase())
    .first<{
      code: string;
      type: string;
      value: number;
      max_uses: number | null;
      uses_count: number;
      expires_at: string | null;
    }>();

  if (!promo) {
    return c.json({ valid: false, error: "Invalid promo code", code: "PROMO_INVALID" }, 404);
  }
  if (promo.expires_at && new Date(promo.expires_at).getTime() < Date.now()) {
    return c.json({ valid: false, error: "Promo expired", code: "PROMO_EXPIRED" }, 400);
  }
  if (promo.max_uses != null && promo.uses_count >= promo.max_uses) {
    return c.json({ valid: false, error: "Promo fully used", code: "PROMO_EXHAUSTED" }, 400);
  }

  const estimate = body.tripEstimate ?? 0;
  const discount =
    promo.type === "percent"
      ? Math.round(estimate * (promo.value / 100) * 100) / 100
      : Math.min(promo.value, estimate);

  return c.json({
    valid: true,
    code: promo.code,
    type: promo.type,
    value: promo.value,
    discount,
    finalFare: Math.max(0, Math.round((estimate - discount) * 100) / 100),
  });
});

promoRoutes.get("/", authMiddleware, requireStaff("config:manage"), async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT * FROM promo_codes ORDER BY created_at DESC LIMIT 200`,
  ).all();
  return c.json({ promos: res.results ?? [] });
});

promoRoutes.post("/", authMiddleware, requireStaff("config:manage"), async (c) => {
  const body = await parseBody(c, createPromoSchema);
  if (isResponse(body)) return body;
  const user = c.get("user");

  try {
    await c.env.DB.prepare(
      `INSERT INTO promo_codes (code, type, value, max_uses, expires_at, active)
       VALUES (?, ?, ?, ?, ?, 1)`,
    )
      .bind(
        body.code,
        body.type,
        body.value,
        body.maxUses ?? null,
        body.expiresAt ?? null,
      )
      .run();
  } catch {
    return c.json({ error: "Promo code already exists", code: "PROMO_EXISTS" }, 409);
  }

  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "promo.create",
    entityType: "promo_codes",
    entityId: body.code,
    payload: body,
    ip: c.req.header("cf-connecting-ip"),
  });

  return c.json({ ok: true, code: body.code }, 201);
});

promoRoutes.post("/:code/deactivate", authMiddleware, requireStaff("config:manage"), async (c) => {
  const codeParam = c.req.param("code") ?? "";
  const code = codeParam.toUpperCase();
  if (!code) return c.json({ error: "code required", code: "MISSING_CODE" }, 400);
  const user = c.get("user");
  await c.env.DB.prepare(`UPDATE promo_codes SET active = 0 WHERE code = ?`).bind(code).run();
  await logAudit(c.env.DB, {
    actorId: user.id,
    action: "promo.deactivate",
    entityType: "promo_codes",
    entityId: code,
    ip: c.req.header("cf-connecting-ip"),
  });
  return c.json({ ok: true, code, at: nowIso() });
});
