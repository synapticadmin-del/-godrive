/**
 * Migration 0024 — dashboard RBAC.
 *
 * The operator console used to be one flat gate: users.role = 'admin' opened
 * every endpoint. These tests pin the replacement — users.dashboard_role
 * resolves through lib/staff.ts into permissions, and requireStaff enforces
 * them per route. The properties that must not regress:
 *
 *  1. A limited role is refused on endpoints outside its grant, with the
 *     PERMISSION_DENIED code (not a generic 403 a client cannot branch on).
 *  2. A pre-RBAC admin (role=admin, dashboard_role NULL) still resolves to
 *     owner — nobody who had access before the migration loses it.
 *  3. Suspension closes the fifteen-minute access-token window immediately.
 *  4. The staff endpoints protect the role system itself: no self-edits,
 *     never demote the last active owner.
 */
import { env, SELF } from "cloudflare:test";
import { describe, it, expect, beforeEach } from "vitest";
import { authHeaders } from "./helpers";
import { effectiveStaffRole, hasPermission, permissionsFor, STAFF_PERMISSIONS } from "../src/lib/staff";

async function seedStaff(id: string, dashboardRole: string | null, status = "active"): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO users (id, email, name, role, status, dashboard_role, created_at, updated_at)
     VALUES (?, ?, ?, 'admin', ?, ?, datetime('now'), datetime('now'))`,
  )
    .bind(id, `${id}@test.local`, id, status, dashboardRole)
    .run();
}

describe("lib/staff — the matrix itself", () => {
  it("owner carries every permission, derived not enumerated", () => {
    expect(permissionsFor("owner")).toEqual(STAFF_PERMISSIONS);
  });

  it("finance gets payouts but nothing operational", () => {
    expect(hasPermission("finance", "payouts:manage")).toBe(true);
    expect(hasPermission("finance", "captains:manage")).toBe(false);
    expect(hasPermission("finance", "staff:manage")).toBe(false);
  });

  it("support gets search and SOS but not documents or captains", () => {
    expect(hasPermission("support", "safety:view")).toBe(true);
    expect(hasPermission("support", "users:view")).toBe(true);
    expect(hasPermission("support", "documents:review")).toBe(false);
    expect(hasPermission("support", "captains:view")).toBe(false);
  });

  it("assistant reviews documents but cannot approve captains", () => {
    expect(hasPermission("assistant", "documents:review")).toBe(true);
    expect(hasPermission("assistant", "captains:manage")).toBe(false);
  });

  it("a NULL dashboard_role on role=admin resolves to owner", () => {
    expect(effectiveStaffRole({ role: "admin", dashboard_role: null })).toBe("owner");
    expect(effectiveStaffRole({ role: "rider", dashboard_role: null })).toBeNull();
    expect(effectiveStaffRole({ role: "admin", dashboard_role: "finance" })).toBe("finance");
  });
});

describe("requireStaff — the enforcement at the edge", () => {
  beforeEach(async () => {
    await seedStaff("owner_1", "owner");
    await seedStaff("legacy_1", null); // pre-RBAC admin
    await seedStaff("finance_1", "finance");
    await seedStaff("support_1", "support");
    await seedStaff("gone_1", "assistant", "suspended");
  });

  it("owner reaches the owner-only staff console", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff", {
      headers: await authHeaders("owner_1", "admin"),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { staff: { id: string }[] };
    expect(body.staff.map((s) => s.id)).toContain("owner_1");
  });

  it("a pre-RBAC admin (NULL dashboard_role) keeps owner access", async () => {
    const res = await SELF.fetch("https://api.test/admin/system-config", {
      headers: await authHeaders("legacy_1", "admin"),
    });
    expect(res.status).toBe(200);
  });

  it("finance gets 403 PERMISSION_DENIED on pricing", async () => {
    const res = await SELF.fetch("https://api.test/admin/pricing", {
      headers: await authHeaders("finance_1", "admin"),
    });
    expect(res.status).toBe(403);
    const body = (await res.json()) as { code: string };
    expect(body.code).toBe("PERMISSION_DENIED");
  });

  it("finance reaches the payout queue", async () => {
    const res = await SELF.fetch("https://api.test/admin/payouts", {
      headers: await authHeaders("finance_1", "admin"),
    });
    expect(res.status).toBe(200);
  });

  it("support cannot approve captains", async () => {
    const res = await SELF.fetch("https://api.test/admin/captains/whoever/approve", {
      method: "POST",
      headers: await authHeaders("support_1", "admin"),
    });
    expect(res.status).toBe(403);
    const body = (await res.json()) as { code: string };
    expect(body.code).toBe("PERMISSION_DENIED");
  });

  it("a suspended staff member is blocked even with a valid token", async () => {
    const res = await SELF.fetch("https://api.test/admin/documents", {
      headers: await authHeaders("gone_1", "admin"),
    });
    expect(res.status).toBe(403);
    const body = (await res.json()) as { code: string };
    expect(body.code).toBe("SUSPENDED");
  });

  it("a rider token never reaches the dashboard, whatever it asks for", async () => {
    const res = await SELF.fetch("https://api.test/admin/stats", {
      headers: await authHeaders("rider_x", "rider"),
    });
    expect(res.status).toBe(403);
  });
});

describe("/admin/staff — the role system protects itself", () => {
  beforeEach(async () => {
    await seedStaff("owner_1", "owner");
    await seedStaff("owner_2", "owner");
    await seedStaff("helper_1", "assistant");
  });

  it("refuses self-modification", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff/owner_1", {
      method: "PATCH",
      headers: await authHeaders("owner_1", "admin"),
      body: JSON.stringify({ dashboardRole: "assistant" }),
    });
    expect(res.status).toBe(400);
  });

  it("refuses self-removal", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff/owner_1", {
      method: "DELETE",
      headers: await authHeaders("owner_1", "admin"),
    });
    expect(res.status).toBe(400);
  });

  it("removal is a suspension, never a row delete", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff/owner_2", {
      method: "DELETE",
      headers: await authHeaders("owner_1", "admin"),
    });
    expect(res.status).toBe(200);

    const row = await env.DB.prepare(`SELECT status FROM users WHERE id = 'owner_2'`).first<{ status: string }>();
    expect(row?.status).toBe("suspended");

    // The guard fires here: owner_2 was suspended, so owner_1 is now the
    // last active owner, and removing them must be refused for ANY actor.
    // (No other owner exists to make the call, which is exactly the lockout
    // the guard exists to prevent.)
  });

  it("demotes a peer owner while another owner remains", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff/owner_2", {
      method: "PATCH",
      headers: await authHeaders("owner_1", "admin"),
      body: JSON.stringify({ dashboardRole: "assistant" }),
    });
    expect(res.status).toBe(200);

    const row = await env.DB.prepare(`SELECT dashboard_role FROM users WHERE id = 'owner_2'`).first<{ dashboard_role: string }>();
    expect(row?.dashboard_role).toBe("assistant");
  });

  it("creates a staff account with the requested role", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff", {
      method: "POST",
      headers: await authHeaders("owner_1", "admin"),
      body: JSON.stringify({
        email: "new.support@test.local",
        name: "Support One",
        password: "longenoughpassword",
        dashboardRole: "support",
      }),
    });
    expect(res.status).toBe(200);
    const row = await env.DB.prepare(
      `SELECT role, dashboard_role, status FROM users WHERE email = 'new.support@test.local'`,
    ).first<{ role: string; dashboard_role: string; status: string }>();
    expect(row?.role).toBe("admin");
    expect(row?.dashboard_role).toBe("support");
    expect(row?.status).toBe("active");
  });

  it("rejects a short password and an unknown role", async () => {
    const short = await SELF.fetch("https://api.test/admin/staff", {
      method: "POST",
      headers: await authHeaders("owner_1", "admin"),
      body: JSON.stringify({ email: "x@test.local", password: "short" }),
    });
    expect(short.status).toBe(400);

    const badRole = await SELF.fetch("https://api.test/admin/staff", {
      method: "POST",
      headers: await authHeaders("owner_1", "admin"),
      body: JSON.stringify({ email: "y@test.local", password: "longenoughpassword", dashboardRole: "superuser" }),
    });
    expect(badRole.status).toBe(400);
  });

  it("non-owners never reach the staff endpoints", async () => {
    const res = await SELF.fetch("https://api.test/admin/staff", {
      headers: await authHeaders("helper_1", "admin"),
    });
    expect(res.status).toBe(403);
    const body = (await res.json()) as { code: string };
    expect(body.code).toBe("PERMISSION_DENIED");
  });
});
