// DRAFT — written by E08 (chat-20260802-0506-3804) for E19 to adopt.
// NOT on `main`. Inert on the board branch, exactly like
// board/exec/drafts/e19_adopt_safety.test.ts is for E13.
//
// WHY THIS IS HERE AND NOT IN apps/api/test/
// ------------------------------------------
// E08's brief makes a test an acceptance criterion — "A captain accepting an
// offer of X is credited from X, proven by a test against the primitive". That
// test needs `apps/api/test/` and `apps/api/vitest.config.ts`, both in E19's
// `owns:` (WAVE-PLAN §8). E19 is round 5 and `depends_on: [E01, E08]`, so at the
// time this was written there was nowhere legal to put it:
//
//   * writing apps/api/test/** would lock a directory to a task nobody has
//     claimed and hand E19 its own deliverable pre-written by a stranger —
//     the boundary violation PROTOCOL-EXEC §4 exists to prevent;
//   * and it would not run anyway. ci.yml's node job runs
//     `npm test -w @synaptic-go/shared` and never invokes the api workspace's
//     test script. Wiring that up is a ci.yml edit no agent can make.
//
// So E08 proved the same behaviour against real SQLite with all 22 migrations in
// board/exec/drafts/e08_settlement_harness/ (69 assertions, 0 failures) and
// parked the runner-shaped version here.
//
// ADOPTION — for whoever claims E19
// ---------------------------------
//  1. Copy to `apps/api/test/settlement.test.ts`.
//  2. `apps/api/tsconfig.json` has `include: ["src/**/*", ...]`, which does not
//     cover `test/`. WAVE-PLAN §8 already flags this as E19's seam; tsconfig.json
//     is in no task's owns, including E08's.
//  3. §A needs no D1 at all — `resolveTripSettlement` is pure. If the workers
//     pool is still being wired, ship §A first; it is the half that closes the
//     brief's "proven by a test against the primitive".
//  4. Do not weaken §D3. That assertion is the platform declining to mint money,
//     and it is the one an accidental refactor will quietly delete.
//  5. Gate item 6 spans E08 and E09. Green here does NOT close it — E09 owns the
//     call site at `routes/trips.ts:873` that still passes its own number.

import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

import { moveMoney } from "../src/lib/money";
import {
  resolveTripSettlement,
  settleTripCompletion,
  type SettlementTrip,
} from "../src/lib/settlement";

const DB = env.DB as D1Database;

const trip = (o: Partial<SettlementTrip>): SettlementTrip =>
  ({
    id: "t1",
    rider_id: "u_rider",
    captain_id: "u_captain",
    status: "in_progress",
    city: "cairo",
    payment_method: "cash",
    estimated_fare: 100,
    commission: 20,
    ...o,
  }) as SettlementTrip;

async function seedUser(id: string, role: string, egp: number) {
  await DB.prepare(`INSERT OR REPLACE INTO users (id, email, name, role) VALUES (?, ?, ?, ?)`)
    .bind(id, `${id}@test.io`, id, role)
    .run();
  await DB.prepare(
    `UPDATE users SET wallet_balance = ?, wallet_balance_piastres = ? WHERE id = ?`,
  )
    .bind(egp, Math.round(egp * 100), id)
    .run();
}

async function seedTripRow(o: Record<string, unknown>) {
  const cols = {
    id: "t1", rider_id: "u_rider", captain_id: "u_captain", status: "in_progress",
    city: "cairo", pickup_lat: 30.04, pickup_lng: 31.23, dropoff_lat: 30.01,
    dropoff_lng: 31.2, currency: "EGP", payment_method: "cash",
    estimated_fare: 100, commission: 20, ...o,
  };
  const keys = Object.keys(cols);
  await DB.prepare(
    `INSERT OR REPLACE INTO trips (${keys.join(", ")}) VALUES (${keys.map(() => "?").join(", ")})`,
  )
    .bind(...keys.map((k) => (cols as Record<string, unknown>)[k]))
    .run();
  return (await DB.prepare(`SELECT * FROM trips WHERE id = ?`).bind(cols.id).first()) as SettlementTrip;
}

const balance = async (id: string) =>
  Number((await DB.prepare(`SELECT wallet_balance AS b FROM users WHERE id = ?`).bind(id).first<{ b: number }>())?.b);

const rows = async (where: string) =>
  Number((await DB.prepare(`SELECT COUNT(*) AS n FROM wallet_transactions WHERE ${where}`).first<{ n: number }>())?.n);

beforeEach(async () => {
  await DB.batch([
    DB.prepare(`DELETE FROM wallet_transactions`),
    DB.prepare(`DELETE FROM audit_log`),
    DB.prepare(`DELETE FROM trips`),
    DB.prepare(`DELETE FROM users`),
  ]);
});

// ───────────────────────────────────────────────────────────────────────────
describe("A. resolveTripSettlement — pure, no database", () => {
  it("settles the rider's offer, not the estimate (F-05-01)", () => {
    const r = resolveTripSettlement(trip({ offered_price: 150 }));
    expect(r.agreedPrice).toBe(150);
    expect(r.priceSource).toBe("offered_price");
  });

  it("an accepted bid outranks the rider's offer", () => {
    const r = resolveTripSettlement(trip({ offered_price: 150, accepted_price: 130 }));
    expect(r.agreedPrice).toBe(130);
    expect(r.priceSource).toBe("accepted_price");
  });

  it("falls back to the estimate when nothing was negotiated", () => {
    expect(resolveTripSettlement(trip({})).agreedPrice).toBe(100);
  });

  it("credits the captain FROM the agreed price — commission rescaled at the booking rate", () => {
    const r = resolveTripSettlement(trip({ offered_price: 150 }));
    expect(r.commission).toBe(30); // 20% of 150, not the stored 20
    expect(r.commissionSource).toBe("rescaled");
    expect(r.captainPayout).toBe(120);
  });

  it("leaves the bid path's commission alone — it was already recomputed", () => {
    const r = resolveTripSettlement(trip({ offered_price: 150, accepted_price: 130 }));
    expect(r.commission).toBe(20);
    expect(r.commissionSource).toBe("stored");
  });

  it("does not drift when the rider named no price", () => {
    // routes/trips.ts:401 sets offered_price = body.offeredPrice || finalEstimate,
    // so the common case must be byte-identical to today's behaviour.
    const r = resolveTripSettlement(trip({ offered_price: 100 }));
    expect(r.agreedPrice).toBe(100);
    expect(r.commission).toBe(20);
  });

  it("never returns a negative payout", () => {
    const r = resolveTripSettlement(trip({ estimated_fare: 50, commission: 999 }));
    expect(r.captainPayout).toBeGreaterThanOrEqual(0);
    expect(r.commission).toBeLessThanOrEqual(r.agreedPrice);
  });

  it("differs from the chain trips.ts:873 uses today", () => {
    const t = trip({ offered_price: 150 });
    const old = t.accepted_price ?? t.final_fare ?? t.estimated_fare ?? 0;
    expect(old).toBe(100);
    expect(resolveTripSettlement(t).agreedPrice).toBe(150);
  });
});

// ───────────────────────────────────────────────────────────────────────────
describe("B. moveMoney — one primitive, one balance move", () => {
  it("moves a credit and keeps the piastre column in step", async () => {
    await seedUser("u_a", "captain", 100);
    const r = await moveMoney({
      db: DB, userId: "u_a", type: "commission", direction: "credit",
      amount: 25, idempotencyKey: "k1",
    });
    expect(r.moved).toBe(true);
    expect(await balance("u_a")).toBe(125);
  });

  it("is idempotent — a retry moves nothing", async () => {
    await seedUser("u_a", "captain", 100);
    const args = {
      db: DB, userId: "u_a", type: "commission" as const, direction: "credit" as const,
      amount: 25, idempotencyKey: "k1",
    };
    await moveMoney(args);
    const second = await moveMoney(args);
    expect(second.moved).toBe(false);
    expect(second.reason).toBe("duplicate");
    expect(await balance("u_a")).toBe(125);
    expect(await rows("idempotency_key = 'k1'")).toBe(1);
  });

  it("refuses a debit that would breach the floor, and writes no ledger row", async () => {
    await seedUser("u_a", "captain", 100);
    const r = await moveMoney({
      db: DB, userId: "u_a", type: "commission", direction: "debit",
      amount: 500, idempotencyKey: "k2", floor: 0,
    });
    expect(r.moved).toBe(false);
    expect(r.reason).toBe("insufficient_funds");
    expect(await balance("u_a")).toBe(100);
    expect(await rows("idempotency_key = 'k2'")).toBe(0);
  });

  it("allows a debit to exactly the floor", async () => {
    await seedUser("u_a", "captain", 100);
    const r = await moveMoney({
      db: DB, userId: "u_a", type: "commission", direction: "debit",
      amount: 100, idempotencyKey: "k3", floor: 0,
    });
    expect(r.moved).toBe(true);
    expect(await balance("u_a")).toBe(0);
  });

  it("refuses a non-positive amount and an unknown user", async () => {
    await seedUser("u_a", "captain", 100);
    expect((await moveMoney({
      db: DB, userId: "u_a", type: "adjustment", direction: "credit",
      amount: 0, idempotencyKey: "k4",
    })).reason).toBe("non_positive_amount");
    expect((await moveMoney({
      db: DB, userId: "ghost", type: "adjustment", direction: "credit",
      amount: 10, idempotencyKey: "k5",
    })).moved).toBe(false);
  });
});

// ───────────────────────────────────────────────────────────────────────────
describe("C. settleTripCompletion", () => {
  it("takes the cash commission when the captain can cover it", async () => {
    await seedUser("u_rider", "rider", 0);
    await seedUser("u_captain", "captain", 200);
    const t = await seedTripRow({ payment_method: "cash" });

    await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    expect(await balance("u_captain")).toBe(180);
  });

  it("cannot drive a captain's balance negative", async () => {
    await seedUser("u_rider", "rider", 0);
    await seedUser("u_captain", "captain", 5);
    const t = await seedTripRow({ payment_method: "cash" });

    const out = await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    expect(await balance("u_captain")).toBe(5);
    expect(out.commissionUncollected).toBe(true);
    expect(await rows("status = 'failed'")).toBe(1);
  });

  it("settling twice does not move the balance twice", async () => {
    await seedUser("u_rider", "rider", 0);
    await seedUser("u_captain", "captain", 200);
    const t = await seedTripRow({ payment_method: "cash" });

    await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    const again = await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    expect(await balance("u_captain")).toBe(180);
    expect(again.captainMove?.reason).toBe("duplicate");
  });

  // D3 — do not weaken this one.
  it("does NOT credit the captain when the rider never paid (no minting)", async () => {
    await seedUser("u_rider", "rider", 10);
    await seedUser("u_captain", "captain", 0);
    const t = await seedTripRow({ payment_method: "wallet", billed_to_company: 0 });

    const out = await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    expect(await balance("u_rider")).toBe(10);
    expect(await balance("u_captain")).toBe(0);
    expect(out.creditWithheld).toBe(true);
    expect(await rows("idempotency_key = 'trip_payout:t1'")).toBe(0);
    // The real debit key stays free so a retry after a top-up can still settle.
    expect(await rows("idempotency_key = 'trip_debit:t1'")).toBe(0);
    expect(await rows("idempotency_key = 'trip_debit_failed:t1'")).toBe(1);
  });

  it("moves both legs when the rider can pay, and writes the audit row", async () => {
    await seedUser("u_rider", "rider", 500);
    await seedUser("u_captain", "captain", 0);
    const t = await seedTripRow({ payment_method: "wallet", billed_to_company: 0 });

    await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    expect(await balance("u_rider")).toBe(400);
    expect(await balance("u_captain")).toBe(80);

    const aud = await DB.prepare(
      `SELECT entity_id, payload FROM audit_log WHERE action = 'trip.settled'`,
    ).first<{ entity_id: string; payload: string }>();
    expect(aud?.entity_id).toBe("t1");
    expect(aud?.payload).toContain("priceSource");
  });

  // The acceptance criterion, end to end against the primitive.
  it("a captain accepting an offer of X is credited from X", async () => {
    await seedUser("u_rider", "rider", 0);
    await seedUser("u_captain", "captain", 500);
    const t = await seedTripRow({ payment_method: "cash", offered_price: 150 });

    const out = await settleTripCompletion({ db: DB, trip: t, tripId: "t1" });
    expect(out.settledPrice).toBe(150);
    expect(out.commission).toBe(30);
    expect(await balance("u_captain")).toBe(470);
  });

  it("still honours a caller-supplied fare, so trips.ts is unchanged until E09", async () => {
    await seedUser("u_rider", "rider", 0);
    await seedUser("u_captain", "captain", 500);
    const t = await seedTripRow({ payment_method: "cash", offered_price: 150 });

    const out = await settleTripCompletion({
      db: DB, trip: t, tripId: "t1",
      finalFare: 100, commission: 20, captainPayout: 80,
    });
    expect(out.settledPrice).toBe(100);
    expect(out.agreedPrice).toBe(150); // reported, and counted as a mismatch
    expect(await balance("u_captain")).toBe(480);
  });
});
