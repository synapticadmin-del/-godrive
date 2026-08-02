/**
 * Applies the repository's real migrations to the test D1 before any test runs.
 *
 * `applyD1Migrations` is idempotent per storage generation, and with
 * `isolatedStorage: true` every test starts from this state.
 */
import { applyD1Migrations, env } from "cloudflare:test";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
