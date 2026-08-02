/**
 * Gate item 16 · the cash-commission money path.
 *
 * Under the launch shape (cash only, wallet and card rejected at the edge by
 * E04) the platform's commission debit is **the only live money path in the
 * product**. It was also the one debit in the codebase with no floor at all
 * — F-03-11 / F-04-12, promoted to G1 — so a captain whose wallet was short
 * went negative and the balance sheet drifted silently.
 *
 * These tests fail if the floor is removed, if the commission stops tracking
 * the price that was actually agreed, or if a refused debit stops leaving a
 * trace.
 */
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import {
  resolveTripSettlement,
  settleTripCompletion,
  type SettlementTrip,
} from "../src/lib/settlement";
import { moveMoney } from "../src/lib/money";
import { seedUser, seedTrip, balancePiastres, ledgerRows } from "./helpers";

describe("resolveTripSettlement — the price that was agreed", () => {
  it("settles offered_price on the direct-accept path, not estimated_fare", () => {
    // The rider named 150; the estimate was 100. Before E08 this settled 100.
    const r = resolveTripSettlement({
      accepted_price: null,
      offered_price: 150,
      final_fare: null,
      estimated_fare: 100,
      commission: 20,
      payment_method: "cash",
    } as unknown as SettlementTrip);

    expect(r.agreedPrice).toBe(150);
    expect(r.priceSource).toBe("offered_price");
  });

  it("rescales the commission to the same effective rate the booking used", () => {
    // Commission was stored as 20 on a 100 estimate — 20%. On a 150 agreed
    // price the platform's take must still be 20%, or the captain is paid a
    // number that does not correspond to any rate.
    const r = resolveTripSettlement({
      accepted_price: null,
      offered_price: 150,
      final_fare: null,
      estimated_fare: 100,
      commission: 20,
      payment_method: "cash",
    } as unknown as SettlementTrip);

    expect(r.commission).toBe(30);
    expect(r.commissionSource).toBe("rescaled");
    expect(r.captainPayout).toBe(120);
  });

  it("prefers an accepted bid over the rider's offer", () => {
    const r = resolveTripSettlement({
      accepted_price: 200,
      offered_price: 150,
      final_fare: null,
      estimated_fare: 100,
      commission: 40,
      payment_method: "cash",
    } as unknown as SettlementTrip);

    expect(r.agreedPrice).toBe(200);
    expect(r.priceSource).toBe("accepted_price");
    // The bid path already recomputed commission against the accepted price,
    // so it must be kept as stored rather than rescaled a second time.
    expect(r.commissionSource).toBe("stored");
  });

  it("never returns a commission larger than the fare", () => {
    const r = resolveTripSettlement({
      accepted_price: 10,
      offered_price: null,
      final_fare: null,
      estimated_fare: 10,
      commission: 999,
      payment_method: "cash",
    } as unknown as SettlementTrip);

    expect(r.commission).toBeLessThanOrEqual(r.agreedPrice);
    expect(r.captainPayout).toBeGreaterThanOrEqual(0);
  });
});

describe("cash commission debit — the balance floor", () => {
  it("debits the commission from a solvent captain", async () => {
    await seedUser("rider_1", "rider", 0);
    await seedUser("cap_solvent", "captain", 100);
    await seedTrip({ id: "trip_solvent", captainId: "cap_solvent", commission: 20 });

    const trip = await env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind("trip_solvent")
      .first();

    const out = await settleTripCompletion({
      db: env.DB,
      trip: trip as unknown as SettlementTrip,
      tripId: "trip_solvent",
    });

    expect(out.captainMove?.moved).toBe(true);
    expect(await balancePiastres("cap_solvent")).toBe(8000); // 100.00 → 80.00
  });

  it("REFUSES the debit rather than driving the wallet negative", async () => {
    // The captain has 5 EGP and owes 20. Before the floor, this wrote -15.
    await seedUser("rider_1", "rider", 0);
    await seedUser("cap_short", "captain", 5);
    await seedTrip({ id: "trip_short", captainId: "cap_short", commission: 20 });

    const trip = await env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind("trip_short")
      .first();

    const out = await settleTripCompletion({
      db: env.DB,
      trip: trip as unknown as SettlementTrip,
      tripId: "trip_short",
    });

    const after = await balancePiastres("cap_short");
    expect(after).toBe(500); // untouched
    expect(after).toBeGreaterThanOrEqual(0); // the property that matters
    expect(out.commissionUncollected).toBe(true);
  });

  it("leaves a 'failed' ledger row for the uncollected commission", async () => {
    await seedUser("rider_1", "rider", 0);
    await seedUser("cap_short2", "captain", 5);
    await seedTrip({ id: "trip_short2", captainId: "cap_short2", commission: 20 });

    const trip = await env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind("trip_short2")
      .first();
    await settleTripCompletion({ db: env.DB, trip: trip as unknown as SettlementTrip, tripId: "trip_short2" });

    const failed = await ledgerRows("trip_commission_debit_failed:trip_short2");
    expect(failed).toHaveLength(1);
    expect((failed[0] as { status: string }).status).toBe("failed");
  });

  it("does not burn the live idempotency key when the debit is refused", async () => {
    // The old code wrote the failure under the real key, so a retry after the
    // captain topped up could never insert the settled row. The debt became
    // permanently uncollectable.
    await seedUser("rider_1", "rider", 0);
    await seedUser("cap_short3", "captain", 5);
    await seedTrip({ id: "trip_short3", captainId: "cap_short3", commission: 20 });

    const trip = await env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind("trip_short3")
      .first();
    await settleTripCompletion({ db: env.DB, trip: trip as unknown as SettlementTrip, tripId: "trip_short3" });

    expect(await ledgerRows("trip_commission_debit:trip_short3")).toHaveLength(0);

    // Top the captain up, retry: the debit must now succeed under the live key.
    await env.DB.prepare(`UPDATE users SET wallet_balance = 50, wallet_balance_piastres = 5000 WHERE id = ?`)
      .bind("cap_short3")
      .run();

    const retry = await moveMoney({
      db: env.DB,
      userId: "cap_short3",
      type: "commission",
      direction: "debit",
      amount: 20,
      idempotencyKey: "trip_commission_debit:trip_short3",
      tripId: "trip_short3",
    });

    expect(retry.moved).toBe(true);
    expect(await balancePiastres("cap_short3")).toBe(3000);
  });

  it("refuses a debit that would breach the floor by a single piastre", async () => {
    await seedUser("cap_edge", "captain", 19.99);

    const res = await moveMoney({
      db: env.DB,
      userId: "cap_edge",
      type: "commission",
      direction: "debit",
      amount: 20,
      idempotencyKey: "edge:1",
    });

    expect(res.moved).toBe(false);
    expect(res.reason).toBe("insufficient_funds");
    expect(await balancePiastres("cap_edge")).toBe(1999);
  });

  it("allows a debit that lands exactly on the floor", async () => {
    await seedUser("cap_exact", "captain", 20);

    const res = await moveMoney({
      db: env.DB,
      userId: "cap_exact",
      type: "commission",
      direction: "debit",
      amount: 20,
      idempotencyKey: "exact:1",
    });

    expect(res.moved).toBe(true);
    expect(await balancePiastres("cap_exact")).toBe(0);
  });
});
