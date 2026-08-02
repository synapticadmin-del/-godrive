/**
 * e19_adopt_invoices.mjs — behavioural proof for E07's invoice-cron shutdown.
 *
 * Parked here rather than in `apps/api/test/` on purpose: that directory and
 * `apps/api/vitest.config.ts` are **E19's** `owns:`, and PROTOCOL-EXEC §4 says a
 * task that needs a file it does not own says so instead of reaching for it.
 * `ci.yml` also does not run `npm test -w @synaptic-go/api` today, so a vitest
 * file added during wave 1 would execute nowhere (WAVE-PLAN §9). Same shape as
 * the drafts E08 left at `e19_adopt_settlement.test.ts`.
 *
 * ## What it proves
 *
 * It imports the **real** `apps/api/src/cron/invoices.ts` — not a copy, not a
 * mock of the module under test — against the real `lib/log.ts` and
 * `lib/utils.ts` (both have zero imports), against a real SQLite database with
 * every migration in `migrations/` applied, through a D1 shim.
 *
 *   A. the disabled job writes nothing and mutates nothing
 *   B. it still emits `cron.heartbeat`, so the dead-man switch stays alive
 *   C. the collapsed generator, once the guard is deleted, does not re-bill
 *   D. it settles exactly the rows it counted, and nothing outside the period
 *
 * ## Running it
 *
 *     node board/exec/drafts/e19_adopt_invoices.mjs
 *
 * from anywhere inside a checkout. Needs Node >= 22.18 for `node:sqlite` and
 * for TypeScript type-stripping; no npm install, no network. Exit code is the
 * failure count.
 *
 * ## For whoever adopts it into E19
 *
 * The assertions port to vitest unchanged — `eq()` becomes `expect().toEqual()`.
 * Under `@cloudflare/vitest-pool-workers` you get a real D1 binding and can drop
 * the shim and the loader hook entirely; keep `freshDb`'s migration walk, since
 * applying `migrations/` in filename order is what makes the timestamp
 * assertions meaningful. The one thing worth preserving verbatim is section A:
 * it is the regression guard on the guard itself, and it fails loudly the moment
 * someone deletes the block in `runMonthlyInvoiceJob` without doing the four
 * things the module comment lists.
 */
import { register } from "node:module";
import { DatabaseSync } from "node:sqlite";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve as presolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// The API compiles with moduleResolution "Bundler", so its relative imports
// carry no extension and Node's resolver needs one added. Registered from a
// data: URL to keep this file self-contained.
register(
  "data:text/javascript," +
    encodeURIComponent(`
      import { existsSync } from "node:fs";
      import { fileURLToPath } from "node:url";
      export async function resolve(spec, ctx, next) {
        if (spec.startsWith(".")) {
          try { return await next(spec, ctx); }
          catch (e) {
            const c = new URL(spec + ".ts", ctx.parentURL);
            if (existsSync(fileURLToPath(c)))
              return { url: c.href, format: "module-typescript", shortCircuit: true };
            throw e;
          }
        }
        return next(spec, ctx);
      }`),
);

// ── locate the checkout ──────────────────────────────────────────────────────
function repoRoot() {
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 8; i++) {
    if (existsSync(join(dir, "migrations")) && existsSync(join(dir, "apps", "api"))) return dir;
    dir = presolve(dir, "..");
  }
  throw new Error("could not find the repository root (expected migrations/ and apps/api/)");
}
const ROOT = repoRoot();
const MIG = join(ROOT, "migrations");
const TARGET = join(ROOT, "apps", "api", "src", "cron", "invoices.ts");

let checks = 0;
const failures = [];
const eq = (label, got, want) => {
  checks++;
  const ok = JSON.stringify(got) === JSON.stringify(want);
  // stderr: console.* is hijacked below to capture the module's own log lines
  process.stderr.write(
    `  ${ok ? "PASS" : "FAIL"}  ${label}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}\n`,
  );
  if (!ok) failures.push(label);
};

// ── a D1Database shim over node:sqlite ───────────────────────────────────────
function d1(db) {
  return {
    prepare(sql) {
      const mk = (args) => ({
        bind: (...a) => mk(a),
        first: async () => {
          const r = db.prepare(sql).get(...args);
          return r === undefined ? null : r;
        },
        all: async () => ({ results: db.prepare(sql).all(...args), success: true }),
        run: async () => {
          const info = db.prepare(sql).run(...args);
          return { success: true, meta: { changes: Number(info.changes ?? 0) } };
        },
      });
      return mk([]);
    },
  };
}

function freshDb() {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys=ON");
  const names = readdirSync(MIG).filter((f) => f.endsWith(".sql")).sort();
  for (const n of names) db.exec(readFileSync(join(MIG, n), "utf8"));
  return { db, n: names.length };
}

/** One active company; two billable July trips — one on the 1st, one mid-month.
 *  `created_at` is written the way the table default writes it, which is the
 *  whole point: 'YYYY-MM-DD HH:MM:SS', not an ISO string. */
function seed(db) {
  db.exec(
    "INSERT INTO users (id,email,phone,role,name)" +
      " VALUES ('u_rider','rider@acme.test','+201000000001','rider','R')",
  );
  db.exec("INSERT INTO companies (id,name,status,created_at) VALUES ('c1','Acme','active',datetime('now'))");
  for (const [tid, created, fare] of [
    ["trip_first", "2026-07-01 09:15:00", 100.0],
    ["trip_mid", "2026-07-15 12:00:00", 250.0],
  ]) {
    db.prepare(
      "INSERT INTO trips (id,rider_id,status,city,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng," +
        "estimated_fare,final_fare,company_id,billed_to_company,created_at)" +
        " VALUES (?,?,'completed','cairo',30.0,31.0,30.1,31.1,?,?,'c1',1,?)",
    ).run(tid, "u_rider", fare, fare, created);
  }
}
const count = (db, sql) => db.prepare(sql).get().n;

// capture the structured lines lib/log.ts emits
const emitted = [];
for (const level of ["log", "info", "warn", "error", "debug"]) {
  console[level] = (...a) => emitted.push(a.map(String).join(" "));
}

const mod = await import(pathToFileURL(TARGET).href);

async function main() {
  const { db, n } = freshDb();
  seed(db);
  process.stderr.write(`applied ${n} migrations; running ${TARGET.replace(ROOT + "/", "")}\n\n`);

  const env = { DB: d1(db) }; // no DEADMAN_URL_* -> heartbeat logs, no HTTP
  const ctx = { waitUntil() {}, passThroughOnException() {} };

  process.stderr.write("A. the registered job, as shipped (guard in place)\n");
  const invBefore = count(db, "SELECT COUNT(*) AS n FROM company_invoices");
  const billBefore = count(db, "SELECT COUNT(*) AS n FROM trips WHERE billed_to_company=1");
  emitted.length = 0;
  // 03:00 on the 1st is exactly when the trigger fires — the one moment the old
  // code would have billed. Twice, the way the every-minute trigger used to.
  await mod.runMonthlyInvoiceJob({ env, ctx, now: "2026-08-01T03:00:00.000Z" });
  await mod.runMonthlyInvoiceJob({ env, ctx, now: "2026-08-01T03:01:00.000Z" });
  eq("invoices written by the disabled job", count(db, "SELECT COUNT(*) AS n FROM company_invoices") - invBefore, 0);
  eq(
    "billed_to_company flags mutated",
    billBefore - count(db, "SELECT COUNT(*) AS n FROM trips WHERE billed_to_company=1"),
    0,
  );

  process.stderr.write("\nB. the dead-man switch is still alive while billing is off\n");
  const beats = emitted.filter((l) => l.includes("cron.heartbeat"));
  eq("cron.heartbeat lines emitted (one per invocation)", beats.length, 2);
  eq("heartbeat names the job", beats[0].includes('"job":"company-invoices"'), true);
  eq("heartbeat reports ok", beats[0].includes('"ok":true'), true);
  eq("heartbeat says billing is disabled", beats[0].includes('"billing":"disabled"'), true);
  eq("heartbeat carries the finding ids", beats[0].includes("F-08-01"), true);

  process.stderr.write("\nC. the collapsed generator (guard deleted) does not re-bill\n");
  const period = mod.previousUtcMonth("2026-08-01T03:00:00.000Z");
  eq("period is the previous whole UTC month, not 'now'", [period.start, period.end], [
    "2026-07-01T00:00:00.000Z",
    "2026-08-01T00:00:00.000Z",
  ]);
  const r1 = await mod.generateCompanyInvoice(env.DB, "c1", period);
  eq("first run invoices both trips", [r1.trips, r1.total], [2, 350]);
  eq("second run finds nothing left to bill", await mod.generateCompanyInvoice(env.DB, "c1", period), null);
  eq("third run likewise", await mod.generateCompanyInvoice(env.DB, "c1", period), null);
  eq("invoices on file after three runs", count(db, "SELECT COUNT(*) AS n FROM company_invoices"), 1);
  eq(
    "total billed equals the trips that happened",
    db.prepare("SELECT COALESCE(SUM(total_amount),0) AS n FROM company_invoices").get().n,
    350,
  );

  process.stderr.write("\nD. it settles exactly the rows it counted\n");
  eq(
    "rows left marked billable in the period",
    count(db, "SELECT COUNT(*) AS n FROM trips WHERE billed_to_company=1 AND company_id='c1'"),
    0,
  );
  eq(
    "the first-day trip specifically was settled",
    db.prepare("SELECT billed_to_company AS n FROM trips WHERE id='trip_first'").get().n,
    0,
  );
  const { db: db2 } = freshDb();
  seed(db2);
  db2
    .prepare(
      "INSERT INTO trips (id,rider_id,status,city,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng," +
        "estimated_fare,final_fare,company_id,billed_to_company,created_at)" +
        " VALUES ('trip_next','u_rider','completed','cairo',30,31,30.1,31.1,99,99,'c1',1,'2026-08-01 10:00:00')",
    )
    .run();
  const r4 = await mod.generateCompanyInvoice(d1(db2), "c1", period);
  eq("August trip excluded from the July invoice", [r4.trips, r4.total], [2, 350]);
  eq(
    "August trip still billable",
    db2.prepare("SELECT billed_to_company AS n FROM trips WHERE id='trip_next'").get().n,
    1,
  );

  process.stderr.write(`\n${checks} assertions, ${failures.length} failures\n`);
  if (failures.length) process.stderr.write("FAILED: " + failures.join(", ") + "\n");
  return failures.length;
}

process.exitCode = await main();
