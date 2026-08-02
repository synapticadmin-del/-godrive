// E08 verification harness — chat-20260802-0506-3804
//
// Runs the REAL apps/api/src/lib/{money,settlement,audit,log,utils}.ts from a
// repository checkout against a REAL SQLite database with every repository
// migration applied, through a D1Database shim over node:sqlite. Nothing is
// mocked and nothing is copied: it imports the shipped files.
//
//   GODRIVE_ROOT=/path/to/-godrive \
//     node --experimental-strip-types --experimental-loader ./loader.mjs harness.ts
//
// Requires Node >= 22 (node:sqlite + native type stripping). Result at the time
// of writing, against exec/08-settlement-money-primitive: 69 passed, 0 failed.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { resolve as resolvePath } from "node:path";
import { D1 } from "./d1shim.mjs";

// Point this at a checkout that has E08's branch (or main, once merged).
//   GODRIVE_ROOT=/path/to/-godrive node --experimental-strip-types \
//     --experimental-loader ./loader.mjs harness.ts
const ROOT = resolvePath(
  process.env.GODRIVE_ROOT ?? new URL("../../../../", import.meta.url).pathname,
);
const LIB = `${ROOT}/apps/api/src/lib`;
const MIG_DIR = `${ROOT}/migrations/`;

for (const p of [`${LIB}/settlement.ts`, `${LIB}/money.ts`, MIG_DIR]) {
  if (!existsSync(p)) {
    console.error(`not found: ${p}\nSet GODRIVE_ROOT to a checkout of the repository.`);
    process.exit(2);
  }
}

const { moveMoney } = await import(pathToFileURL(`${LIB}/money.ts`).href);
const { resolveTripSettlement, settleTripCompletion } = await import(
  pathToFileURL(`${LIB}/settlement.ts`).href
);

let pass = 0;
let fail = 0;
const failures: string[] = [];

function ok(name: string, cond: boolean, detail = "") {
  if (cond) {
    pass++;
    console.log(`  \x1b[32m✓\x1b[0m ${name}`);
  } else {
    fail++;
    failures.push(name + (detail ? ` — ${detail}` : ""));
    console.log(`  \x1b[31m✗ ${name}\x1b[0m ${detail}`);
  }
}
function eq(name: string, actual: unknown, expected: unknown) {
  ok(name, Object.is(actual, expected), `got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`);
}
function section(t: string) {
  console.log(`\n\x1b[1m${t}\x1b[0m`);
}

function freshDb() {
  const db = new D1(":memory:");
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith(".sql")).sort();
  for (const f of files) db.exec(readFileSync(MIG_DIR + f, "utf8"));
  return { db, migrations: files.length };
}

async function seedUser(db: any, id: string, role: string, balanceEgp: number) {
  await db
    .prepare(`INSERT INTO users (id, email, name, role) VALUES (?, ?, ?, ?)`)
    .bind(id, `${id}@test.io`, id, role)
    .run();
  await db
    .prepare(`UPDATE users SET wallet_balance = ?, wallet_balance_piastres = ? WHERE id = ?`)
    .bind(balanceEgp, Math.round(balanceEgp * 100), id)
    .run();
}

async function balance(db: any, id: string): Promise<number> {
  const r = await db.prepare(`SELECT wallet_balance AS b FROM users WHERE id = ?`).bind(id).first();
  return r ? Number(r.b) : NaN;
}
async function balPiastres(db: any, id: string): Promise<number> {
  const r = await db.prepare(`SELECT wallet_balance_piastres AS b FROM users WHERE id = ?`).bind(id).first();
  return r ? Number(r.b) : NaN;
}
async function txnCount(db: any, where = "1=1"): Promise<number> {
  const r = await db.prepare(`SELECT COUNT(*) AS n FROM wallet_transactions WHERE ${where}`).first();
  return Number(r.n);
}

async function seedTrip(db: any, o: Record<string, any>) {
  const cols = {
    id: "t1",
    rider_id: "u_rider",
    captain_id: "u_captain",
    status: "in_progress",
    city: "cairo",
    pickup_lat: 30.04,
    pickup_lng: 31.23,
    dropoff_lat: 30.01,
    dropoff_lng: 31.2,
    currency: "EGP",
    payment_method: "cash",
    estimated_fare: 100,
    offered_price: null,
    accepted_price: null,
    final_fare: null,
    commission: 20,
    ...o,
  };
  const keys = Object.keys(cols);
  await db
    .prepare(
      `INSERT INTO trips (${keys.join(", ")}) VALUES (${keys.map(() => "?").join(", ")})`,
    )
    .bind(...keys.map((k) => (cols as any)[k]))
    .run();
  return await db.prepare(`SELECT * FROM trips WHERE id = ?`).bind(cols.id).first();
}

// ═══════════════════════════════════════════════════════════════════════════
const boot = freshDb();
console.log(`\x1b[1mE08 verification\x1b[0m — ${boot.migrations} migrations applied to fresh SQLite\n`);

// ── A. Price resolution — pure, no database ────────────────────────────────
section("A. resolveTripSettlement — the F-05-01 fix");
{
  const base = { estimated_fare: 100, commission: 20 } as any;

  const a1 = resolveTripSettlement({ ...base, offered_price: 150 });
  eq("A1 offered_price (150) beats estimated_fare (100)", a1.agreedPrice, 150);
  eq("A1 price source", a1.priceSource, "offered_price");

  const a2 = resolveTripSettlement({ ...base, offered_price: 150, accepted_price: 130 });
  eq("A2 accepted_price (130) beats offered_price (150)", a2.agreedPrice, 130);
  eq("A2 price source", a2.priceSource, "accepted_price");

  const a3 = resolveTripSettlement({ ...base });
  eq("A3 no offer → estimated_fare", a3.agreedPrice, 100);
  eq("A3 price source", a3.priceSource, "estimated_fare");

  eq("A4 commission rescaled at booking rate (20% of 150)", a1.commission, 30);
  eq("A4 commission source", a1.commissionSource, "rescaled");
  eq("A4 captain payout = 150 − 30", a1.captainPayout, 120);

  eq("A5 bid path keeps its stored commission", a2.commission, 20);
  eq("A5 commission source", a2.commissionSource, "stored");

  const a6 = resolveTripSettlement({ ...base, offered_price: 100 });
  eq("A6 offered == estimated → no drift in price", a6.agreedPrice, 100);
  eq("A6 offered == estimated → no drift in commission", a6.commission, 20);

  const a7 = resolveTripSettlement({ estimated_fare: 50, commission: 999, offered_price: null } as any);
  ok("A7 payout never negative", a7.captainPayout >= 0, `got ${a7.captainPayout}`);
  ok("A7 commission never exceeds fare", a7.commission <= a7.agreedPrice);

  const a8 = resolveTripSettlement({} as any);
  eq("A8 nothing priced → 0", a8.agreedPrice, 0);
  eq("A8 source none", a8.priceSource, "none");

  // The exact chain trips.ts:873 uses today, for contrast.
  const t = { estimated_fare: 100, commission: 20, offered_price: 150 } as any;
  const oldWay = t.accepted_price ?? t.final_fare ?? t.estimated_fare ?? 0;
  eq("A9 old chain settles 100 on the same row (the bug)", oldWay, 100);
  eq("A9 new chain settles 150", resolveTripSettlement(t).agreedPrice, 150);
}

// ── B. moveMoney against real SQLite ───────────────────────────────────────
section("B. moveMoney — the one primitive");
{
  const { db } = freshDb();
  await seedUser(db, "u_a", "captain", 100);

  const c1 = await moveMoney({
    db: db as any, userId: "u_a", type: "commission", direction: "credit",
    amount: 25, idempotencyKey: "k_credit_1",
  });
  ok("B1 credit moved", c1.moved);
  eq("B1 balance 100 → 125", await balance(db, "u_a"), 125);
  eq("B1 piastres in step", await balPiastres(db, "u_a"), 12500);

  const c2 = await moveMoney({
    db: db as any, userId: "u_a", type: "commission", direction: "credit",
    amount: 25, idempotencyKey: "k_credit_1",
  });
  ok("B2 retry refused", !c2.moved);
  eq("B2 reason", c2.reason, "duplicate");
  eq("B2 balance unchanged on retry", await balance(db, "u_a"), 125);
  eq("B2 exactly one ledger row for the key", await txnCount(db, "idempotency_key = 'k_credit_1'"), 1);

  const d1 = await moveMoney({
    db: db as any, userId: "u_a", type: "commission", direction: "debit",
    amount: 500, idempotencyKey: "k_debit_big", floor: 0,
  });
  ok("B3 debit past the floor refused", !d1.moved);
  eq("B3 reason", d1.reason, "insufficient_funds");
  eq("B3 balance untouched", await balance(db, "u_a"), 125);
  eq("B3 no ledger row written", await txnCount(db, "idempotency_key = 'k_debit_big'"), 0);

  const d2 = await moveMoney({
    db: db as any, userId: "u_a", type: "commission", direction: "debit",
    amount: 125, idempotencyKey: "k_debit_exact", floor: 0,
  });
  ok("B4 debit to exactly the floor allowed", d2.moved);
  eq("B4 balance 125 → 0", await balance(db, "u_a"), 0);

  const z = await moveMoney({
    db: db as any, userId: "u_a", type: "adjustment", direction: "credit",
    amount: 0, idempotencyKey: "k_zero",
  });
  ok("B5 zero amount refused", !z.moved);
  eq("B5 reason", z.reason, "non_positive_amount");

  const ghost = await moveMoney({
    db: db as any, userId: "nobody", type: "adjustment", direction: "credit",
    amount: 10, idempotencyKey: "k_ghost",
  });
  ok("B6 move against a missing user refused", !ghost.moved);

  // Float safety: 0.1 * 3 style drift must not defeat the floor.
  await seedUser(db, "u_f", "captain", 10);
  const f = await moveMoney({
    db: db as any, userId: "u_f", type: "commission", direction: "debit",
    amount: 10, idempotencyKey: "k_float", floor: 0,
  });
  ok("B7 integer-piastre floor allows an exact-balance debit", f.moved);
  eq("B7 balance exactly 0", await balance(db, "u_f"), 0);
}

// ── C. The double-debit the old rider path had ─────────────────────────────
section("C. Retry safety — the bug the old order had");
{
  const { db } = freshDb();
  await seedUser(db, "u_old", "rider", 500);
  await seedUser(db, "u_new", "rider", 500);

  // Faithful replay of the pre-E08 rider debit: UPDATE first, INSERT second.
  async function oldRiderDebit() {
    const r = await db
      .prepare(
        `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres,0) - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
      )
      .bind(100, 10000, new Date().toISOString(), "u_old", 100)
      .run();
    const status = r.meta && r.meta.changes === 1 ? "settled" : "failed";
    await db
      .prepare(
        `INSERT OR IGNORE INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, trip_id, idempotency_key, note, status, created_at)
         VALUES (?, ?, 'trip_payment', 'debit', ?, ?, NULL, ?, ?, ?, datetime('now'))`,
      )
      .bind("wt_" + Math.random(), "u_old", 100, 10000, "trip_debit:tX", "n", status)
      .run();
  }

  await oldRiderDebit();
  eq("C1 old path, first call: 500 → 400", await balance(db, "u_old"), 400);
  await oldRiderDebit();
  eq("C1 old path, RETRY double-debits: 400 → 300", await balance(db, "u_old"), 300);
  eq("C1 …while the ledger still shows one row", await txnCount(db, "idempotency_key = 'trip_debit:tX'"), 1);

  for (let i = 0; i < 2; i++) {
    await moveMoney({
      db: db as any, userId: "u_new", type: "trip_payment", direction: "debit",
      amount: 100, idempotencyKey: "trip_debit:tY", floor: 0,
    });
  }
  eq("C2 moveMoney under the same retry: 500 → 400 once", await balance(db, "u_new"), 400);
  eq("C2 one ledger row", await txnCount(db, "idempotency_key = 'trip_debit:tY'"), 1);
}

// ── D. settleTripCompletion end to end ─────────────────────────────────────
section("D. settleTripCompletion — against the real schema");
{
  // D1: cash, captain can pay the commission.
  const { db } = freshDb();
  await seedUser(db, "u_rider", "rider", 0);
  await seedUser(db, "u_captain", "captain", 200);
  const trip = await seedTrip(db, { payment_method: "cash", estimated_fare: 100, commission: 20 });

  const out = await settleTripCompletion({ db: db as any, trip: trip as any, tripId: "t1" });
  eq("D1 cash: commission debited", await balance(db, "u_captain"), 180);
  ok("D1 captain move landed", out.captainMove?.moved === true);
  eq("D1 no rider leg on a cash trip", out.riderDebit, undefined);

  const again = await settleTripCompletion({ db: db as any, trip: trip as any, tripId: "t1" });
  eq("D6 settling twice does not move again", await balance(db, "u_captain"), 180);
  eq("D6 second call reports duplicate", again.captainMove?.reason, "duplicate");
}
{
  // D2: cash, captain too poor — floor holds, nothing goes negative.
  const { db } = freshDb();
  await seedUser(db, "u_rider", "rider", 0);
  await seedUser(db, "u_captain", "captain", 5);
  const trip = await seedTrip(db, { payment_method: "cash", estimated_fare: 100, commission: 20 });

  const out = await settleTripCompletion({ db: db as any, trip: trip as any, tripId: "t1" });
  eq("D2 balance NOT driven negative", await balance(db, "u_captain"), 5);
  ok("D2 flagged uncollected", out.commissionUncollected === true);
  eq("D2 failure recorded in the ledger", await txnCount(db, "status = 'failed'"), 1);
  eq("D2 no settled commission row", await txnCount(db, "status = 'settled' AND type = 'commission'"), 0);
}
{
  // D3: wallet, rider cannot pay — the mint must not happen.
  const { db } = freshDb();
  await seedUser(db, "u_rider", "rider", 10);
  await seedUser(db, "u_captain", "captain", 0);
  const trip = await seedTrip(db, {
    payment_method: "wallet", estimated_fare: 100, commission: 20, billed_to_company: 0,
  });

  const out = await settleTripCompletion({ db: db as any, trip: trip as any, tripId: "t1" });
  eq("D3 rider not debited below floor", await balance(db, "u_rider"), 10);
  ok("D3 credit withheld", out.creditWithheld === true);
  eq("D3 captain NOT credited — the mint refused", await balance(db, "u_captain"), 0);
  eq("D3 no payout row", await txnCount(db, "idempotency_key = 'trip_payout:t1'"), 0);
  eq("D3 failed debit recorded under its own key", await txnCount(db, "idempotency_key = 'trip_debit_failed:t1'"), 1);
  eq("D3 the real debit key stays free for a retry", await txnCount(db, "idempotency_key = 'trip_debit:t1'"), 0);
}
{
  // D4: wallet, rider can pay — both legs move.
  const { db } = freshDb();
  await seedUser(db, "u_rider", "rider", 500);
  await seedUser(db, "u_captain", "captain", 0);
  const trip = await seedTrip(db, {
    payment_method: "wallet", estimated_fare: 100, commission: 20, billed_to_company: 0,
  });

  const out = await settleTripCompletion({ db: db as any, trip: trip as any, tripId: "t1" });
  eq("D4 rider debited", await balance(db, "u_rider"), 400);
  eq("D4 captain credited the payout", await balance(db, "u_captain"), 80);
  ok("D4 nothing withheld", out.creditWithheld === false);

  const aud = await db
    .prepare(`SELECT action, entity_id, payload FROM audit_log WHERE action = 'trip.settled'`)
    .first();
  ok("D5 audit row written on the money path", !!aud);
  eq("D5 audit entity", aud?.entity_id, "t1");
  ok("D5 audit payload carries the price source", String(aud?.payload).includes("priceSource"));
}
{
  // D7: the shape E09 will call — omit finalFare, settle the agreed price.
  const { db } = freshDb();
  await seedUser(db, "u_rider", "rider", 0);
  await seedUser(db, "u_captain", "captain", 500);
  const trip = await seedTrip(db, {
    payment_method: "cash", estimated_fare: 100, offered_price: 150, commission: 20,
  });

  const out = await settleTripCompletion({ db: db as any, trip: trip as any, tripId: "t1" });
  eq("D7 settles the offered price, not the estimate", out.settledPrice, 150);
  eq("D7 commission rescaled to 20% of 150", out.commission, 30);
  eq("D7 captain debited 30, not 20", await balance(db, "u_captain"), 470);

  // And the shape trips.ts uses TODAY — caller wins, mismatch is surfaced.
  const { db: db2 } = freshDb();
  await seedUser(db2, "u_rider", "rider", 0);
  await seedUser(db2, "u_captain", "captain", 500);
  const trip2 = await seedTrip(db2, {
    payment_method: "cash", estimated_fare: 100, offered_price: 150, commission: 20,
  });
  const legacy = await settleTripCompletion({
    db: db2 as any, trip: trip2 as any, tripId: "t1",
    finalFare: 100, commission: 20, captainPayout: 80,
  });
  eq("D8 today's caller still settles its own number (unchanged behaviour)", legacy.settledPrice, 100);
  eq("D8 …and the agreed price is reported alongside it", legacy.agreedPrice, 150);
  eq("D8 captain debited the caller's 20", await balance(db2, "u_captain"), 480);
}

// ═══════════════════════════════════════════════════════════════════════════
console.log(`\n${"─".repeat(60)}`);
console.log(`\x1b[1m${pass} passed, ${fail} failed\x1b[0m`);
if (fail) {
  console.log("\nFailures:");
  for (const f of failures) console.log("  • " + f);
  process.exit(1);
}
