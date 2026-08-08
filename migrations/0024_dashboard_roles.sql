-- 0024: Dashboard staff roles (RBAC).
--
-- The dashboard used to be a single flat gate: users.role = 'admin' unlocked
-- every page, from live-trip monitoring to pricing edits and payout
-- decisions. This migration adds a second, dashboard-only dimension so the
-- operator console can be shared with assistants, support and finance staff
-- without handing each of them the keys to the whole platform.
--
-- Design notes:
--  * users.role keeps its CHECK constraint ('rider','captain','admin') —
--    widening it would require rebuilding the table on production D1. Every
--    dashboard account therefore remains role = 'admin'; dashboard_role
--    scopes what that admin can touch.
--  * NULL means "not a dashboard operator" (riders and captains). The API
--    treats role = 'admin' with a NULL dashboard_role as 'owner' so any
--    account created before this migration keeps full access.
--  * The permission matrix itself lives in code (apps/api/src/lib/staff.ts),
--    not in a table: the roles are a fixed hierarchy, and a code matrix is
--    reviewable in a diff and impossible to mis-edit at runtime.

ALTER TABLE users ADD COLUMN dashboard_role TEXT;

CREATE INDEX IF NOT EXISTS idx_users_dashboard_role
  ON users (dashboard_role) WHERE dashboard_role IS NOT NULL;

-- Seed: every existing admin becomes an owner. The operator who has been
-- running the platform alone must not lose the ability to manage the new
-- roles the moment this migration lands.
UPDATE users SET dashboard_role = 'owner' WHERE role = 'admin' AND dashboard_role IS NULL;
