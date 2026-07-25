import type { Context, Next } from "hono";
import type { ZodSchema, ZodTypeDef } from "zod";
import type { AppEnv } from "./auth";

type RateLimitOpts = {
  prefix: string;
  limit: number;
  windowSec: number;
  keyFn?: (c: Context<AppEnv>) => string;
};

/**
 * Fixed-window rate limiter backed by Workers KV.
 * Key: rl:{prefix}:{id}:{windowBucket}
 */
export function rateLimit(opts: RateLimitOpts) {
  return async (c: Context<AppEnv>, next: Next) => {
    const id =
      opts.keyFn?.(c) ??
      c.req.header("cf-connecting-ip") ??
      c.req.header("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";

    const bucket = Math.floor(Date.now() / 1000 / opts.windowSec);
    const key = `rl:${opts.prefix}:${id}:${bucket}`;

    let count = 0;
    try {
      const raw = await c.env.SESSIONS.get(key);
      count = raw ? Number(raw) || 0 : 0;
    } catch {
      await next();
      return;
    }

    if (count >= opts.limit) {
      c.header("Retry-After", String(opts.windowSec));
      return c.json(
        {
          error: "Too many requests",
          code: "RATE_LIMITED",
          limit: opts.limit,
          windowSec: opts.windowSec,
        },
        429,
      );
    }

    c.executionCtx.waitUntil(
      c.env.SESSIONS.put(key, String(count + 1), {
        expirationTtl: opts.windowSec + 5,
      }),
    );

    c.header("X-RateLimit-Limit", String(opts.limit));
    c.header("X-RateLimit-Remaining", String(Math.max(0, opts.limit - count - 1)));

    await next();
  };
}

/** Parse + validate JSON body. Returns data or a Response (400). */
export async function parseBody<T>(
  c: Context,
  schema: ZodSchema<T, ZodTypeDef, unknown>,
): Promise<T | Response> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    return c.json({ error: "Invalid JSON body", code: "INVALID_JSON" }, 400);
  }

  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    return c.json(
      {
        error: "Validation failed",
        code: "VALIDATION_ERROR",
        details: parsed.error.flatten(),
      },
      400,
    );
  }
  return parsed.data;
}

export function isResponse(v: unknown): v is Response {
  return v instanceof Response;
}
