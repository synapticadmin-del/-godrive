import { describe, it, expect } from "vitest";
import {
  calculateFare,
  DEFAULT_PRICING,
  TRIP_TRANSITIONS,
  type PricingRule,
} from "./index";

const rule: PricingRule = DEFAULT_PRICING;

describe("calculateFare", () => {
  it("computes the base fare for a standard trip (10 km / 20 min)", () => {
    // base 12 + distance 45 + time 10 + booking 3 = 70
    const fare = calculateFare(10, 20, rule);
    expect(fare.baseFare).toBe(12);
    expect(fare.distanceFare).toBe(45);
    expect(fare.timeFare).toBe(10);
    expect(fare.bookingFee).toBe(3);
    expect(fare.total).toBe(70);
  });

  it("enforces the minFare floor for short trips", () => {
    // base 12 + distance 2.25 + time 1 + booking 3 = 18.25 → floored to minFare 25
    const fare = calculateFare(0.5, 2, rule);
    expect(fare.total).toBe(rule.minFare);
    expect(fare.total).toBe(25);
  });

  it("applies the surge multiplier to the full fare", () => {
    // (12 + 45 + 10 + 3) * 2 = 140
    const fare = calculateFare(10, 20, rule, { surgeMultiplier: 2 });
    expect(fare.total).toBe(140);
  });

  it("applies a discount to the total", () => {
    // 70 - 10 = 60
    const fare = calculateFare(10, 20, rule, { discount: 10 });
    expect(fare.total).toBe(60);
  });

  it("floors the total at zero when the discount exceeds the fare", () => {
    // 70 - 999 → clamped to 0
    const fare = calculateFare(10, 20, rule, { discount: 999 });
    expect(fare.total).toBe(0);
    expect(fare.commission).toBe(0);
    // TODO: minFare is applied BEFORE the discount, so a large discount can
    // push the total below minFare (even to 0). Decide whether minFare should
    // instead be enforced AFTER the discount is applied.
  });

  it("computes commission from the discounted total", () => {
    // 70 * 0.2 = 14, and (70 - 10) * 0.2 = 12
    expect(calculateFare(10, 20, rule).commission).toBe(14);
    expect(calculateFare(10, 20, rule, { discount: 10 }).commission).toBe(12);
  });

  it("clamps negative distance/duration to zero instead of producing a negative fare", () => {
    // With the input guard, negative distance/time are clamped to 0, so the
    // fare is just base + booking = 15 → floored to minFare 25 (never negative).
    const fare = calculateFare(-5, -10, rule);
    expect(fare.distanceKm).toBe(0);
    expect(fare.durationMin).toBe(0);
    expect(fare.distanceFare).toBe(0);
    expect(fare.timeFare).toBe(0);
    expect(fare.total).toBe(rule.minFare);
    expect(fare.total).toBeGreaterThanOrEqual(0);
  });

  it("handles zero distance (base + booking only, floored to minFare)", () => {
    // base 12 + 0 + time 10 + booking 3 = 25
    const fare = calculateFare(0, 20, rule);
    expect(fare.distanceFare).toBe(0);
    expect(fare.total).toBe(25);
  });
});

describe("TRIP_TRANSITIONS", () => {
  it("keeps the expected state machine shape", () => {
    expect(TRIP_TRANSITIONS.searching).toEqual(["offered", "assigned", "cancelled"]);
    expect(TRIP_TRANSITIONS.completed).toEqual([]);
    expect(TRIP_TRANSITIONS.cancelled).toEqual([]);
  });
});
