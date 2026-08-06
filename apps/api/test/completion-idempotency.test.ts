/**
 * Gate item 16 · the completion handler must be safe to retry.
 *
 * A captain on a bad connection taps "complete" twice; the client retries a
 * request whose response was lost. Both are ordinary. Before E08 the rider
 * debit updated the balance *before* taking the idempotency lock, so a retried
 * completion moved money a second time and then discarded the duplicate ledger
 * row — the balance drifted and the ledger did not show why.
 *
 * Two independent guards have to hold, and this file tests both:
 *
 *   1. the row guard — `UPDATE … WHERE id = ? AND status != 'completed'`
 *      (`routes/trips.ts:878`), which makes the second HTTP call a 409;
 *   2. the money guard — the `UNIQUE` index `idx_wt_idem` (`migrations/0005`),
 *      which makes a second balance move impossible even if a caller gets
 *      past the first guard.
 *
 * Testing only the 409 would be testing the cheaper half.
 */
import { env, SELF } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { settleTripCompletion, type SettlementTrip } from "../src/lib/settlement";
import { moveMoney } from "../src/lib/money";
import {
  seedUser,
  seedCaptain,
  seedTrip,
  authHeaders,
  balancePiastres,
  ledgerRows,
} from "./helpers";

describe("POST /trips/:id/complete — the row guard", () => {
  it("completes once and 409s the retry", async () => {
    await seedUser("rider_c", "rider", 0);
    await seedUser("cap_c", "captain", 100);
    await seedCaptain("cap_c");
    await seedTrip({
      id: "trip_c1",
      riderId: "rider_c",
      captainId: "cap_c",
      status: "in_progress",
      commission: 20,
    });

    const headers = await authHeaders("cap_c", "captain");

    const first = await SELF.fetch("https://api.test/trips/trip_c1/complete", {
      method: "POST",
      headers,
    });
    expect(first.status).toBe(200);

    const second = await SELF.fetch("https://api.test/trips/trip_c1/complete", {
      method: "POST",
      headers,
    });
    // The guard turns the retry into a refusal rather than a second settlement.
    expect(second.status).toBe(409);
    expect((await second.json<{ code: string }>()).code).toBe("CONFLICT");
  });

  it("charges the commission exactly once across a retried completion", async () => {
    await seedUser("rider_c2", "rider", 0);
    await seedUser("cap_c2", "captain", 100);
    await seedCaptain("cap_c2");
    await seedTrip({
      id: "trip_c2",
      riderId: "rider_c2",
      captainId: "cap_c2",
      status: "in_progress",
      commission: 20,
    });

    const headers = await authHeaders("cap_c2", "captain");
    await SELF.fetch("https://api.test/trips/trip_c2/complete", { method: "POST", headers });
    await SELF.fetch("https://api.test/trips/trip_c2/complete", { method: "POST", headers });

    // 100 − 20, once. Not 60.
    expect(await balancePiastres("cap_c2")).toBe(8000);
    const settled = (await ledgerRows("trip_commission_debit:trip_c2")).filter(
      (r) => (r as { status: string }).status === "settled",
    );
    expect(settled).toHaveLength(1);
  });
});

describe("the money guard — idempotency independent of the row guard", () => {
  it("does not move the balance twice when settlement itself is re-run", async () => {
    // Bypasses the HTTP row guard on purpose: this is the second line of
    // defence, and it has to hold on its own.
    await seedUser("rider_c3", "rider", 0);
    await seedUser("cap_c3", "captain", 100);
    await seedTrip({ id: "trip_c3", riderId: "rider_c3", captainId: "cap_c3", commission: 20 });

    const trip = await env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind("trip_c3")
      .first();

    await settleTripCompletion({ db: env.DB, trip: trip as unknown as SettlementTrip, tripId: "trip_c3" });
    await settleTripCompletion({ db: env.DB, trip: trip as unknown as SettlementTrip, tripId: "trip_c3" });

    expect(await balancePiastres("cap_c3")).toBe(8000);
  });

  it("reports the second attempt as a duplicate rather than a new debit", async () => {
    await seedUser("cap_c4", "captain", 100);

    const first = await moveMoney({
      db: env.DB,
      userId: "cap_c4",
      type: "commission",
      direction: "debit",
      amount: 20,
      idempotencyKey: "dup:trip_c4",
    });
    const second = await moveMoney({
      db: env.DB,
      userId: "cap_c4",
      type: "commission",
      direction: "debit",
      amount: 20,
      idempotencyKey: "dup:trip_c4",
    });

    expect(first.moved).toBe(true);
    expect(second.moved).toBe(false);
    expect(second.reason).toBe("duplicate");
    expect(await balancePiastres("cap_c4")).toBe(8000);
    expect(await ledgerRows("dup:trip_c4")).toHaveLength(1);
  });

  it("refuses to move money for a user that does not exist", async () => {
    // `INSERT … SELECT FROM users` is what makes this true; the previous
    // `INSERT … VALUES` would happily have written the ledger row.
    const res = await moveMoney({
      db: env.DB,
      userId: "nobody_at_all",
      type: "commission",
      direction: "debit",
      amount: 10,
      idempotencyKey: "ghost:1",
    });

    expect(res.moved).toBe(false);
    expect(await ledgerRows("ghost:1")).toHaveLength(0);
  });

  it("refuses a non-positive amount without writing anything", async () => {
    await seedUser("cap_c5", "captain", 50);

    for (const amount of [0, -5]) {
      const res = await moveMoney({
        db: env.DB,
        userId: "cap_c5",
        type: "commission",
        direction: "debit",
        amount,
        idempotencyKey: `nonpos:${amount}`,
      });
      expect(res.moved).toBe(false);
      expect(res.reason).toBe("non_positive_amount");
    }
    expect(await balancePiastres("cap_c5")).toBe(5000);
  });
});
