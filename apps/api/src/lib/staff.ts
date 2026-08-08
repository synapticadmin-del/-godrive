/**
 * Dashboard staff roles and their permissions (RBAC).
 *
 * Every dashboard account keeps users.role = 'admin' (the users.role CHECK
 * constraint predates this system and widening it needs a table rebuild on
 * production D1). What an admin can actually touch is decided by
 * users.dashboard_role, added in migration 0024, and the matrix below.
 *
 * The hierarchy, top down:
 *
 *   owner     — the platform principal. Everything, including this matrix's
 *               own administration (creating staff, changing roles).
 *   admin     — operations manager: the live console, captain onboarding and
 *               discipline, documents, SOS. No money knobs, no pricing, no
 *               staff management.
 *   assistant — an operations assistant: reads the console and works the
 *               document-review queue. No captain approve/suspend, no SOS.
 *   support   — customer service: finds users and trips, works the SOS
 *               queue. That is the whole job.
 *   finance   — payouts and the revenue numbers behind them. Nothing else.
 *
 * Two deliberate rules:
 *  * Permissions are strings checked on the server. The admin UI hides what a
 *    role cannot do, but hiding is UX — this matrix is the enforcement.
 *  * role = 'admin' with a NULL dashboard_role resolves to 'owner'. Every
 *    account that existed before migration 0024 keeps working, and a row the
 *    seed somehow missed can never become locked out of its own platform.
 */

export const STAFF_ROLES = ["owner", "admin", "assistant", "support", "finance"] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export const STAFF_PERMISSIONS = [
  "stats:view",        // overview cards, live-trips feed, live map
  "analytics:view",    // revenue/analytics dashboards
  "captains:view",     // captain list, online captains
  "captains:manage",   // approve / suspend captains
  "documents:view",    // document queue + file images
  "documents:review",  // approve / reject documents
  "trips:view",        // trip list and search
  "users:view",        // rider list and global search
  "safety:view",       // SOS queue (ack, event, resolve)
  "audit:view",        // audit log
  "pricing:manage",    // pricing rules + vehicle types
  "config:manage",     // system config, document-type catalog, promos, intercity/companies admin
  "payouts:manage",    // payout queue + settle/reject
  "staff:manage",      // create/edit/suspend dashboard accounts, change roles
] as const;
export type StaffPermission = (typeof STAFF_PERMISSIONS)[number];

/**
 * The grant table. Owner is derived rather than enumerated so a permission
 * added later can never silently miss the one role that must have it.
 */
const GRANTS: Record<Exclude<StaffRole, "owner">, readonly StaffPermission[]> = {
  admin: [
    "stats:view",
    "analytics:view",
    "captains:view",
    "captains:manage",
    "documents:view",
    "documents:review",
    "trips:view",
    "users:view",
    "safety:view",
    "audit:view",
  ],
  assistant: [
    "stats:view",
    "captains:view",
    "documents:view",
    "documents:review",
    "trips:view",
    "users:view",
  ],
  support: ["stats:view", "trips:view", "users:view", "safety:view"],
  finance: ["stats:view", "analytics:view", "payouts:manage"],
};

export function permissionsFor(role: StaffRole): readonly StaffPermission[] {
  if (role === "owner") return STAFF_PERMISSIONS;
  return GRANTS[role];
}

export function hasPermission(role: StaffRole, permission: StaffPermission): boolean {
  return permissionsFor(role).includes(permission);
}

export function isStaffRole(value: string | null | undefined): value is StaffRole {
  return typeof value === "string" && (STAFF_ROLES as readonly string[]).includes(value);
}

/**
 * Resolve the effective dashboard role for a users row. NULL on a role=admin
 * account means "pre-RBAC admin" and resolves to owner (see the file header).
 * NULL on any other app role means "not dashboard staff" — no resolution.
 */
export function effectiveStaffRole(
  user: { role: string; dashboard_role: string | null },
): StaffRole | null {
  if (user.role !== "admin") return null;
  if (user.dashboard_role === null) return "owner";
  return isStaffRole(user.dashboard_role) ? user.dashboard_role : null;
}
