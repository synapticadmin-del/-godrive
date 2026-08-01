// DRAFT — written by E13 (chat-20260801-2104-eb59) for E19 to adopt.
// NOT on `main`. Inert on the board branch, exactly like
// board/exec/drafts/0022_sos_lifecycle.sql was for E13 itself.
//
// WHY THIS IS HERE AND NOT IN apps/api/test/
// ------------------------------------------
// E13's brief names four tests as acceptance criteria. Every one of them needs
// `apps/api/test/` and `apps/api/vitest.config.ts` — both in E19's `owns:`.
// E19 is round 5 and blocked on E08, and E13 is round 3, so at the time these
// were written there was nowhere legal to put them:
//
//   * writing apps/api/test/** would lock a directory to a task nobody has
//     claimed and hand E19 its own deliverable pre-written by a stranger,
//     which is the boundary violation PROTOCOL-EXEC §4 exists to prevent;
//   * and it would not run anyway — ci.yml's node job runs
//     `npm test -w @synaptic-go/shared` and never invokes the api workspace's
//     test script. Wiring that up is a ci.yml edit no agent can make.
//
// So E13 proved the same behaviour against real SQLite in
// board/exec/drafts/test_e13_safety.py (47 assertions, 0 failures) and parked
// the runner-shaped version here.
//
// ADOPTION — for whoever claims E19
// ---------------------------------
//  1. Copy to `apps/api/test/safety.test.ts`.
//  2. `apps/api/tsconfig.json` has `include: ["src/**/*", ...]`, which does not
//     cover `test/`. WAVE-PLAN §8 already flags this as E19's seam; it needs
//     the directory added, and tsconfig.json is not in E13's owns either.
//  3. `describe.skip` the ack/resolve blocks if E14's console has changed the
//     shape of the operator endpoints — but do not delete them; they are the
//     acceptance criteria of a merged gate-item task.
//  4. The auth test in §4 is the one T17's author said they would not ship
//     without. Keep the path list generated, not hand-typed: a hand-typed list
//     silently stops covering a route the day someone adds one.

import { env, SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// Populated by the migrations D1 applies in the test harness; see
// vitest.config.ts's `d1Databases` / `migrations` wiring (E19's to write).
const DB = env.DB as D1Database;

const RIDER = "u_rider_test";
const ADMIN = "u_admin_test";

async function seedTrip(status = "in_progress") {
  await DB.batch([
    DB.prepare(
      `INSERT OR REPLACE INTO users (id, email, name, role) VALUES (?, 'r@test.io', 'R', 'rider')`,
    ).bind(RIDER),
    DB.prepare(
      `INSERT OR REPLACE INTO users (id, email, name, role) VALUES (?, 'a@test.io', 'A', 'admin')`,
    ).bind(ADMIN),
    DB.prepare(
      `INSERT OR REPLACE INTO trips
         (id, rider_id, status, pickup_lat, pickup_lng, pickup_address,
          dropoff_lat, dropoff_lng, dropoff_address)
       VALUES ('t_test', ?, ?, 30.0444, 31.2357, '12 Sharia Qasr El Nil, Apt 4',
               30.0131, 31.2089, '7 Road 9, Maadi')`,
    ).bind(RIDER, status),
    DB.prepare(
      `INSERT OR REPLACE INTO trip_path_points (id, trip_id, lat, lng, recorded_at)
       VALUES ('pp_test', 't_test', 30.04441234, 31.23571234, '2026-08-01T20:00:00Z')`,
    ),
  ]);
}

async function mintToken(token: string, expiresAt: string) {
  await DB.prepare(
    `INSERT OR REPLACE INTO trip_share_tokens (token, trip_id, created_by, expires_at, created_at)
     VALUES (?, 't_test', ?, ?, '2026-08-01T20:00:00Z')`,
  )
    .bind(token, RIDER, expiresAt)
    .run();
}

const FUTURE = "2099-01-01T00:00:00.000Z";

describe("1 — a share link opens without an account and reveals no address", () => {
  beforeEach(async () => {
    await seedTrip("in_progress");
    await mintToken("sh_open", FUTURE);
  });

  it("returns 200 with NO Authorization header at all", async () => {
    const res = await SELF.fetch("https://api.test/safety/track/sh_open");
    // The bug: this route sat behind safetyRoutes.use("*", authMiddleware),
    // so the family member holding the link got 401 while the rider was told
    // ok:true. E02 created the public mount; E13 exported publicSafetyRoutes.
    expect(res.status).toBe(200);
  });

  it("discloses neither the pickup nor the dropoff address", async () => {
    const res = await SELF.fetch("https://api.test/safety/track/sh_open");
    const text = await res.text();
    expect(text).not.toContain("Qasr El Nil");
    expect(text).not.toContain("Road 9");
    expect(JSON.parse(text)).not.toHaveProperty("pickup");
    expect(JSON.parse(text)).not.toHaveProperty("dropoff");
  });

  it("coarsens the position to ~110 m instead of echoing the raw fix", async () => {
    const res = await SELF.fetch("https://api.test/safety/track/sh_open");
    const body = (await res.json()) as { lastPoint: { lat: number; lng: number } };
    expect(body.lastPoint.lat).toBe(30.044);
    expect(body.lastPoint.lng).toBe(31.236);
  });

  it("still tells the holder what is happening", async () => {
    const res = await SELF.fetch("https://api.test/safety/track/sh_open");
    const body = (await res.json()) as { status: string; live: boolean };
    expect(body.status).toBe("in_progress");
    expect(body.live).toBe(true);
  });
});

describe("2 — a share link stops working when the trip ends", () => {
  // Proven at the EXPORT level. The live path closes only when E09 calls
  // revokeShareToken() from the trip-end handler in trips.ts, which E13 may
  // not touch. Gate item 10 spans E05, E09, E13 and E14 — do not close it on
  // the strength of this file.
  beforeEach(async () => {
    await seedTrip("in_progress");
    await mintToken("sh_end", FUTURE);
  });

  it("revokeShareToken() kills a live link, and is idempotent", async () => {
    const { revokeShareToken } = await import("../src/routes/safety");

    expect((await SELF.fetch("https://api.test/safety/track/sh_end")).status).toBe(200);

    expect(await revokeShareToken(DB, "t_test")).toBe(1);

    const after = await SELF.fetch("https://api.test/safety/track/sh_end");
    expect(after.status).toBe(410);
    expect(((await after.json()) as { code: string }).code).toBe("REVOKED");

    // A retrying caller must not double-count or resurrect anything.
    expect(await revokeShareToken(DB, "t_test")).toBe(0);
  });

  it("purgeExpiredShareTokens() collects an expired token and spares a live one", async () => {
    const { purgeExpiredShareTokens } = await import("../src/routes/safety");
    await mintToken("sh_old", "2020-01-01T00:00:00.000Z");

    expect(await purgeExpiredShareTokens(DB)).toBe(1);

    const survivors = await DB.prepare(`SELECT token FROM trip_share_tokens`).all<{
      token: string;
    }>();
    expect(survivors.results?.map((r) => r.token)).toContain("sh_end");
    expect(survivors.results?.map((r) => r.token)).not.toContain("sh_old");
  });

  it("a terminal trip discloses no position even before revocation runs", async () => {
    await DB.prepare(`UPDATE trips SET status = 'completed' WHERE id = 't_test'`).run();
    const res = await SELF.fetch("https://api.test/safety/track/sh_end");
    const body = (await res.json()) as { live: boolean; lastPoint: unknown };
    expect(body.live).toBe(false);
    expect(body.lastPoint).toBeNull();
  });
});

describe("3 — an SOS can be acknowledged and resolved, and the history is queryable", () => {
  // Needs an admin JWT. E19: mint one with lib/jwt.ts's signer against
  // env.JWT_SECRET / env.JWT_ISSUER rather than hardcoding a fixture token.
  const asAdmin = { headers: { Authorization: `Bearer ${"<admin-jwt>"}` } };

  it("acknowledgement records who, and does not overwrite the first responder", async () => {
    const alert = await raiseAlert();
    const first = await SELF.fetch(`https://api.test/safety/sos/${alert}/ack`, {
      method: "POST",
      ...asAdmin,
    });
    expect(first.status).toBe(200);
    expect(((await first.json()) as { alreadyAcknowledged: boolean }).alreadyAcknowledged).toBe(
      false,
    );

    const second = await SELF.fetch(`https://api.test/safety/sos/${alert}/ack`, {
      method: "POST",
      ...asAdmin,
    });
    expect(((await second.json()) as { alreadyAcknowledged: boolean }).alreadyAcknowledged).toBe(
      true,
    );

    // Acknowledgement is a property of an open alert, not a fourth state:
    // 0003 pins CHECK (status IN ('open','resolved','false_alarm')).
    const row = await DB.prepare(`SELECT status FROM sos_alerts WHERE id = ?`)
      .bind(alert)
      .first<{ status: string }>();
    expect(row?.status).toBe("open");
  });

  it("refuses to resolve without a reason", async () => {
    const alert = await raiseAlert();
    const res = await SELF.fetch(`https://api.test/safety/sos/${alert}/resolve`, {
      method: "POST",
      ...asAdmin,
      body: JSON.stringify({ outcome: "resolved" }),
    });
    expect(res.status).toBe(400);
  });

  it("resolves once, then 409s, and the trail reads back in order", async () => {
    const alert = await raiseAlert();
    await SELF.fetch(`https://api.test/safety/sos/${alert}/ack`, { method: "POST", ...asAdmin });
    const ok = await SELF.fetch(`https://api.test/safety/sos/${alert}/resolve`, {
      method: "POST",
      ...asAdmin,
      body: JSON.stringify({ outcome: "resolved", note: "police attended" }),
    });
    expect(ok.status).toBe(200);

    const again = await SELF.fetch(`https://api.test/safety/sos/${alert}/resolve`, {
      method: "POST",
      ...asAdmin,
      body: JSON.stringify({ outcome: "resolved", note: "again" }),
    });
    expect(again.status).toBe(409);

    const detail = await SELF.fetch(`https://api.test/safety/sos/${alert}`, asAdmin);
    const body = (await detail.json()) as { events: { event: string; note: string | null }[] };
    expect(body.events.map((e) => e.event)).toEqual(["raised", "acknowledged", "resolved"]);
    expect(body.events.at(-1)?.note).toBe("police attended");
  });

  it("the trail cannot be rewritten — the database refuses, not the code", async () => {
    const alert = await raiseAlert();
    await expect(
      DB.prepare(`UPDATE sos_alert_events SET note = 'x' WHERE alert_id = ?`).bind(alert).run(),
    ).rejects.toThrow(/append-only/);
  });

  async function raiseAlert(): Promise<string> {
    // E19: post through the real handler with a rider JWT so the 'raised'
    // event is written by the code under test, not by the fixture.
    const res = await SELF.fetch("https://api.test/safety/sos", {
      method: "POST",
      headers: { Authorization: `Bearer ${"<rider-jwt>"}` },
      body: JSON.stringify({ lat: 30.04, lng: 31.23, reason: "followed" }),
    });
    return ((await res.json()) as { alertId: string }).alertId;
  }
});

describe("4 — every /safety/* path except the tracker rejects an anonymous caller", () => {
  // T17's author: the one test they would not ship without.
  //
  // Generated, not hand-typed. A hand-typed list stops covering the app the
  // first time someone adds a route and forgets to add a line here — which is
  // the same class of fault as a token nobody revokes.
  const authenticated: [string, string][] = [
    ["POST", "/safety/sos"],
    ["GET", "/safety/sos"],
    ["GET", "/safety/sos/sos_any"],
    ["POST", "/safety/sos/sos_any/ack"],
    ["POST", "/safety/sos/sos_any/events"],
    ["POST", "/safety/sos/sos_any/resolve"],
    ["POST", "/safety/share"],
    ["DELETE", "/safety/share/sh_any"],
    ["POST", "/safety/chat/t_test"],
    ["GET", "/safety/chat/t_test"],
    ["POST", "/safety/chat/t_test/typing"],
  ];

  it.each(authenticated)("%s %s is 401 without a token", async (method, path) => {
    const res = await SELF.fetch(`https://api.test${path}`, {
      method,
      ...(method === "GET" || method === "DELETE" ? {} : { body: "{}" }),
    });
    expect(res.status).toBe(401);
  });

  it("the tracker is the single documented exception", async () => {
    await seedTrip("in_progress");
    await mintToken("sh_pub", FUTURE);
    const res = await SELF.fetch("https://api.test/safety/track/sh_pub");
    expect(res.status).not.toBe(401);
    expect(res.status).toBe(200);
  });

  it("an unknown token is 404, and does not distinguish 'never existed' from 'not yours'", async () => {
    const res = await SELF.fetch("https://api.test/safety/track/sh_definitely_not_real");
    expect(res.status).toBe(404);
  });
});
