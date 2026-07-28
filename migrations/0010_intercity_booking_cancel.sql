-- =====================================================================
-- Synaptic Go migration 0010 — Intercity booking cancellation
-- Tracks when a booking was cancelled (refund policy + audit).
-- Compatible with D1 (SQLite). Runs after 0009_captain_city.sql.
-- =====================================================================

ALTER TABLE intercity_bookings ADD COLUMN cancelled_at TEXT;

CREATE INDEX IF NOT EXISTS idx_int_book_status ON intercity_bookings(status);
