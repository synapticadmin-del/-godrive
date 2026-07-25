-- Synaptic Go initial schema

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT,             -- null when using OTP-only; required for email/password mode
  name TEXT,
  phone TEXT,
  role TEXT NOT NULL CHECK (role IN ('rider', 'captain', 'admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'pending')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS otp_codes (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  code TEXT NOT NULL,
  role TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_otp_email ON otp_codes(email);

CREATE TABLE IF NOT EXISTS captains (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  vehicle_make TEXT,
  vehicle_model TEXT,
  vehicle_plate TEXT,
  vehicle_color TEXT,
  license_number TEXT,
  approval_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending', 'approved', 'rejected', 'suspended')),
  is_online INTEGER NOT NULL DEFAULT 0,
  last_lat REAL,
  last_lng REAL,
  last_seen_at TEXT,
  rating_avg REAL NOT NULL DEFAULT 5.0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS pricing_rules (
  city TEXT PRIMARY KEY,
  currency TEXT NOT NULL DEFAULT 'EGP',
  base_fare REAL NOT NULL,
  per_km REAL NOT NULL,
  per_min REAL NOT NULL,
  booking_fee REAL NOT NULL DEFAULT 0,
  min_fare REAL NOT NULL DEFAULT 0,
  commission_rate REAL NOT NULL DEFAULT 0.2,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS trips (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL REFERENCES users(id),
  captain_id TEXT REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'searching',
  city TEXT NOT NULL DEFAULT 'cairo',
  pickup_lat REAL NOT NULL,
  pickup_lng REAL NOT NULL,
  pickup_address TEXT,
  dropoff_lat REAL NOT NULL,
  dropoff_lng REAL NOT NULL,
  dropoff_address TEXT,
  distance_km REAL,
  duration_min REAL,
  currency TEXT NOT NULL DEFAULT 'EGP',
  estimated_fare REAL,
  final_fare REAL,
  commission REAL,
  payment_method TEXT NOT NULL DEFAULT 'cash',
  cancel_reason TEXT,
  captain_lat REAL,
  captain_lng REAL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  assigned_at TEXT,
  arrived_at TEXT,
  started_at TEXT,
  completed_at TEXT,
  cancelled_at TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trips_rider ON trips(rider_id);
CREATE INDEX IF NOT EXISTS idx_trips_captain ON trips(captain_id);
CREATE INDEX IF NOT EXISTS idx_trips_status ON trips(status);
CREATE INDEX IF NOT EXISTS idx_trips_created ON trips(created_at);

CREATE TABLE IF NOT EXISTS trip_events (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  actor_id TEXT,
  type TEXT NOT NULL,
  payload TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trip_events_trip ON trip_events(trip_id);

CREATE TABLE IF NOT EXISTS ratings (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  from_user_id TEXT NOT NULL REFERENCES users(id),
  to_user_id TEXT NOT NULL REFERENCES users(id),
  score INTEGER NOT NULL CHECK (score BETWEEN 1 AND 5),
  comment TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(trip_id, from_user_id)
);

-- Seed default Cairo pricing (EGP)
INSERT OR IGNORE INTO pricing_rules (
  city, currency, base_fare, per_km, per_min, booking_fee, min_fare, commission_rate
) VALUES (
  'cairo', 'EGP', 12, 4.5, 0.5, 3, 25, 0.2
);

INSERT OR IGNORE INTO pricing_rules (
  city, currency, base_fare, per_km, per_min, booking_fee, min_fare, commission_rate
) VALUES (
  'giza', 'EGP', 12, 4.5, 0.5, 3, 25, 0.2
);

INSERT OR IGNORE INTO pricing_rules (
  city, currency, base_fare, per_km, per_min, booking_fee, min_fare, commission_rate
) VALUES (
  'alex', 'EGP', 11, 4.2, 0.45, 3, 22, 0.2
);
