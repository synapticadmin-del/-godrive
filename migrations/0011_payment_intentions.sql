-- =====================================================================
-- Synaptic Go migration 0011 — Payment intentions + index hardening
-- Server-side source of truth for Paymob intentions so webhook crediting
-- can verify amount + purpose before touching the wallet.
-- Compatible with D1 (SQLite). Runs after 0010_intercity_booking_cancel.sql.
-- =====================================================================

CREATE TABLE IF NOT EXISTS payment_intentions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  order_id TEXT NOT NULL UNIQUE,
  amount_piastres INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'EGP',
  purpose TEXT NOT NULL DEFAULT 'wallet_topup',
  trip_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  settled_at TEXT
);

-- order_id already has a UNIQUE index; index the user lookup instead.
CREATE INDEX IF NOT EXISTS idx_payment_intentions_user ON payment_intentions(user_id);

-- Hot lookup pattern for trip dispatch / listing queries.
CREATE INDEX IF NOT EXISTS idx_trips_city_status_created ON trips(city, status, created_at);

-- Phone is the primary identity in the Egypt market; it had no index.
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

-- trips had no payment_status column in 0001; track paid/unpaid per trip.
ALTER TABLE trips ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'unpaid';
