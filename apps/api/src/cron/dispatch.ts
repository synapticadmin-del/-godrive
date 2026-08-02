import { dispatchTrip, writeTripEvent } from "../lib/dispatch";
import { counter, logInfo, logWarn, pingDeadMan } from "../lib/log";
import { pushToUser } from "../lib/notifications";
import { revokeShareToken } from "../routes/safety";
import type { CronJobInput } from "./types";

/**
 * The every-minute trip lifecycle job — **E09**, gate items 7 and 9.
 *
 * E02 lifted this out of `index.ts` verbatim and said so: "E09 owns this file
 * next and is the task that makes the dispatch itself correct; nothing in here
 * was fixed on the way past." This is that task. Two jobs live here now.
 *
 * ## 1. Scheduled rides dispatch at their scheduled time (gate item 9)
 *
 * They did not. `POST /trips` called `dispatchTrip` unconditionally, so a ride
 * booked for 07:00 tomorrow was offered to captains **at booking time** — the
 * staged wave rollout in `OfferScheduler` burned through all ten candidates
 * hours early, each declined a ride they could not take, and the trip then sat
 * in `searching` forever (F-06-01 / F-16-02).
 *
 * This job was supposed to catch that and did not, for two compounding
 * reasons, both fixed here:
 *
 *  - **It never dispatched anything.** It flipped
 *    `scheduled_trip_dispatch.status` to `dispatched` and pushed a notification
 *    to *admins*. No captain was ever offered the trip. The comment claimed
 *    "`/trips` create already drives nearest-captain matching", which was true
 *    and was exactly the bug.
 *  - **Its `WHERE` could never match.** It filters `t.status = 'searching'`,
 *    but booking-time dispatch had already moved the row to `offered`. E09
 *    gates booking dispatch on `!scheduledFor` in `routes/trips.ts`, which is
 *    what makes this predicate reachable at all. The two halves only work
 *    together.
 *
 * ## 2. A trip nobody accepts now reaches a terminal state (gate item 7)
 *
 * Root **R6**: no timeout, no terminal state, no sweeper. The `ACTIVE_TRIP`
 * guard in `POST /trips` then refuses to let that rider book again — so a rider
 * who requests a ride when no captain is online, which is the *normal* early
 * outcome for a platform bootstrapping supply, is locked out of the product
 * permanently. Four tracks found the one hole: T06 F-06-04, T09 F-09-01,
 * T16 F-16-01, T27 F-27-06.
 *
 * ## Two things this job is careful about
 *
 * **Timestamps.** Root **R7**: `nowIso()` writes `2026-08-02T07:00:00.000Z` and
 * SQL defaults write `2026-08-02 07:00:00`, into the same TEXT columns. A raw
 * `created_at < ?` compares `' '` (0x20) against `'T'` (0x54) at offset 10, so
 * *every* SQL-default row sorts below *any* ISO cutoff sharing its date — a
 * sweeper written that way would cancel trips booked an hour in the future.
 * Every comparison here puts both sides through `datetime()`, the idiom
 * `cron/invoices.ts:36` already uses.
 *
 * **Races.** Every state change is a conditional `UPDATE` whose `WHERE` repeats
 * the status it expects, and `meta.changes === 0` means someone else got there
 * first. A captain accepting in the same second as the sweep wins, and the
 * sweep skips the row rather than cancelling a trip that now has a driver.
 */

/**
 * How long a trip may sit unaccepted before it is given up on.
 *
 * The offer rollout reaches all ten candidate captains in roughly 45 s
 * (`OfferScheduler`: 3 per wave, 15 s apart). Ten minutes is ~13× the time it
 * takes to ask everyone, which leaves room for a captain finishing another trip
 * to come back and take it, while staying inside the window where a rider is
 * plausibly still waiting rather than having given up and walked.
 *
 * Deliberately a constant and not a `system_config` row: a knob read from a
 * table with no screen is how the last round of "configurable" values became
 * unobservable. When there is an admin surface for it, move it there.
 */
const UNFULFILLED_TTL_MINUTES = 10;

/**
 * `cancel_reason` written by the sweeper.
 *
 * **Why `cancelled` and not a new `expired` status.** `TripStatus` in
 * `packages/shared/src/index.ts` has seven members and no unfulfilled state,
 * and `TRIP_TRANSITIONS` already permits `searching → cancelled` and
 * `offered → cancelled`. That file is in **nobody's `owns:`** (WAVE-PLAN §8),
 * and a new status would additionally have to be taught to both Flutter apps —
 * three files, three owners, none of them E09. `trips.status` carries no CHECK
 * constraint, so an invented string would store happily and then render
 * nowhere: the worst of both.
 *
 * `cancelled` is terminal, is already understood by every client, and clears
 * the `ACTIVE_TRIP` guard (`status NOT IN ('completed','cancelled')`) — which
 * is the entire point of the sweep. The reason column carries the distinction
 * for anyone reconciling later, and this constant is what a Wave-2 task should
 * grep for when it adds a real `expired` status.
 */
const EXPIRY_REASON = "expired_no_captain";

/** Belt and braces: one tick never tries to sweep an unbounded backlog. */
const SWEEP_BATCH = 200;

type DueScheduledTrip = {
  dispatch_id: string;
  trip_id: string;
  rider_id: string;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_lat: number;
  dropoff_lng: number;
  city: string;
  estimated_fare: number | null;
  currency: string;
};

type ExpiringTrip = {
  id: string;
  rider_id: string;
  status: string;
  scheduled_for: string | null;
};

/**
 * The registered job. Runs both halves, then reports the heartbeat.
 *
 * `pingDeadMan` is E12's seam — `lib/log.ts:255` says so in as many words:
 * "This is the seam E07 and E09 call." It never throws, so it cannot turn a
 * monitoring problem into a dispatch problem, and it emits its `cron.heartbeat`
 * line even with no monitor URL configured, so an alert can be built on the log
 * stream today ("no `cron.heartbeat` with job=scheduled-dispatch in 15 min").
 *
 * The job name is `scheduled-dispatch`, byte-identical to the string registered
 * in `cron/scheduled.ts` — **E02's** file, not touched here.
 *
 * A failure pings first, marked `ok: false`, and *then* rethrows. E02's
 * dispatcher fails the whole invocation on a thrown job, which is the property
 * that makes a broken cron visible in Cloudflare at all (F-22-03); swallowing
 * the error to keep the heartbeat green would undo exactly that fix.
 */
export async function runScheduledDispatchJob({ env, now }: CronJobInput): Promise<void> {
  const startedAt = Date.now();
  let dispatched = 0;
  let dispatchFailures = 0;
  let expired = 0;

  try {
    const scheduled = await dispatchDueScheduledTrips(env, now);
    dispatched = scheduled.dispatched;
    dispatchFailures = scheduled.failed;
    expired = await sweepUnfulfilledTrips(env, now);
  } catch (e) {
    await pingDeadMan("scheduled-dispatch", env, {
      ok: false,
      durationMs: Date.now() - startedAt,
      detail: { dispatched, expired, error: e instanceof Error ? e.message : String(e) },
    });
    throw e;
  }

  // A tick where some rows failed is not a healthy tick, even though the
  // surviving rows were processed. Report it as a failure and fail the
  // invocation — a partial dispatch reporting success is how a cron rots.
  const ok = dispatchFailures === 0;
  await pingDeadMan("scheduled-dispatch", env, {
    ok,
    durationMs: Date.now() - startedAt,
    detail: { dispatched, dispatchFailures, expired, ttlMinutes: UNFULFILLED_TTL_MINUTES },
  });

  if (!ok) {
    throw new Error(
      `scheduled-dispatch: ${dispatchFailures} scheduled trip(s) failed to dispatch`,
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Scheduled rides
// ---------------------------------------------------------------------------

/**
 * Dispatch every scheduled trip whose time has come.
 *
 * One row at a time, one failure at a time: a row that throws is marked
 * `failed`, counted, and the loop continues. Letting the first error propagate
 * would let one bad trip suppress every later one in the same tick — the same
 * reasoning E02 applied to the job registry itself.
 */
async function dispatchDueScheduledTrips(
  env: Env,
  now: string,
): Promise<{ dispatched: number; failed: number }> {
  const due = await env.DB.prepare(
    `SELECT d.id AS dispatch_id, d.trip_id, t.rider_id, t.pickup_lat, t.pickup_lng,
            t.dropoff_lat, t.dropoff_lng, t.city, t.estimated_fare, t.currency
     FROM scheduled_trip_dispatch d
     JOIN trips t ON t.id = d.trip_id
     WHERE d.status = 'pending'
       AND datetime(d.scheduled_for) <= datetime(?)
       AND t.status = 'searching'`,
  )
    .bind(now)
    .all<DueScheduledTrip>();

  let dispatched = 0;
  let failed = 0;

  for (const row of due.results ?? []) {
    // Claim the row before doing any work. Two overlapping ticks — a slow one
    // and the next minute's — would otherwise both dispatch the same trip and
    // wake every nearby captain twice. `changes === 0` means the other tick
    // won; leave it alone.
    const claim = await env.DB.prepare(
      `UPDATE scheduled_trip_dispatch SET status = 'dispatched', dispatched_at = ?
       WHERE id = ? AND status = 'pending'`,
    )
      .bind(now, row.dispatch_id)
      .run();
    if (claim.meta && claim.meta.changes === 0) continue;

    try {
      const result = await dispatchTrip({
        env,
        tripId: row.trip_id,
        city: row.city,
        pickupLat: row.pickup_lat,
        pickupLng: row.pickup_lng,
        dropoffLat: row.dropoff_lat,
        dropoffLng: row.dropoff_lng,
        estimatedFare: row.estimated_fare ?? 0,
        currency: row.currency,
        // No actor id: the scheduler dispatched this, not a person.
      });

      // Keep `trips.schedule_status` honest. `0003` documents the vocabulary as
      // pending/dispatched/expired and nothing has ever advanced it past
      // `pending` — a column written once at booking and never maintained is
      // the same R3 shape as a value defined and never read.
      await env.DB.prepare(
        `UPDATE trips SET schedule_status = 'dispatched', updated_at = ? WHERE id = ?`,
      )
        .bind(now, row.trip_id)
        .run();

      await writeTripEvent(env.DB, row.trip_id, "scheduled.dispatched", undefined, {
        dispatchId: row.dispatch_id,
        status: result.status,
        candidates: result.captains.length,
      });

      dispatched += 1;
      counter("scheduled_trip_dispatched", 1, { status: result.status });
      logInfo("cron.scheduled_dispatch.dispatched", {
        tripId: row.trip_id,
        status: result.status,
        candidates: result.captains.length,
      });

      // Tell the rider their scheduled ride has gone out to captains. Without
      // this the first thing they hear about a ride booked yesterday is either
      // a captain accepting or, ten minutes later, the sweeper's apology.
      await pushToUser({
        env,
        userId: row.rider_id,
        topic: "trip.scheduled.dispatched",
        title: "جاري البحث عن كابتن",
        body: "حان موعد رحلتك المجدولة. نبحث لك عن كابتن الآن.",
        data: { tripId: row.trip_id, status: result.status },
      }).catch((e) => console.error("scheduled dispatch rider push failed", row.trip_id, e));

      // Kept from the pre-E09 job: operators watching the scheduled queue still
      // get their notification. Best-effort and secondary now — it used to be
      // the *entire* body of this job, which is what gate item 9 is about.
      await notifyAdmins(env, row).catch((e) =>
        console.error("scheduled dispatch admin push failed", row.trip_id, e),
      );
    } catch (e) {
      failed += 1;
      counter("scheduled_trip_dispatch_failed", 1, {});
      logWarn("cron.scheduled_dispatch.failed", {
        tripId: row.trip_id,
        dispatchId: row.dispatch_id,
        reason: e instanceof Error ? e.message : String(e),
      });
      // Honest state: the row says what happened. The trip stays `searching`,
      // so the sweeper below terminates it on the TTL rather than leaving the
      // rider blocked — a failed dispatch must not become a bricked account.
      try {
        await env.DB.prepare(
          `UPDATE scheduled_trip_dispatch SET status = 'failed' WHERE id = ?`,
        )
          .bind(row.dispatch_id)
          .run();
      } catch (inner) {
        console.error("scheduled dispatch failure-mark failed", row.dispatch_id, inner);
      }
    }
  }

  return { dispatched, failed };
}

async function notifyAdmins(env: Env, row: DueScheduledTrip): Promise<void> {
  const admins = await env.DB.prepare(`SELECT id FROM users WHERE role = 'admin'`).all<{
    id: string;
  }>();
  for (const admin of admins.results ?? []) {
    await pushToUser({
      env,
      userId: admin.id,
      topic: "scheduled.trip.dispatch",
      title: "رحلة مجدولة نشطة الآن",
      body: `الرحلة ${row.trip_id} تم تفعيلها في ${row.city}.`,
      data: { tripId: row.trip_id },
    });
  }
}

// ---------------------------------------------------------------------------
// 2. The expiry sweeper
// ---------------------------------------------------------------------------

/**
 * Terminate trips that have been waiting too long, and tell the rider.
 *
 * ## The clock starts when dispatch starts, not when the row was written
 *
 * `COALESCE(scheduled_for, created_at)` is the whole trick. A live trip is
 * measured from creation; a scheduled trip from the moment it was *due*. A ride
 * booked today for 07:00 tomorrow therefore cannot be swept before 07:10
 * tomorrow, because `datetime(scheduled_for) < datetime(now, -10 minutes)` is
 * false at every instant until then. Measuring from `created_at` would cancel
 * every scheduled ride ten minutes after booking — turning the fix for gate
 * item 9 into a more efficient version of the bug it replaces.
 */
async function sweepUnfulfilledTrips(env: Env, now: string): Promise<number> {
  const cutoff = new Date(Date.parse(now) - UNFULFILLED_TTL_MINUTES * 60_000).toISOString();

  const stale = await env.DB.prepare(
    `SELECT id, rider_id, status, scheduled_for
     FROM trips
     WHERE status IN ('searching', 'offered')
       AND datetime(COALESCE(scheduled_for, created_at)) < datetime(?)
     LIMIT ?`,
  )
    .bind(cutoff, SWEEP_BATCH)
    .all<ExpiringTrip>();

  const rows = stale.results ?? [];
  if (rows.length === 0) return 0;

  let swept = 0;
  for (const trip of rows) {
    // The race that matters: a captain tapping accept in this same second.
    // Repeating the status in the WHERE means the accept wins and the sweep
    // silently declines to cancel a trip that now has a driver on the way.
    const res = await env.DB.prepare(
      `UPDATE trips SET status = 'cancelled', cancel_reason = ?, cancelled_at = ?, updated_at = ?,
              schedule_status = CASE WHEN scheduled_for IS NOT NULL THEN 'expired' ELSE schedule_status END
       WHERE id = ? AND status IN ('searching', 'offered')`,
    )
      .bind(EXPIRY_REASON, now, now, trip.id)
      .run();

    if (res.meta && res.meta.changes === 0) {
      counter("trip_expiry_lost_race", 1, {});
      continue;
    }

    swept += 1;
    counter("trip_expired_unfulfilled", 1, { from: trip.status });
    logInfo("cron.trip_expiry.swept", {
      tripId: trip.id,
      previousStatus: trip.status,
      scheduled: trip.scheduled_for != null,
      ttlMinutes: UNFULFILLED_TTL_MINUTES,
    });

    try {
      await writeTripEvent(env.DB, trip.id, "expired", undefined, {
        reason: EXPIRY_REASON,
        previousStatus: trip.status,
        ttlMinutes: UNFULFILLED_TTL_MINUTES,
      });
    } catch (e) {
      console.error("expiry event write failed", trip.id, e);
    }

    // A scheduled-dispatch row still pending for a trip that just died is never
    // going to fire. Say so rather than leaving it `pending` forever.
    try {
      await env.DB.prepare(
        `UPDATE scheduled_trip_dispatch SET status = 'failed' WHERE trip_id = ? AND status = 'pending'`,
      )
        .bind(trip.id)
        .run();
    } catch (e) {
      console.error("expiry scheduled-row close failed", trip.id, e);
    }

    await tearDownOfferRollout(env, trip.id);
    await revokeTokensForTrip(env, trip.id);
    await announceExpiry(env, trip);
  }

  return swept;
}

/**
 * Stop the staged rollout for a trip that just died.
 *
 * `OfferScheduler.alarm()` already re-reads the status and tears itself down,
 * so this is not load-bearing for correctness — it stops up to one further wave
 * of offer cards reaching captains inside the 15 s before the next alarm, and
 * releases the DO's storage now rather than at the end of the rollout. Same
 * call `POST /trips/:id/cancel` makes.
 */
async function tearDownOfferRollout(env: Env, tripId: string): Promise<void> {
  try {
    const scheduler = env.OFFER_SCHEDULER.get(env.OFFER_SCHEDULER.idFromName(tripId));
    await scheduler.fetch("https://scheduler/cancel", { method: "POST" });
  } catch (e) {
    console.error("expiry: offer scheduler teardown failed", tripId, e);
  }
}

/**
 * Revoke any live share token — E13's seam, wired at every terminal transition.
 *
 * A trip that ended must not leave a live tracking link behind, and "ended"
 * includes "expired without ever finding a captain". `revokeShareToken` is
 * idempotent (`revoked_at IS NULL` guard), so a retried sweep is free.
 *
 * Loud on failure and non-fatal: a token outliving its trip is a safety problem
 * worth a counter and a log line, and failing the sweep over it would leave the
 * rider bricked, which is the larger of the two harms.
 */
async function revokeTokensForTrip(env: Env, tripId: string): Promise<void> {
  try {
    const revoked = await revokeShareToken(env.DB, tripId);
    if (revoked > 0) counter("share_token_revoked", revoked, { at: "expiry" });
  } catch (e) {
    counter("share_token_revoke_failed", 1, { at: "expiry" });
    logWarn("safety.share_token_revoke_failed", {
      tripId,
      at: "expiry",
      reason: e instanceof Error ? e.message : String(e),
    });
  }
}

/**
 * Tell the rider, on both channels.
 *
 * The push reaches a closed app; the trip-room broadcast reaches one that is
 * open on the trip screen with a socket attached. Doing only the first leaves a
 * waiting rider watching a spinner for a trip that no longer exists — the
 * bricked state this whole job exists to end.
 *
 * The room write is the same pair of calls `broadcastTrip` makes in
 * `routes/trips.ts`. It is repeated rather than imported because that helper
 * closes over `withCaptain`, which lives in the route module, and importing a
 * Hono router into a cron to reuse ten lines is the worse trade. An expired
 * trip has no `captain_id`, so the enrichment `broadcastTrip` adds would be a
 * no-op here in any case. Both belong in a shared module the day one is owned.
 */
async function announceExpiry(env: Env, trip: ExpiringTrip): Promise<void> {
  try {
    const updated = await env.DB.prepare(`SELECT * FROM trips WHERE id = ?`)
      .bind(trip.id)
      .first();
    if (updated) {
      const room = env.TRIP_ROOM.get(env.TRIP_ROOM.idFromName(trip.id));
      await room.fetch("https://room/broadcast", {
        method: "POST",
        body: JSON.stringify({ type: "trip.updated", trip: updated }),
      });
      await room.fetch("https://room/state", {
        method: "PUT",
        body: JSON.stringify(updated),
      });
    }
  } catch (e) {
    console.error("expiry broadcast failed", trip.id, e);
  }

  try {
    await pushToUser({
      env,
      userId: trip.rider_id,
      topic: "trip.expired",
      title: "لم نجد كابتن متاح",
      body: "نعتذر — لم يقبل أي كابتن رحلتك. تم إغلاق الطلب ويمكنك طلب رحلة جديدة الآن.",
      data: { tripId: trip.id, status: "cancelled", reason: EXPIRY_REASON },
    });
  } catch (e) {
    console.error("expiry push failed", trip.id, e);
  }
}
