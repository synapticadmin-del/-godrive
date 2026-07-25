import type { Context, Next } from "hono";
import { verifyToken } from "../lib/jwt";
import type { AuthUser } from "../lib/types";

export type AppEnv = {
  Bindings: Env;
  Variables: {
    user: AuthUser;
  };
};

export async function authMiddleware(c: Context<AppEnv>, next: Next) {
  const header = c.req.header("Authorization");
  let token = header?.startsWith("Bearer ") ? header.slice(7) : null;

  if (!token) {
    token = c.req.query("token") ?? null;
  }

  if (!token) {
    return c.json({ error: "Unauthorized", code: "UNAUTHORIZED" }, 401);
  }

  try {
    const user = await verifyToken(token, c.env.JWT_SECRET, c.env.JWT_ISSUER);
    // Reject pure refresh tokens on protected routes
    if (user.typ === "refresh") {
      return c.json({ error: "Use access token", code: "WRONG_TOKEN_TYPE" }, 401);
    }
    c.set("user", {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
    });
    await next();
  } catch {
    return c.json({ error: "Invalid or expired token", code: "INVALID_TOKEN" }, 401);
  }
}

export function requireRole(...roles: AuthUser["role"][]) {
  return async (c: Context<AppEnv>, next: Next) => {
    const user = c.get("user");
    if (!roles.includes(user.role)) {
      return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
    }
    await next();
  };
}
