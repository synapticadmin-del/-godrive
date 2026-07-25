-- Migration 0005: Idempotency Key & Integer Currency (Piastres) Support

-- Add idempotency_key to wallet_transactions for duplicate transaction prevention
ALTER TABLE wallet_transactions ADD COLUMN idempotency_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_wt_idem ON wallet_transactions(idempotency_key);

-- Add integer piastres fields for zero-floating-point financial accounting (1 EGP = 100 Piastres)
ALTER TABLE wallet_transactions ADD COLUMN amount_piastres INTEGER;
ALTER TABLE trips ADD COLUMN estimated_fare_piastres INTEGER;
ALTER TABLE trips ADD COLUMN final_fare_piastres INTEGER;
ALTER TABLE trips ADD COLUMN commission_piastres INTEGER;
ALTER TABLE users ADD COLUMN wallet_balance_piastres INTEGER DEFAULT 0;

-- Backfill integer piastres from existing REAL values where applicable
UPDATE wallet_transactions SET amount_piastres = CAST(ROUND(amount * 100) AS INTEGER) WHERE amount_piastres IS NULL;
UPDATE trips SET estimated_fare_piastres = CAST(ROUND(estimated_fare * 100) AS INTEGER) WHERE estimated_fare_piastres IS NULL AND estimated_fare IS NOT NULL;
UPDATE trips SET final_fare_piastres = CAST(ROUND(final_fare * 100) AS INTEGER) WHERE final_fare_piastres IS NULL AND final_fare IS NOT NULL;
UPDATE trips SET commission_piastres = CAST(ROUND(commission * 100) AS INTEGER) WHERE commission_piastres IS NULL AND commission IS NOT NULL;
UPDATE users SET wallet_balance_piastres = CAST(ROUND(wallet_balance * 100) AS INTEGER) WHERE wallet_balance IS NOT NULL;
