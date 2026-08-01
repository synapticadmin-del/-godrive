import { id, nowIso } from "./utils";
import { counter, logError, logWarn } from "./log";

/**
 * Audit log writes.
 *
 * Two findings meet in this file.
 *
 * **F-22-07 (S-414) — `logAudit` swallows every write failure.** The old body
 * caught the error, wrote `console.error("audit log failed", e)` and returned.
 * Nothing counted it, nothing alerted on it, and the caller could not tell a
 * written row from a lost one. An audit trail that fails silently is worse than
 * no audit trail, because everyone downstream believes it is complete.
 *
 * **F-22-05 (S-038) — the money path writes no audit rows at all.**
 * `trips.ts:20` imports `logAudit` and never calls it, so a fare dispute has no
 * authoritative record. That is gate item 14's "`logAudit` actually called on
 * the trip-completion money path", and **the call site is not in this task's
 * `owns:`** — it lands in `lib/settlement.ts`, which E03 extracts and E08 then
 * owns. E08's brief says so explicitly: *"Call `logAudit` (from E12's
 * `lib/audit.ts`) on the completion path inside `settlement.ts`"*.
 *
 * So this file is the seam and E08 is the caller. What E12 can do is make the
 * write **observable** — countable on failure, and loud when the thing that was
 * lost was a money record.
 */

export type AuditWriteResult = {
  /** False when the row was not persisted. Callers may ignore it; money paths should not. */
  ok: boolean;
  /** The generated row id, present whether or not the write landed. */
  id: string;
  error?: string;
};

export type AuditOptions = {
  actorId?: string | null;
  action: string;
  entityType?: string;
  entityId?: string;
  payload?: unknown;
  ip?: string | null;
  userAgent?: string | null;
  /**
   * Mark this as a record whose loss has consequences — settlement, payout,
   * refund. Failures on a critical row log at `error` and increment their own
   * counter, so "we lost a fare record" is separable from "we lost a login
   * record" in an alert rule.
   *
   * This is the flag E08 sets on the completion path.
   */
  critical?: boolean;
  /** Correlation id, when the caller has one (`getRequestId(c)`). */
  requestId?: string;
};

/**
 * Write one audit row.
 *
 * **Still never throws.** That property is deliberate and is kept: an audit
 * failure must not break the request that triggered it, or a D1 hiccup during
 * settlement becomes a rider who cannot end a trip. The change is that the
 * failure is now *counted and returned* rather than swallowed — the caller can
 * react, and someone watching can see it happen.
 *
 * The return type widened from `Promise<void>`; every existing `await` call site
 * keeps compiling unchanged.
 */
export async function logAudit(
  db: D1Database,
  opts: AuditOptions,
): Promise<AuditWriteResult> {
  const rowId = id("aud");

  try {
    await db
      .prepare(
        `INSERT INTO audit_log (id, actor_id, action, entity_type, entity_id, payload, ip, user_agent, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        rowId,
        opts.actorId ?? null,
        opts.action,
        opts.entityType ?? null,
        opts.entityId ?? null,
        opts.payload ? JSON.stringify(opts.payload) : null,
        opts.ip ?? null,
        opts.userAgent ?? null,
        nowIso(),
      )
      .run();

    return { ok: true, id: rowId };
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);

    // The counter is the acceptance criterion: "an audit-write failure
    // increments a counter someone can see". `metric = "audit_write_failed"`
    // is queryable in Workers Logs and is the predicate an alert sits on.
    counter("audit_write_failed", 1, {
      action: opts.action,
      critical: opts.critical === true,
    });

    const fields = {
      auditId: rowId,
      action: opts.action,
      entityType: opts.entityType,
      entityId: opts.entityId,
      actorId: opts.actorId,
      requestId: opts.requestId,
      reason: error,
    };

    // A lost money record is an incident; a lost routine record is a warning.
    if (opts.critical) {
      logError("audit.write_failed.critical", fields);
    } else {
      logWarn("audit.write_failed", fields);
    }

    return { ok: false, id: rowId, error };
  }
}
