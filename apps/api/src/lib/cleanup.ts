import { purgeExpiredShareTokens } from "../routes/safety";
import { logAudit } from "./audit";
import { counter } from "./log";

/**
 * Daily expired-data cleanup.
 *
 * Runs from the scheduled (cron) handler. Each DELETE is wrapped in its own
 * try/catch so a single failure (e.g. a locked table) never blocks the rest,
 * and every run writes one audit row (`system.cleanup`) with the deleted
 * counts.
 *
 * NOTE: `turnstile_verifications` does not exist in the current migrations
 * (0001–0010), so it is intentionally omitted here. If a later migration adds
 * it, purge rows older than 30 days the same way.
 *
 * ---
 *
 * ## E09: share tokens are collected here
 *
 * E13 exports [purgeExpiredShareTokens] and is forbidden from touching any cron
 * file or `routes/trips.ts`, so the call site is E09's (WAVE-PLAN §7). The
 * brief says "…and `purgeExpiredShareTokens()` from your sweeper", and this is
 * the sweeper it belongs in rather than the every-minute trip-expiry job in
 * `cron/dispatch.ts`:
 *
 *  - This is the *expired-data* pass. It already exists, already runs once a
 *    day behind a KV gate, and already writes one audit row carrying the
 *    deleted counts — which is the record a retention question gets answered
 *    from.
 *  - `trip_share_tokens` expires on a 7-day horizon. Running the DELETE 1,440
 *    times a day to collect rows that age out weekly is waste, and D1 bills it.
 *  - It is the only reason `lib/cleanup.ts` appears in E09's `owns:` at all;
 *    nothing else in the brief's scope touches this file. `MIGRATION-LOCK.md`
 *    reads the same way — the deferred retention sweeper is recorded there as
 *    needing "`cron/` (E02) and `lib/cleanup.ts` (E09) to land first".
 *
 * The import direction (`lib/ → routes/`) is the one E13 chose when it put the
 * primitives in `routes/safety.ts`; it is not a cycle — `routes/safety.ts`
 * imports `lib/utils`, `lib/schemas`, `lib/notifications` and `lib/audit`, and
 * nothing from here.
 */

export type CleanupResult = {
  otpCodes: number | null;
  refreshTokens: number | null;
  /** Expired `trip_share_tokens` rows removed. `null` when the purge failed. */
  shareTokens: number | null;
};

async function countRun(
  stmt: D1PreparedStatement,
): Promise<number | null> {
  const res = await stmt.run();
  const changes = res.meta?.changes;
  return typeof changes === "number" ? changes : null;
}

export async function runExpiredDataCleanup(env: Env): Promise<CleanupResult> {
  const result: CleanupResult = { otpCodes: null, refreshTokens: null, shareTokens: null };

  // OTP codes that expired more than 24 hours ago. Their 1-day grace window
  // keeps recently-expired rows available for rate-limit/audit forensics.
  try {
    result.otpCodes = await countRun(
      env.DB.prepare(`DELETE FROM otp_codes WHERE expires_at < datetime('now', '-1 day')`),
    );
    console.log("cleanup: otp_codes deleted", result.otpCodes);
  } catch (e) {
    console.error("cleanup: otp_codes delete failed", e);
  }

  // Refresh tokens revoked over 7 days ago, or naturally expired over 7 days
  // ago. The 7-day window keeps recent rows for session forensics before
  // pruning.
  try {
    result.refreshTokens = await countRun(
      env.DB.prepare(
        `DELETE FROM refresh_tokens
         WHERE (revoked_at IS NOT NULL AND revoked_at < datetime('now', '-7 days'))
            OR expires_at < datetime('now', '-7 days')`,
      ),
    );
    console.log("cleanup: refresh_tokens deleted", result.refreshTokens);
  } catch (e) {
    console.error("cleanup: refresh_tokens delete failed", e);
  }

  // Share tokens whose lifetime has run out (E13's primitive, E09's call site).
  //
  // Nothing pruned this table before: it is append-only in practice and grows
  // with every shared trip against D1's hard 10 GB ceiling. `0022` added
  // `idx_share_tokens_expiry` so the predicate is an index range scan rather
  // than the full table scan it would otherwise be.
  //
  // The cutoff is left to the primitive's default (now), which is what makes
  // this a *retention* pass and not a revocation one — a token revoked early at
  // trip end is already dead to `/track/:token` and is collected here when it
  // expires. Revocation itself happens at every terminal transition, in
  // `routes/trips.ts` and `cron/dispatch.ts`.
  try {
    const purged = await purgeExpiredShareTokens(env.DB);
    result.shareTokens = purged;
    if (purged > 0) counter("share_tokens_purged", purged, {});
    console.log("cleanup: trip_share_tokens deleted", purged);
  } catch (e) {
    console.error("cleanup: trip_share_tokens delete failed", e);
  }

  try {
    await logAudit(env.DB, {
      actorId: null,
      action: "system.cleanup",
      entityType: "system",
      entityId: "expired-data",
      payload: {
        otp_codes: result.otpCodes,
        refresh_tokens: result.refreshTokens,
        share_tokens: result.shareTokens,
      },
    });
  } catch (e) {
    console.error("cleanup: audit failed", e);
  }

  return result;
}
