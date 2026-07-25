-- Migration 0006: OTP attempts counter & wallet idempotency index

-- Add attempts counter to otp_codes table if missing
ALTER TABLE otp_codes ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;

-- Ensure unique index on idempotency_key for wallet_transactions
CREATE UNIQUE INDEX IF NOT EXISTS idx_wt_idem ON wallet_transactions(idempotency_key);
