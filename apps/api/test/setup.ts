/**
 * Applies the repository's real migrations to the test D1 before any test runs.
 *
 * `applyD1Migrations` is idempotent per storage generation, and with
 * `isolatedStorage: true` every test starts from this state.
 */
import { applyD1Migrations, env } from "cloudflare:test";
import { beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM trips").run();
  await env.DB.prepare("DELETE FROM users").run();
  await env.DB.prepare("DELETE FROM captains").run();
  await env.DB.prepare("DELETE FROM wallet_transactions").run();
  await env.DB.prepare("DELETE FROM sos_alerts").run();
});

