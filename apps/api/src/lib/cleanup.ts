import { logAudit } from "./audit";

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
 */

export type CleanupResult = {
  otpCodes: number | null;
  refreshTokens: number | null;
};

async function countRun(
  stmt: D1PreparedStatement,
): Promise<number | null> {
  const res = await stmt.run();
  const changes = res.meta?.changes;
  return typeof changes === "number" ? changes : null;
}

export async function runExpiredDataCleanup(env: Env): Promise<CleanupResult> {
  const result: CleanupResult = { otpCodes: null, refreshTokens: null };

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

  try {
    await logAudit(env.DB, {
      actorId: null,
      action: "system.cleanup",
      entityType: "system",
      entityId: "expired-data",
      payload: {
        otp_codes: result.otpCodes,
        refresh_tokens: result.refreshTokens,
      },
    });
  } catch (e) {
    console.error("cleanup: audit failed", e);
  }

  return result;
}
