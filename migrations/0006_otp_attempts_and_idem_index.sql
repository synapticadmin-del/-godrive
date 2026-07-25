-- Migration 0006: OTP attempts counter & wallet idempotency index

-- NOTE: otp_codes.attempts is already added by migration 0005 (line 22).
-- Repeating the ALTER here raised "duplicate column name: attempts", which
-- aborted this migration and every migration queued after it. SQLite has no
-- "ADD COLUMN IF NOT EXISTS", so the statement is removed rather than guarded.
-- Intentionally left out: ALTER TABLE otp_codes ADD COLUMN attempts ...

-- Ensure unique index on idempotency_key for wallet_transactions
CREATE UNIQUE INDEX IF NOT EXISTS idx_wt_idem ON wallet_transactions(idempotency_key);
