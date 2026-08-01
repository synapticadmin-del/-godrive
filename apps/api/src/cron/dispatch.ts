import { pushToUser } from "../lib/notifications";
import type { CronJobInput } from "./types";

type DueScheduledTrip = {
  dispatch_id: string;
  trip_id: string;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_lat: number;
  dropoff_lng: number;
  city: string;
  estimated_fare: number;
  currency: string;
};

/**
 * Dispatch due scheduled trips: flip status to searching and send offers.
 *
 * Lifted verbatim out of the `scheduled` handler in `index.ts`. Two mechanical
 * changes, neither behavioural: the swallowing `try/catch` is gone (the
 * dispatcher owns failure now), and the per-iteration
 * `await import("../lib/notifications")` became a module-level import — same
 * module, same function, no cycle, resolved once instead of once per row.
 *
 * E09 owns this file next and is the task that makes the dispatch itself
 * correct; nothing in here was fixed on the way past.
 */
export async function runScheduledDispatchJob({ env, now }: CronJobInput): Promise<void> {
  const due = await env.DB.prepare(
    `SELECT d.id AS dispatch_id, d.trip_id, t.pickup_lat, t.pickup_lng, t.dropoff_lat,
            t.dropoff_lng, t.city, t.estimated_fare, t.currency
     FROM scheduled_trip_dispatch d
     JOIN trips t ON t.id = d.trip_id
     WHERE d.status = 'pending' AND d.scheduled_for <= ?
       AND t.status = 'searching'`,
  )
    .bind(now)
    .all();

  for (const row of (due.results ?? []) as DueScheduledTrip[]) {
    // Mark dispatched to avoid duplicate processing
    await env.DB.prepare(
      `UPDATE scheduled_trip_dispatch SET status = 'dispatched', dispatched_at = ? WHERE id = ? AND status = 'pending'`,
    )
      .bind(now, row.dispatch_id)
      .run();

    // Push a notification to admins (the actual /trips create already
    // drives nearest-captain matching through GeoCell; scheduled trips
    // flip their status to `offered` automatically once a captain sees
    // them in their inbox).
    const admins = await env.DB.prepare(`SELECT id FROM users WHERE role = 'admin'`).all<{ id: string }>();
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
}
