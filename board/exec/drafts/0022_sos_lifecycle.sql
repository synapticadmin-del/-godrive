-- 0022: SOS lifecycle — an alert an operator can actually work
--
-- E13 / launch-gate item 10. Number 0022 reserved for E13 in
-- board/exec/MIGRATION-LOCK.md; never guessed from the directory listing.
--
-- Item 10 is split four ways (E05, E09, E13, E14) — see WAVE-PLAN §4. This
-- migration is the schema half of E13's share only. It does not close the item.
--
-- Forward-only and deliberately additive: one CREATE TABLE, three ALTER TABLE
-- ADD COLUMNs, two triggers, three indexes. No table is rebuilt and NOT ONE
-- EXISTING ROW IS REWRITTEN, so this migration contains no backfill —
-- irreversible or otherwise. It is not a fifth alongside 0005/0009/0017/0018.
--
-- Rollback (forward repair, per PROTOCOL-EXEC §6):
--   DROP TRIGGER sos_alert_events_no_update;
--   DROP TRIGGER sos_alert_events_no_delete;
--   DROP TABLE sos_alert_events;
--   DROP INDEX idx_sos_alerts_queue;
--   DROP INDEX idx_share_tokens_expiry;
--   UPDATE sos_alerts SET acknowledged_at = NULL, acknowledged_by = NULL, resolved_by = NULL;
-- leaving the three columns in place but unread. Dropping them for real needs
-- the table rebuild rehearsed under E18's restore. Nothing here is destructive,
-- so the rollback loses only operator annotations written after the deploy.

-- ---------------------------------------------------------------------------
-- 1) The escalation trail, append-only.
-- ---------------------------------------------------------------------------
-- F-17-04: `sos_alerts` is INSERT-only in practice. `status` and `resolved_at`
-- exist (0003:170,172) and are never written a second time by any code path, so
-- an alert has exactly two observable states — it happened, and that is all.
--
-- The brief requires escalation as immutable event rows rather than a mutated
-- status field, and that is the right shape for a reason beyond tidiness: this
-- is the evidence trail for a passenger emergency. "Who saw it, when, and what
-- did they do" is the question that gets asked afterwards, and a single mutable
-- column cannot answer it. An UPDATE would destroy the fact we need to prove.
--
-- Note there is NO `ON DELETE CASCADE` on alert_id, deliberately. With the
-- append-only trigger below, an attempt to delete an alert that has a trail
-- fails on the foreign key instead of silently taking the evidence with it.
-- Verified before relying on it: nothing deletes from `sos_alerts` today —
-- `lib/cleanup.ts` touches only `otp_codes` and `refresh_tokens`.
CREATE TABLE IF NOT EXISTS sos_alert_events (
  id TEXT PRIMARY KEY,
  alert_id TEXT NOT NULL REFERENCES sos_alerts(id),
  event TEXT NOT NULL CHECK (event IN (
    'raised',        -- the rider or captain pressed the button
    'acknowledged',  -- a named operator has it
    'escalated',     -- handed to a supervisor or an external service
    'contacted',     -- someone spoke to the person who raised it
    'resolved',
    'false_alarm',
    'note'           -- free text, changes no state
  )),
  actor_id TEXT REFERENCES users(id),   -- NULL = system / automated
  actor_role TEXT CHECK (actor_role IN ('rider', 'captain', 'admin', 'system')),
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- The console reads one alert's trail oldest-first, and the dead-man report
-- reads "events in the last N minutes". Both are served by this ordering.
CREATE INDEX IF NOT EXISTS idx_sos_alert_events_alert
  ON sos_alert_events(alert_id, created_at);

-- Append-only enforced by the database, not by convention. A convention holds
-- until the first chat that has not read this comment writes an UPDATE.
CREATE TRIGGER IF NOT EXISTS sos_alert_events_no_update
BEFORE UPDATE ON sos_alert_events
BEGIN
  SELECT RAISE(ABORT, 'sos_alert_events is append-only: record a correction as a new row');
END;

CREATE TRIGGER IF NOT EXISTS sos_alert_events_no_delete
BEFORE DELETE ON sos_alert_events
BEGIN
  SELECT RAISE(ABORT, 'sos_alert_events is append-only: an SOS trail is evidence and is not deletable');
END;

-- ---------------------------------------------------------------------------
-- 2) The three facts the operator queue needs on the alert row itself.
-- ---------------------------------------------------------------------------
-- Denormalised from the trail on purpose: the queue screen sorts and filters on
-- these, and deriving them per row from an events table is the query that gets
-- slow exactly when the queue is busiest.
--
-- IMPORTANT — there is deliberately no new `status` value. `sos_alerts.status`
-- carries CHECK (status IN ('open','resolved','false_alarm')) from 0003:170.
-- SQLite cannot widen a CHECK without a full table rebuild, and rebuilding a
-- live safety table to add one enum member is not a trade worth making. So:
--
--     acknowledged  ==  status = 'open' AND acknowledged_at IS NOT NULL
--
-- The queue is "everything still open, oldest first"; acknowledgement is a
-- property of an open alert, not a state that replaces it. That also happens to
-- be the truthful model — an acknowledged emergency is still an emergency.
ALTER TABLE sos_alerts ADD COLUMN acknowledged_at TEXT;
ALTER TABLE sos_alerts ADD COLUMN acknowledged_by TEXT REFERENCES users(id);
ALTER TABLE sos_alerts ADD COLUMN resolved_by TEXT REFERENCES users(id);

-- The operator queue: open alerts, oldest first. 0003:175 indexes created_at
-- alone, which cannot serve the status filter; this is the composite the screen
-- actually issues.
CREATE INDEX IF NOT EXISTS idx_sos_alerts_queue
  ON sos_alerts(status, created_at);

-- ---------------------------------------------------------------------------
-- 3) Make the share-token sweep affordable.
-- ---------------------------------------------------------------------------
-- E13 exports purgeExpiredShareTokens() for E09 to call on a schedule (seam
-- ruling, WAVE-PLAN §7). That sweep is `WHERE expires_at < ?`, and
-- trip_share_tokens carries exactly one index — idx_share_trip on trip_id
-- (0003:185) — so today the sweep is a full table scan on a table that grows
-- with every shared trip and is never pruned.
--
-- No column is added: `revoked_at` already exists at 0003:181. revokeShareToken()
-- needs no schema change at all, which is worth stating plainly because the
-- brief reads as though it might.
CREATE INDEX IF NOT EXISTS idx_share_tokens_expiry
  ON trip_share_tokens(expires_at);
