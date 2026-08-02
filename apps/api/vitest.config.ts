/**
 * E19 — the API test runner.
 *
 * `@cloudflare/vitest-pool-workers` runs each test *inside* `workerd`, against
 * the same bindings `wrangler.toml` declares: real D1, real KV, real R2, real
 * Durable Objects. That is the point. A Node approximation of D1 would not have
 * caught either of the two bugs this suite pins down, because both of them are
 * properties of the SQL — `meta.changes` on a guarded `UPDATE`, and a `UNIQUE`
 * index refusing a second insert.
 *
 * E01 added the `@cloudflare/vitest-pool-workers` devDependency and the `test`
 * script (`vitest run`) to `apps/api/package.json`; this file is the other half.
 *
 * ## Two things a reader should know
 *
 * 1. **Migrations are read from the repository, not from a fixture.** The suite
 *    applies `migrations/*.sql` — all of them, in order — to a fresh D1 for the
 *    run. A test that passes against a hand-written schema proves nothing about
 *    the schema that ships.
 * 2. **`isolatedStorage` is on.** Every test gets the migrated database back in
 *    its post-migration state, so the accept-race test cannot be made to pass by
 *    a row some earlier test left behind.
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  defineWorkersConfig,
  readD1Migrations,
} from "@cloudflare/vitest-pool-workers/config";

const HERE = path.dirname(fileURLToPath(import.meta.url));

export default defineWorkersConfig(async () => {
  // The real migration directory, as wrangler.toml points at it.
  const migrations = await readD1Migrations(path.join(HERE, "..", "..", "migrations"));

  return {
    test: {
      // Only *.test.ts. `test/tools/` holds the dependency-free evidence
      // harness, which is run by hand and must not be collected here.
      include: ["test/**/*.test.ts"],
      setupFiles: ["./test/setup.ts"],
      poolOptions: {
        workers: {
          // One worker: these tests are ordering-sensitive by nature and there
          // is no wall-clock win worth a flaky money test.
          singleWorker: true,
          isolatedStorage: true,
          wrangler: { configPath: "./wrangler.toml" },
          miniflare: {
            // Consumed by test/setup.ts.
            bindings: {
              TEST_MIGRATIONS: migrations,
              // A signing secret that exists only in the test runtime. The real
              // one is a wrangler secret and is never in the repository.
              JWT_SECRET: "e19-test-signing-secret-not-a-real-key",
              JWT_ISSUER: "synaptic-go",
              DEFAULT_CITY: "cairo",
              // Deliberately unroutable. Nothing in this suite may reach OSRM;
              // if a test ever does, it fails loudly instead of silently
              // depending on a third party being up.
              OSRM_URL: "http://osrm.invalid",
            },
          },
        },
      },
    },
  };
});
