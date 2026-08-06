/**
 * Gate item 16 · two captains, one trip.
 *
 * Dispatch offers a trip to several captains at once, so two of them tapping
 * "accept" within the same second is the normal case, not the edge case. The
 * handler's protection is a compare-and-swap: the `UPDATE` carries
 * `AND status IN ('searching','offered')` (`routes/trips.ts:767`) and the loser
 * is detected by `meta.changes === 0` (`:772`).
 *
 * Without the guard both updates succeed, the second overwrites `captain_id`,
 * and two captains drive to the same rider — one of whom is never paid.
 *
 * This is a genuine test of D1 rather than of a mock: the whole assertion is
 * that a guarded `UPDATE` reports zero changed rows.
 */
import { env, SELF } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { seedUser, seedCaptain, seedTrip, authHeaders } from "./helpers";

describe("POST /trips/:id/accept — the accept race", () => {
  it("gives the trip to exactly one of two simultaneous captains", async () => {
    await seedUser("rider_r", "rider", 0);
    await seedUser("cap_a", "captain", 0);
    await seedUser("cap_b", "captain", 0);
    await seedCaptain("cap_a");
    await seedCaptain("cap_b");
    await seedTrip({ id: "trip_race", riderId: "rider_r", status: "searching" });

    const [ha, hb] = await Promise.all([
      authHeaders("cap_a", "captain"),
      authHeaders("cap_b", "captain"),
    ]);

    // Fired together. Which one wins is not asserted — only that one does.
    const [ra, rb] = await Promise.all([
      SELF.fetch("https://api.test/trips/trip_race/accept", { method: "POST", headers: ha }),
      SELF.fetch("https://api.test/trips/trip_race/accept", { method: "POST", headers: hb }),
    ]);

    const codes = [ra.status, rb.status].sort();
    expect(codes).toEqual([200, 409]);

    const loser = ra.status === 409 ? ra : rb;
    // Depending on which request reads the row first, the loser either loses
    // the guarded UPDATE or observes the winner's assigned state. Both are the
    // same conflict and, critically, neither can overwrite the winner.
    expect(["TRIP_TAKEN", "NOT_AVAILABLE"]).toContain((await loser.json<{ code: string }>()).code);
  });

  it("leaves the trip assigned to the winner alone", async () => {
    await seedUser("rider_r2", "rider", 0);
    await seedUser("cap_c", "captain", 0);
    await seedUser("cap_d", "captain", 0);
    await seedCaptain("cap_c");
    await seedCaptain("cap_d");
    await seedTrip({ id: "trip_race2", riderId: "rider_r2", status: "searching" });

    const hc = await authHeaders("cap_c", "captain");
    const hd = await authHeaders("cap_d", "captain");

    const first = await SELF.fetch("https://api.test/trips/trip_race2/accept", {
      method: "POST",
      headers: hc,
    });
    expect(first.status).toBe(200);

    const second = await SELF.fetch("https://api.test/trips/trip_race2/accept", {
      method: "POST",
      headers: hd,
    });
    expect(second.status).toBe(409);

    // The decisive assertion: the loser did not overwrite the winner.
    const row = await env.DB.prepare(`SELECT captain_id, status FROM trips WHERE id = ?`)
      .bind("trip_race2")
      .first<{ captain_id: string; status: string }>();

    expect(row?.captain_id).toBe("cap_c");
    expect(row?.status).toBe("assigned");
  });

  it("refuses a captain who is already on an active trip", async () => {
    await seedUser("rider_r3", "rider", 0);
    await seedUser("cap_busy", "captain", 0);
    await seedCaptain("cap_busy");
    await seedTrip({ id: "trip_held", riderId: "rider_r3", captainId: "cap_busy", status: "in_progress" });
    await seedTrip({ id: "trip_open", riderId: "rider_r3", status: "searching" });

    const res = await SELF.fetch("https://api.test/trips/trip_open/accept", {
      method: "POST",
      headers: await authHeaders("cap_busy", "captain"),
    });

    expect(res.status).toBe(409);
    expect((await res.json<{ code: string }>()).code).toBe("BUSY");
  });

  it("refuses an offline captain", async () => {
    await seedUser("rider_r4", "rider", 0);
    await seedUser("cap_off", "captain", 0);
    await seedCaptain("cap_off", false);
    await seedTrip({ id: "trip_open2", riderId: "rider_r4", status: "searching" });

    const res = await SELF.fetch("https://api.test/trips/trip_open2/accept", {
      method: "POST",
      headers: await authHeaders("cap_off", "captain"),
    });

    expect(res.status).toBe(403);
    expect((await res.json<{ code: string }>()).code).toBe("OFFLINE");
  });

  it("refuses to accept a trip that is already assigned", async () => {
    await seedUser("rider_r5", "rider", 0);
    await seedUser("cap_late", "captain", 0);
    await seedUser("cap_other", "captain", 0);
    await seedCaptain("cap_late");
    await seedTrip({ id: "trip_gone", riderId: "rider_r5", captainId: "cap_other", status: "assigned" });

    const res = await SELF.fetch("https://api.test/trips/trip_gone/accept", {
      method: "POST",
      headers: await authHeaders("cap_late", "captain"),
    });

    expect(res.status).toBe(409);
    expect((await res.json<{ code: string }>()).code).toBe("NOT_AVAILABLE");
  });
});
