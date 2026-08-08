import type { Context, Next } from "hono";
import { verifyToken } from "../lib/jwt";
import { effectiveStaffRole, hasPermission, type StaffPermission, type StaffRole } from "../lib/staff";
import type { AuthUser } from "../lib/types";

export type AppEnv = {
  Bindings: Env;
  Variables: {
    user: AuthUser;
    /** Set by requireStaff once the dashboard role has been resolved. */
    staffRole?: StaffRole;
  };
};

/**
 * Paths permitted to authenticate via a ?token= query parameter.
 *
 * A browser cannot attach an Authorization header to a WebSocket handshake, nor
 * to the request an <img> element makes, so those two cases have no
 * alternative. Every other route must use the header: tokens placed in a query
 * string leak into server access logs, proxy logs, browser history, and the
 * Referer header sent to any third-party resource the page loads.
 */
function queryTokenAllowed(path: string): boolean {
  // WebSocket upgrades — this is the documented behaviour (docs/API.md).
  if (path.startsWith("/ws/")) return true;
  // Admin document images, which are rendered directly via <img src>.
  if (/^\/admin\/documents\/[^/]+\/file$/.test(path)) return true;
  return false;
}

export async function authMiddleware(c: Context<AppEnv>, next: Next) {
  const header = c.req.header("Authorization");
  let token = header?.startsWith("Bearer ") ? header.slice(7) : null;

  if (!token) {
    let pathname = c.req.path;
    try {
      pathname = new URL(c.req.url).pathname;
    } catch {
      // c.req.path is already the fallback.
    }
    if (queryTokenAllowed(pathname)) {
      token = c.req.query("token") ?? null;
    }
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

/**
 * Dashboard RBAC gate (migration 0024 + lib/staff.ts).
 *
 * Replaces the old flat requireRole("admin") on operator endpoints: every
 * dashboard account is still role='admin', but users.dashboard_role decides
 * which permissions it carries. The role is re-read from D1 on every request
 * rather than trusted from the JWT — one cheap SELECT — so an owner can
 * demote or suspend a member of staff and the change lands on their very
 * next call, not when their token expires in fifteen minutes.
 *
 * The caller must hold EVERY listed permission; endpoints that offer several
 * capabilities list them all.
 */
export function requireStaff(...permissions: StaffPermission[]) {
  return async (c: Context<AppEnv>, next: Next) => {
    const user = c.get("user");
    if (user.role !== "admin") {
      return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
    }

    const row = await c.env.DB.prepare(
      `SELECT role, status, dashboard_role FROM users WHERE id = ?`,
    )
      .bind(user.id)
      .first<{ role: string; status: string; dashboard_role: string | null }>();

    // A suspended account keeps a valid access token for up to fifteen
    // minutes; this is where that window is closed for the dashboard.
    if (!row || row.status === "suspended") {
      return c.json({ error: "Account suspended", code: "SUSPENDED" }, 403);
    }

    const staffRole = effectiveStaffRole(row);
    if (!staffRole) {
      return c.json({ error: "Forbidden", code: "FORBIDDEN" }, 403);
    }

    for (const permission of permissions) {
      if (!hasPermission(staffRole, permission)) {
        return c.json(
          { error: "Insufficient dashboard permissions", code: "PERMISSION_DENIED", required: permissions },
          403,
        );
      }
    }

    c.set("staffRole", staffRole);
    await next();
  };
}
