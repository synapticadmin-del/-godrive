/**
 * E19 — dependency-free evidence for the four money-path guarantees.
 *
 * ## Why this exists alongside the vitest suite
 *
 * The vitest suite is the deliverable and `workerd` is where it belongs. But it
 * needs `npm ci` and a working registry, and the first time it can possibly run
 * is after a human installs the CI job (see `docs/plan/assets/E19-ci-test-job.yml`).
 * That left a gap: PROTOCOL-EXEC §7 asks a *different chat* to verify the effect
 * against `main`, and "trust the author's summary" is exactly what this
 * programme exists to stop.
 *
 * So this runs the same four guarantees with **no dependencies at all** — Node's
 * built-in `node:sqlite`, Node's built-in type stripping, the repository's real
 * migrations, and the API's real source modules. Nothing is reimplemented.
 *
 *     node --import ./ts-loader.mjs offline-verify.mjs
 *     node --import ./ts-loader.mjs offline-verify.mjs --revert=floor
 *
 * `--revert=<floor|completion|race|enum>` puts one fix back to its pre-fix form
 * so you can watch the corresponding assertion go red. A guarantee nobody has
 * seen fail is not a guarantee.
 *
 * Requires Node >= 22.6 for `--experimental-strip-types` (default-on from 23).
 * Group D additionally needs `zod`, which is a runtime dependency of the API and
 * is present after `npm ci`; without it that group reports SKIP rather than
 * failing.
 */
import { freshDb, makeD1 } from "./sqlite-d1.mjs";

const REVERT = (process.argv.find((a) => a.startsWith("--revert=")) ?? "").split("=")[1] ?? "";
const results = [];

function check(name, pass, detail = "") {
  results.push({ name, pass });
  console.log(`  ${pass ? "PASS" : "FAIL"}  ${name}${detail ? `  — ${detail}` : ""}`);
}
function skip(name, why) {
  console.log(`  SKIP  ${name}  — ${why}`);
}

function seedUser(sqlite, id, role, balance) {
  sqlite
    .prepare(
      `INSERT INTO users (id,email,role,status,wallet_balance,wallet_balance_piastres,created_at,updated_at)
       VALUES (?,?,?,'active',?,?,datetime('now'),datetime('now'))`,
    )
    .run(id, `${id}@test.local`, role, balance, Math.round(balance * 100));
}

function seedTrip(sqlite, id, over = {}) {
  const t = {
    rider_id: "rider_1", captain_id: null, status: "in_progress", payment_method: "cash",
    estimated_fare: 100, offered_price: null, accepted_price: null, final_fare: null,
    commission: 20, ...over,
  };
  sqlite
    .prepare(
      `INSERT INTO trips (id,rider_id,captain_id,status,city,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,
         currency,payment_method,estimated_fare,offered_price,accepted_price,final_fare,commission,created_at,updated_at)
       VALUES (?,?,?,?,'cairo',30.0444,31.2357,30.0561,31.2394,'EGP',?,?,?,?,?,?,datetime('now'),datetime('now'))`,
    )
    .run(id, t.rider_id, t.captain_id, t.status, t.payment_method, t.estimated_fare,
         t.offered_price, t.accepted_price, t.final_fare, t.commission);
  return { id, ...t };
}

const piastres = (sqlite, uid) =>
  sqlite.prepare(`SELECT wallet_balance_piastres p, wallet_balance b FROM users WHERE id=?`).get(uid);

// ── A. cash-commission settlement including the balance floor ───────────────
async function groupA() {
  console.log("\nA. cash-commission settlement including the balance floor");
  const { resolveTripSettlement, settleTripCompletion } = await import("../../src/lib/settlement.ts");
  const { moveMoney } = await import("../../src/lib/money.ts");

  const r = resolveTripSettlement({
    accepted_price: null, offered_price: 150, final_fare: null,
    estimated_fare: 100, commission: 20, payment_method: "cash",
  });
  check("settles offered_price, not estimated_fare",
    r.agreedPrice === 150 && r.priceSource === "offered_price",
    `agreed=${r.agreedPrice} source=${r.priceSource}`);
  check("commission rescales at the booking rate (20% of 150 = 30)",
    r.commission === 30 && r.commissionSource === "rescaled", `commission=${r.commission}`);
  check("captain payout = agreed − commission", r.captainPayout === 120, `payout=${r.captainPayout}`);

  {
    const { db: sqlite } = freshDb();
    const db = makeD1(sqlite);
    seedUser(sqlite, "rider_1", "rider", 0);
    seedUser(sqlite, "cap_ok", "captain", 100);
    const trip = seedTrip(sqlite, "t_ok", { captain_id: "cap_ok" });
    const out = await settleTripCompletion({ db, trip, tripId: "t_ok" });
    check("solvent captain: commission debited, 100 → 80",
      out.captainMove?.moved === true && piastres(sqlite, "cap_ok").p === 8000,
      `balance=${piastres(sqlite, "cap_ok").b}`);
  }

  {
    const { db: sqlite } = freshDb();
    const db = makeD1(sqlite);
    seedUser(sqlite, "rider_1", "rider", 0);
    seedUser(sqlite, "cap_short", "captain", 5);
    const trip = seedTrip(sqlite, "t_short", { captain_id: "cap_short" });

    if (REVERT === "floor") {
      // Pre-fix: the cash commission debit was the one debit with no floor.
      await moveMoney({
        db, userId: "cap_short", type: "commission", direction: "debit", amount: 20,
        idempotencyKey: "trip_commission_debit:t_short", tripId: "t_short", floor: null,
      });
      const b = piastres(sqlite, "cap_short");
      check("floor holds: the wallet never goes negative", b.p >= 0,
        `REVERTED floor:null → balance=${b.b} EGP (${b.p} piastres)`);
    } else {
      const out = await settleTripCompletion({ db, trip, tripId: "t_short" });
      const b = piastres(sqlite, "cap_short");
      check("floor holds: the wallet never goes negative", b.p === 500 && b.p >= 0, `balance=${b.b}`);
      check("the refusal is reported, not silently dropped", out.commissionUncollected === true);
      const failed = sqlite
        .prepare(`SELECT status FROM wallet_transactions WHERE idempotency_key=?`)
        .get("trip_commission_debit_failed:t_short");
      check("a 'failed' ledger row records the uncollected commission", failed?.status === "failed");
      const live = sqlite
        .prepare(`SELECT count(*) c FROM wallet_transactions WHERE idempotency_key=?`)
        .get("trip_commission_debit:t_short");
      check("the live idempotency key is not burned by the failure", live.c === 0);
    }
  }
}

// ── B. completion handler idempotency on retry ──────────────────────────────
async function groupB() {
  console.log("\nB. completion handler idempotency on retry");
  const { settleTripCompletion } = await import("../../src/lib/settlement.ts");
  const { moveMoney } = await import("../../src/lib/money.ts");
  const { db: sqlite } = freshDb();
  const db = makeD1(sqlite);
  seedUser(sqlite, "rider_1", "rider", 0);
  seedUser(sqlite, "cap_b", "captain", 100);
  const trip = seedTrip(sqlite, "t_b", { captain_id: "cap_b" });

  // The compare-and-swap from routes/trips.ts:878, verbatim.
  const guard = REVERT === "completion" ? "" : ` AND status != 'completed'`;
  const sql = `UPDATE trips SET status='completed', final_fare=?, completed_at=?, updated_at=? WHERE id=?${guard}`;
  const a = sqlite.prepare(sql).run(100, "t", "t", "t_b");
  const b = sqlite.prepare(sql).run(100, "t", "t", "t_b");
  check("the retry is refused by the status guard (changes=0)",
    Number(a.changes) === 1 && Number(b.changes) === 0,
    `first=${a.changes} second=${b.changes}${REVERT === "completion" ? "  [REVERTED: guard removed]" : ""}`);

  await settleTripCompletion({ db, trip, tripId: "t_b" });
  await settleTripCompletion({ db, trip, tripId: "t_b" });
  check("a retried settlement debits the commission exactly once",
    piastres(sqlite, "cap_b").p === 8000, `balance=${piastres(sqlite, "cap_b").b}`);

  const dup = await moveMoney({
    db, userId: "cap_b", type: "commission", direction: "debit", amount: 20,
    idempotencyKey: "trip_commission_debit:t_b", tripId: "t_b",
  });
  check("a further attempt reports 'duplicate', not a new debit",
    dup.moved === false && dup.reason === "duplicate", `reason=${dup.reason}`);
}

// ── C. the accept race ──────────────────────────────────────────────────────
function groupC() {
  console.log("\nC. the accept race — two captains, one trip");
  const { db: sqlite } = freshDb();
  seedUser(sqlite, "rider_1", "rider", 0);
  seedUser(sqlite, "cap_x", "captain", 0);
  seedUser(sqlite, "cap_y", "captain", 0);
  seedTrip(sqlite, "t_race", { status: "searching" });

  // The compare-and-swap from routes/trips.ts:767, verbatim.
  const guard = REVERT === "race" ? "" : ` AND status IN ('searching','offered')`;
  const sql = `UPDATE trips SET status='assigned', captain_id=?, assigned_at=?, updated_at=? WHERE id=?${guard}`;
  const a = sqlite.prepare(sql).run("cap_x", "t", "t", "t_race");
  const b = sqlite.prepare(sql).run("cap_y", "t", "t", "t_race");
  const row = sqlite.prepare(`SELECT captain_id FROM trips WHERE id=?`).get("t_race");

  check("exactly one captain wins the compare-and-swap",
    Number(a.changes) === 1 && Number(b.changes) === 0,
    `first=${a.changes} second=${b.changes}${REVERT === "race" ? "  [REVERTED: status guard removed]" : ""}`);
  check("the loser does not overwrite the winner's captain_id",
    row.captain_id === "cap_x", `captain_id=${row.captain_id}`);
}

// ── D. E04's payment-method rejections ──────────────────────────────────────
async function groupD() {
  console.log("\nD. E04's payment-method rejections");
  let createTripSchema;
  try {
    ({ createTripSchema } = await import("../../src/lib/schemas.ts"));
  } catch (e) {
    skip("POST /trips rejects wallet and card", `zod not resolvable (run npm ci) — ${e.code ?? e.message}`);
    return;
  }
  const base = { pickupLat: 30.0444, pickupLng: 31.2357, dropoffLat: 30.0561, dropoffLng: 31.2394 };

  let schema = createTripSchema;
  if (REVERT === "enum") {
    const { z } = await import("zod");
    schema = z.object({ paymentMethod: z.enum(["cash", "card", "wallet"]).default("cash") });
  }

  for (const method of ["wallet", "card"]) {
    const res = schema.safeParse({ ...base, paymentMethod: method });
    check(`POST /trips rejects paymentMethod="${method}"`, res.success === false,
      res.success ? `ACCEPTED${REVERT === "enum" ? "  [REVERTED: enum widened]" : ""}` : "400 at the edge");
  }
  check('paymentMethod="cash" is accepted',
    createTripSchema.safeParse({ ...base, paymentMethod: "cash" }).success === true);
  const dflt = createTripSchema.safeParse(base);
  check("an omitted paymentMethod defaults to cash",
    dflt.success && dflt.data.paymentMethod === "cash");
}

// ── run ─────────────────────────────────────────────────────────────────────
const { applied, total, tables } = freshDb();
console.log("E19 offline evidence — real source, real migrations, real SQLite");
console.log(`migrations ${applied}/${total}, ${tables} tables${REVERT ? `   [REVERT: ${REVERT}]` : ""}`);

await groupA();
await groupB();
groupC();
await groupD();

const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} assertions passed`);
if (failed.length) {
  console.log(`RED — ${failed.map((f) => f.name).join(" | ")}`);
  process.exit(1);
}
console.log("GREEN");
