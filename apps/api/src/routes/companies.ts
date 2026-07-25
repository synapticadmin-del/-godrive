import { Hono } from "hono";
import { id, nowIso } from "../lib/utils";
import { authMiddleware, requireRole, type AppEnv } from "../middleware/auth";
import { isResponse, parseBody } from "../middleware/rateLimit";
import { companySchema, companyEmployeeSchema } from "../lib/schemas";
import { logAudit } from "../lib/audit";

export const companyRoutes = new Hono<AppEnv>();

// All company endpoints require auth
companyRoutes.use("*", authMiddleware);

// ---- Employee-bound rides: create a trip billed to my company ----
companyRoutes.post("/trip", async (c) => {
  const user = c.get("user");
  const body = (await c.req.json().catch(() => ({}))) as {
    costCenter?: string;
    pickupLat: number;
    pickupLng: number;
    dropoffLat: number;
    dropoffLng: number;
    vehicleTypeId?: string;
  };

  // Find any active employee binding for this user
  const emp = await c.env.DB.prepare(
    `SELECT e.company_id, e.cost_center, e.spend_limit_month, e.allowed_vehicle_types, e.allowed_hours,
            c.status AS company_status, c.credit_limit
     FROM company_employees e
     JOIN companies c ON c.id = e.company_id
     WHERE e.user_id = ? AND e.active = 1 AND c.status = 'active'
     LIMIT 1`,
  )
    .bind(user.id)
    .first<{ company_id: string; cost_center: string; spend_limit_month: number; allowed_vehicle_types: string; allowed_hours: string; company_status: string; credit_limit: number }>();
  if (!emp) return c.json({ error: "Not a company employee", code: "NOT_EMPLOYEE" }, 403);

  // Spend limit this month
  const spendRes = await c.env.DB.prepare(
    `SELECT COUNT(*) AS trips, COALESCE(SUM(COALESCE(final_fare, estimated_fare, 0)), 0) AS total
     FROM trips WHERE company_id = ? AND cost_center = ? AND billed_to_company = 1
     AND created_at >= datetime('now','start of month')`,
  )
    .bind(emp.company_id, body.costCenter ?? emp.cost_center ?? "")
    .first<{ trips: number; total: number }>();

  const monthSpend = spendRes?.total ?? 0;
  const limit = emp.spend_limit_month ?? 0;
  if (limit > 0 && monthSpend >= limit) {
    return c.json({ error: "تجاوزت الحد الشهري للإنفاق", code: "SPEND_LIMIT" }, 403);
  }

  // Don't actually create the trip here — rider flow goes through /trips with
  // a `companyId` marker. We just return authorization + booking context.
  return c.json({
    ok: true,
    allowed: true,
    company: {
      id: emp.company_id,
      costCenter: body.costCenter ?? emp.cost_center,
      monthSpend,
      spendLimit: limit,
    },
  });
});

// ---- Admin-facing company management ----
companyRoutes.use("/admin/*", requireRole("admin"));

companyRoutes.post("/admin", async (c) => {
  const body = await parseBody(c, companySchema);
  if (isResponse(body)) return body;
  const companyId = id("cmp");
  await c.env.DB.prepare(
    `INSERT INTO companies
      (id, name, legal_name, tax_id, contact_email, contact_phone, credit_limit, monthly_invoice_day, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', datetime('now'))`,
  )
    .bind(
      companyId,
      body.name,
      body.legalName ?? null,
      body.taxId ?? null,
      body.contactEmail ?? null,
      body.contactPhone ?? null,
      body.creditLimit,
      body.monthlyInvoiceDay,
    )
    .run();
  await logAudit(c.env.DB, {
    actorId: c.get("user").id,
    action: "company.create",
    entityType: "company",
    entityId: companyId,
  });
  return c.json({ ok: true, companyId });
});

companyRoutes.get("/admin", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT * FROM companies ORDER BY created_at DESC LIMIT 200`,
  ).all();
  return c.json({ companies: res.results ?? [] });
});

companyRoutes.get("/admin/:id", async (c) => {
  const company = await c.env.DB.prepare(`SELECT * FROM companies WHERE id = ?`)
    .bind(c.req.param("id"))
    .first();
  if (!company) return c.json({ error: "Not found", code: "NOT_FOUND" }, 404);
  const employees = await c.env.DB.prepare(
    `SELECT e.*, u.name, u.email, u.phone
     FROM company_employees e
     JOIN users u ON u.id = e.user_id
     WHERE e.company_id = ?`,
  )
    .bind(c.req.param("id"))
    .all();
  return c.json({ company, employees: employees.results ?? [] });
});

companyRoutes.post("/admin/employee", async (c) => {
  const body = await parseBody(c, companyEmployeeSchema);
  if (isResponse(body)) return body;
  const empId = id("emp");
  await c.env.DB.prepare(
    `INSERT INTO company_employees
      (id, company_id, user_id, cost_center, spend_limit_month, allowed_vehicle_types, allowed_hours, active, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 1, datetime('now'))`,
  )
    .bind(
      empId,
      body.companyId,
      body.userId,
      body.costCenter ?? null,
      body.spendLimitMonth,
      body.allowedVehicleTypes ? JSON.stringify(body.allowedVehicleTypes) : null,
      body.allowedHours ? JSON.stringify(body.allowedHours) : null,
    )
    .run();
  return c.json({ ok: true, employeeId: empId });
});

companyRoutes.patch("/admin/employee/:id", async (c) => {
  const empId = c.req.param("id");
  const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
  // Whitelist fields
  if ("active" in body) {
    await c.env.DB.prepare(`UPDATE company_employees SET active = ? WHERE id = ?`)
      .bind(body.active ? 1 : 0, empId)
      .run();
  }
  if ("costCenter" in body) {
    await c.env.DB.prepare(`UPDATE company_employees SET cost_center = ? WHERE id = ?`)
      .bind(body.costCenter ?? null, empId)
      .run();
  }
  if ("spendLimitMonth" in body) {
    await c.env.DB.prepare(`UPDATE company_employees SET spend_limit_month = ? WHERE id = ?`)
      .bind(body.spendLimitMonth ?? 0, empId)
      .run();
  }
  return c.json({ ok: true });
});

// Monthly invoice generation — admin triggers manually or via cron
companyRoutes.post("/admin/:id/invoice", async (c) => {
  const companyId = c.req.param("id");
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString();
  const end = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

  const summary = await c.env.DB.prepare(
    `SELECT COUNT(*) AS trips, COALESCE(SUM(COALESCE(final_fare, estimated_fare, 0)), 0) AS total
     FROM trips WHERE company_id = ? AND billed_to_company = 1
     AND created_at >= ? AND created_at < ?`,
  )
    .bind(companyId, start, end)
    .first<{ trips: number; total: number }>();
  if (!summary) return c.json({ error: "Summary failed", code: "INTERNAL" }, 500);

  const invoiceId = id("inv");
  await c.env.DB.prepare(
    `INSERT INTO company_invoices
      (id, company_id, period_start, period_end, total_trips, total_amount, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'issued', datetime('now'))`,
  )
    .bind(invoiceId, companyId, start, end, summary.trips, summary.total)
    .run();

  // Mark all the trips in the period as billed (so they aren't double-counted)
  await c.env.DB.prepare(
    `UPDATE trips SET billed_to_company = 0 WHERE company_id = ? AND created_at >= ? AND created_at < ?`,
  )
    .bind(companyId, start, end)
    .run();

  await logAudit(c.env.DB, {
    actorId: c.get("user").id,
    action: "company.invoice.issue",
    entityType: "company_invoice",
    entityId: invoiceId,
  });
  return c.json({ ok: true, invoiceId, trips: summary.trips, total: summary.total });
});

companyRoutes.get("/admin/:id/invoices", async (c) => {
  const res = await c.env.DB.prepare(
    `SELECT * FROM company_invoices WHERE company_id = ? ORDER BY created_at DESC`,
  )
    .bind(c.req.param("id"))
    .all();
  return c.json({ invoices: res.results ?? [] });
});

// Company admin dashboard — limited view for the company contact
companyRoutes.use("/portal/*", authMiddleware);
companyRoutes.get("/portal/invoices", async (c) => {
  const user = c.get("user");
  const emp = await c.env.DB.prepare(
    `SELECT company_id FROM company_employees WHERE user_id = ? AND active = 1 LIMIT 1`,
  )
    .bind(user.id)
    .first<{ company_id: string }>();
  if (!emp) return c.json({ error: "لا تملك صلاحية بوابة الشركة", code: "NO_COMPANY" }, 403);
  const res = await c.env.DB.prepare(
    `SELECT * FROM company_invoices WHERE company_id = ? ORDER BY created_at DESC`,
  )
    .bind(emp.company_id)
    .all();
  const trips = await c.env.DB.prepare(
    `SELECT id, COALESCE(final_fare, estimated_fare, 0) AS fare,
            pickup_address, dropoff_address, cost_center,
            datetime(created_at) AS created_at, status
     FROM trips WHERE company_id = ? ORDER BY created_at DESC LIMIT 100`,
  )
    .bind(emp.company_id)
    .all();
  return c.json({ invoices: res.results ?? [], trips: trips.results ?? [] });
});