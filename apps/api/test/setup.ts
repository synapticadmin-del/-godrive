/**
 * Applies the repository's real migrations to the test D1 before any test runs.
 *
 * `applyD1Migrations` is idempotent per storage generation. Tests share one
 * storage generation because a few of them exercise Durable Objects, so reset
 * only their fixture rows before each test.
 */
import { applyD1Migrations, env } from "cloudflare:test";
import { beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

beforeEach(async () => {
  // Delete leaves before their parents. In particular, trip completion writes
  // audit rows that reference users without ON DELETE CASCADE; deleting users
  // first made every following test fail with a foreign-key violation.
  await env.DB.batch([
    env.DB.prepare("DELETE FROM audit_log"),
    env.DB.prepare("DELETE FROM payout_requests"),
    env.DB.prepare("DELETE FROM wallet_transactions"),
    env.DB.prepare("DELETE FROM sos_alert_events"),
    env.DB.prepare("DELETE FROM sos_alerts"),
    env.DB.prepare("DELETE FROM trips"),
    env.DB.prepare("DELETE FROM captains"),
    env.DB.prepare("DELETE FROM users"),
  ]);
});

