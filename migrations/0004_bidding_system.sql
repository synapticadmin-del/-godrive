-- Migration 0004: Dynamic Bidding & Price Negotiation System

CREATE TABLE IF NOT EXISTS trip_bids (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  captain_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  counter_price REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trip_bids_trip ON trip_bids(trip_id);
CREATE INDEX IF NOT EXISTS idx_trip_bids_captain ON trip_bids(captain_id);

-- Alter trips table for bidding fields if missing
ALTER TABLE trips ADD COLUMN offered_price REAL;
ALTER TABLE trips ADD COLUMN accepted_price REAL;
ALTER TABLE trips ADD COLUMN bidding_mode INTEGER DEFAULT 1;
