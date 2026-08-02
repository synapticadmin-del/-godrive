/**
 * Gate item 16 · the launch shape is a property of the API, not of the app.
 *
 * E04 narrowed `createTripSchema.paymentMethod` from
 * `z.enum(["cash","card","wallet"])` to `z.enum(["cash"])`. The rider client
 * only ever sent `"cash"`, but the client is not the boundary: `POST /trips`
 * took `body.paymentMethod` straight into the INSERT, so anyone with curl could
 * book a wallet- or card-paid trip and reach the two paths the launch shape
 * descopes — the settlement mint (F-18-01) and the fare bypass (F-04-03).
 *
 * That narrowing is **G1‡ — disabled, not fixed.** Nothing downstream of it was
 * repaired, so widening the enum re-opens both findings. `lib/schemas.ts:70`
 * says the rejection has to be asserted for exactly that reason: putting
 * `"wallet"` back must turn a test red before it can ship.
 *
 * ## Why no test here reaches the network
 *
 * `parseBody()` runs at `routes/trips.ts:322`, before the active-trip lookup,
 * before `getPricing()` and well before `getRoute()`. A rejected method 400s
 * without a single outbound request. For the accepted case the test removes
 * `pricing_rules` first, so the request stops deterministically at
 * `NO_PRICING` (`:343`) — which still proves it got past validation, and still
 * never calls OSRM.
 */
import { env, SELF } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { createTripSchema } from "../src/lib/schemas";
import { seedUser, authHeaders } from "./helpers";

const BODY = {
  pickupLat: 30.0444,
  pickupLng: 31.2357,
  dropoffLat: 30.0561,
  dropoffLng: 31.2394,
};

describe("createTripSchema — the enum itself", () => {
  it.each(["wallet", "card"])("rejects paymentMethod=%s", (method) => {
    const res = createTripSchema.safeParse({ ...BODY, paymentMethod: method });
    expect(res.success).toBe(false);
  });

  it("accepts cash", () => {
    const res = createTripSchema.safeParse({ ...BODY, paymentMethod: "cash" });
    expect(res.success).toBe(true);
  });

  it("defaults an omitted paymentMethod to cash", () => {
    const res = createTripSchema.safeParse(BODY);
    expect(res.success).toBe(true);
    expect(res.success && res.data.paymentMethod).toBe("cash");
  });
});

describe("POST /trips — the rejection at the edge", () => {
  it.each(["wallet", "card"])("400s a %s trip before anything is written", async (method) => {
    await seedUser("rider_p", "rider", 500);
    const headers = await authHeaders("rider_p", "rider");

    const res = await SELF.fetch("https://api.test/trips", {
      method: "POST",
      headers,
      body: JSON.stringify({ ...BODY, paymentMethod: method }),
    });

    expect(res.status).toBe(400);
    expect((await res.json<{ code: string }>()).code).toBe("VALIDATION_ERROR");

    // The rejection has to happen *before* the INSERT, not after it.
    const trips = await env.DB.prepare(`SELECT count(*) AS c FROM trips`).first<{ c: number }>();
    expect(trips?.c).toBe(0);
  });

  it("lets a cash trip past validation", async () => {
    // Deterministic stop short of routing: no pricing row, so the handler
    // returns NO_PRICING. Reaching that line at all proves the body validated.
    await env.DB.prepare(`DELETE FROM pricing_rules`).run();
    await seedUser("rider_p2", "rider", 500);

    const res = await SELF.fetch("https://api.test/trips", {
      method: "POST",
      headers: await authHeaders("rider_p2", "rider"),
      body: JSON.stringify({ ...BODY, paymentMethod: "cash" }),
    });

    expect(res.status).not.toBe(400);
    expect((await res.json<{ code: string }>()).code).toBe("NO_PRICING");
  });

  it("rejects a payment method the enum never had", async () => {
    await seedUser("rider_p3", "rider", 500);

    const res = await SELF.fetch("https://api.test/trips", {
      method: "POST",
      headers: await authHeaders("rider_p3", "rider"),
      body: JSON.stringify({ ...BODY, paymentMethod: "crypto" }),
    });

    expect(res.status).toBe(400);
  });
});
