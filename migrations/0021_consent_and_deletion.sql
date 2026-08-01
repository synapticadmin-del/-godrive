-- 0021: Consent records, account deletion tombstones, and public deletion requests
--
-- E16 / launch-gate item 12. Number 0021 taken from board/exec/MIGRATION-LOCK.md
-- (0020 went to E06); never guessed from the directory listing.
--
-- Forward-only, and deliberately additive: three CREATE TABLEs, two ALTER TABLE
-- ADD COLUMNs and two triggers. No table is rebuilt and no existing row is
-- rewritten, so this migration contains no backfill — irreversible or otherwise.
-- It is therefore NOT a fifth irreversible backfill alongside 0005/0009/0017/0018.
--
-- Rollback (forward repair, per PROTOCOL-EXEC §6): D1/SQLite cannot DROP COLUMN
-- on a table with dependent indexes without a rebuild, so the repair migration is
--   DROP TRIGGER user_consents_no_update;
--   DROP TRIGGER user_consents_no_delete;
--   DROP TABLE user_consents;
--   DROP TABLE account_deletion_requests;
--   UPDATE users SET deleted_at = NULL, deletion_reason = NULL;
--   DROP INDEX idx_users_deleted_at;
-- leaving users.deleted_at / users.deletion_reason in place but unread. Dropping
-- the two columns for real means the table rebuild rehearsed under E18's restore.

-- ---------------------------------------------------------------------------
-- 1) Consent, recorded server-side and append-only.
-- ---------------------------------------------------------------------------
-- F-25-02: today the terms checkbox is client-side only, so nothing anywhere
-- records that a user agreed, to which document, or when. Withdrawal is a NEW
-- ROW, never an UPDATE — the history is the evidence, and an UPDATE would
-- destroy the very fact we need to prove.
--
-- Deliberately no ip / user_agent column. Those are personal data that erasure
-- would have to redact, and redaction means UPDATE, which this table forbids.
-- The request metadata goes to audit_log instead, which is not append-only, so
-- consent rows can lawfully outlive an erasure attached to the tombstoned id.
CREATE TABLE IF NOT EXISTS user_consents (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  document TEXT NOT NULL CHECK (document IN ('privacy_policy', 'terms_of_service')),
  version TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('granted', 'withdrawn')),
  source TEXT NOT NULL CHECK (source IN ('rider_app', 'captain_app', 'web', 'admin')),
  locale TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- "Current consent for this user and document" is the newest row, so the index
-- is ordered to make that a single backwards scan.
CREATE INDEX IF NOT EXISTS idx_user_consents_lookup
  ON user_consents(user_id, document, created_at);

-- Append-only enforced by the database, not by convention. A convention holds
-- until the first chat that has not read this comment writes an UPDATE.
CREATE TRIGGER IF NOT EXISTS user_consents_no_update
BEFORE UPDATE ON user_consents
BEGIN
  SELECT RAISE(ABORT, 'user_consents is append-only: record a withdrawal as a new row');
END;

CREATE TRIGGER IF NOT EXISTS user_consents_no_delete
BEFORE DELETE ON user_consents
BEGIN
  SELECT RAISE(ABORT, 'user_consents is append-only: record a withdrawal as a new row');
END;

-- ---------------------------------------------------------------------------
-- 2) Deletion tombstones on users.
-- ---------------------------------------------------------------------------
-- Soft delete, because the financial ledger (wallet_transactions, user_credits,
-- trips.final_fare/commission) references users(id) and must keep balancing
-- after erasure. The row survives; every identifier in it does not.
--
-- users.status is CHECK (status IN ('active','suspended','pending')) from
-- 0001_init.sql:10 and adding a 'deleted' member would mean rebuilding the
-- table. deleted_at is the authority instead; status is set to 'suspended'.
ALTER TABLE users ADD COLUMN deleted_at TEXT;
ALTER TABLE users ADD COLUMN deletion_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);

-- ---------------------------------------------------------------------------
-- 3) Public (unauthenticated) deletion requests.
-- ---------------------------------------------------------------------------
-- Google Play and the App Store both require a deletion route reachable without
-- installing the app. That route cannot delete on the spot: it is unauthenticated,
-- so acting on it directly would let anyone erase any account by typing an email
-- address. It records an intent for an operator to action, and answers
-- identically whether or not the address matches an account (no enumeration).
CREATE TABLE IF NOT EXISTS account_deletion_requests (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  user_id TEXT REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'rejected', 'cancelled')),
  source TEXT NOT NULL DEFAULT 'web'
    CHECK (source IN ('web', 'rider_app', 'captain_app', 'support')),
  note TEXT,
  ip TEXT,
  user_agent TEXT,
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_adr_status ON account_deletion_requests(status, requested_at);
CREATE INDEX IF NOT EXISTS idx_adr_email ON account_deletion_requests(email);
