-- =====================================================================
-- Synaptic Go migration 0003 — Comprehensive transport platform for Egypt
-- Adds: device tokens, FCM, internal wallet, scheduled trips, multi-point,
--      surge, intercity, B2B companies, safety (SOS/share/in-call chat),
--      turnstile records, notification queue log.
-- Compatible with D1 (SQLite). Runs after 0001_init.sql and 0002_enhancements.sql.
-- =====================================================================

-- ----------------------------------------------------------------------
-- 1) Device tokens (FCM push)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android' CHECK (platform IN ('android','ios','web')),
  app_role TEXT,                       -- 'rider' | 'captain'
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_dev_user ON device_tokens(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_dev_token ON device_tokens(token);

-- ----------------------------------------------------------------------
-- 2) Internal wallet + transactions (ledger; balance = SUM credits-debits)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('topup','trip_payment','refund','commission','payout','adjustment','promo_credit')),
  direction TEXT NOT NULL CHECK (direction IN ('credit','debit')),
  amount REAL NOT NULL,                -- positive amount in EGP
  currency TEXT NOT NULL DEFAULT 'EGP',
  trip_id TEXT REFERENCES trips(id) ON DELETE SET NULL,
  payment_ref TEXT,                    -- paymob order id / external ref
  note TEXT,
  status TEXT NOT NULL DEFAULT 'settled' CHECK (status IN ('pending','settled','failed','reversed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_wt_user ON wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wt_trip ON wallet_transactions(trip_id);
CREATE INDEX IF NOT EXISTS idx_wt_created ON wallet_transactions(created_at);

-- Hold the "available" balance snapshot for fast reads (kept consistent via API).
ALTER TABLE users ADD COLUMN wallet_balance REAL NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN wallet_updated_at TEXT;

-- ----------------------------------------------------------------------
-- 3) Scheduled trips (deferred rides) + surge + waypoints
-- ----------------------------------------------------------------------
ALTER TABLE trips ADD COLUMN scheduled_for TEXT;        -- ISO timestamp
ALTER TABLE trips ADD COLUMN schedule_status TEXT;       -- pending/dispatched/expired
ALTER TABLE trips ADD COLUMN waypoints TEXT;            -- JSON array of {lat,lng,address}
ALTER TABLE trips ADD COLUMN surge_multiplier REAL NOT NULL DEFAULT 1.0;

CREATE TABLE IF NOT EXISTS scheduled_trip_dispatch (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  scheduled_for TEXT NOT NULL,
  dispatched_at TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','dispatched','failed'))
);
CREATE INDEX IF NOT EXISTS idx_sched_time ON scheduled_trip_dispatch(scheduled_for);
CREATE INDEX IF NOT EXISTS idx_sched_status ON scheduled_trip_dispatch(status);

-- ----------------------------------------------------------------------
-- 4) Intercity (between governorates) — scheduled fixed-price routes
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intercity_routes (
  id TEXT PRIMARY KEY,
  origin_city TEXT NOT NULL,
  destination_city TEXT NOT NULL,
  distance_km REAL,
  base_price REAL NOT NULL,           -- EGP per seat
  vehicle_type_id TEXT REFERENCES vehicle_types(id),
  duration_minutes INTEGER,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS intercity_schedules (
  id TEXT PRIMARY KEY,
  route_id TEXT NOT NULL REFERENCES intercity_routes(id) ON DELETE CASCADE,
  depart_at TEXT NOT NULL,            -- ISO datetime
  seats_total INTEGER NOT NULL DEFAULT 4,
  seats_booked INTEGER NOT NULL DEFAULT 0,
  captain_id TEXT REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','boarding','departed','cancelled','completed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_int_sched_route ON intercity_schedules(route_id);
CREATE INDEX IF NOT EXISTS idx_int_sched_depart ON intercity_schedules(depart_at);

CREATE TABLE IF NOT EXISTS intercity_bookings (
  id TEXT PRIMARY KEY,
  schedule_id TEXT NOT NULL REFERENCES intercity_schedules(id) ON DELETE CASCADE,
  rider_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seats INTEGER NOT NULL DEFAULT 1,
  pickup_station TEXT,
  dropoff_station TEXT,
  fare REAL NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'cash',
  status TEXT NOT NULL DEFAULT 'booked' CHECK (status IN ('booked','boarded','cancelled','no_show')),
  qr_token TEXT UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_int_book_sched ON intercity_bookings(schedule_id);
CREATE INDEX IF NOT EXISTS idx_int_book_rider ON intercity_bookings(rider_id);

-- ----------------------------------------------------------------------
-- 5) B2B companies + employees + cost centers + monthly billing
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS companies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  legal_name TEXT,
  tax_id TEXT,                        -- Egyptian commercial registry number
  contact_email TEXT,
  contact_phone TEXT,
  credit_limit REAL NOT NULL DEFAULT 0,
  monthly_invoice_day INTEGER NOT NULL DEFAULT 1 CHECK (monthly_invoice_day BETWEEN 1 AND 28),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','closed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS company_employees (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cost_center TEXT,
  spend_limit_month REAL NOT NULL DEFAULT 0,   -- 0 = unlimited within company limit
  allowed_vehicle_types TEXT,                   -- JSON array of vehicle_type_id; NULL = all
  allowed_hours TEXT,                           -- JSON range {from, to}; NULL = all hours
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_emp_company ON company_employees(company_id);
CREATE INDEX IF NOT EXISTS idx_emp_user ON company_employees(user_id);

ALTER TABLE trips ADD COLUMN company_id TEXT REFERENCES companies(id) ON DELETE SET NULL;
ALTER TABLE trips ADD COLUMN cost_center TEXT;
ALTER TABLE trips ADD COLUMN billed_to_company INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS company_invoices (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  total_trips INTEGER NOT NULL DEFAULT 0,
  total_amount REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','issued','paid','overdue')),
  paymob_order_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_invoice_company ON company_invoices(company_id);
CREATE INDEX IF NOT EXISTS idx_invoice_period ON company_invoices(period_start, period_end);

-- ----------------------------------------------------------------------
-- 6) Safety: SOS alerts, trip sharing, in-call anonymous chat
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sos_alerts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trip_id TEXT REFERENCES trips(id) ON DELETE SET NULL,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','false_alarm')),
  shared_with TEXT,                   -- JSON array of contact refs / authorities
  resolved_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sos_user ON sos_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_status ON sos_alerts(status);
CREATE INDEX IF NOT EXISTS idx_sos_created ON sos_alerts(created_at);

CREATE TABLE IF NOT EXISTS trip_share_tokens (
  token TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  created_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_share_trip ON trip_share_tokens(trip_id);

CREATE TABLE IF NOT EXISTS trip_chat_messages (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('rider','captain','support')),
  body TEXT NOT NULL,
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_trip ON trip_chat_messages(trip_id, created_at);

-- ----------------------------------------------------------------------
-- 7) Turnstile token records (anti-abuse on public auth)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS turnstile_verifications (
  id TEXT PRIMARY KEY,
  token TEXT NOT NULL,
  ip TEXT,
  verified INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_turnstile_created ON turnstile_verifications(created_at);

-- ----------------------------------------------------------------------
-- 8) Notification queue log (consumed via Cloudflare Queues)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification_log (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('fcm','whatsapp','sms','email','in_app')),
  topic TEXT NOT NULL,                -- 'trip.offer', 'trip.accepted', ...
  payload TEXT,                       -- JSON
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','failed','dropped')),
  provider_ref TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  sent_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notification_log(user_id);
CREATE INDEX IF NOT EXISTS idx_notif_status ON notification_log(status);
CREATE INDEX IF NOT EXISTS idx_notif_created ON notification_log(created_at);