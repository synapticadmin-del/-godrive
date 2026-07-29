-- 0013: Dynamic captain document types
--
-- Previously the set of required documents lived only in client code: the
-- captain app's upload screen and the admin verification page each hard-coded
-- the same four types (license, national_id, vehicle_reg, criminal_record).
-- Adding a new document meant shipping new builds of every app.
--
-- This migration makes document types data-driven. The captain app renders its
-- onboarding upload grid from GET /captain/document-types, and the admin
-- dashboard manages the catalog (add / edit / deactivate) without a deploy.
-- driver_documents.type rows written before this migration keep working: the
-- catalog is seeded with the original four types using the same ids.

CREATE TABLE IF NOT EXISTS document_types (
  id TEXT PRIMARY KEY,                -- stable machine id, e.g. 'license'
  title_ar TEXT NOT NULL,             -- label shown in Arabic UIs
  title_en TEXT NOT NULL DEFAULT '',  -- label shown in English UIs
  icon TEXT NOT NULL DEFAULT 'description', -- material icon name hint for clients
  required INTEGER NOT NULL DEFAULT 1,-- 0 = optional (اختياري badge in the app)
  sort_order INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,  -- 0 = hidden from captains, kept for history
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed: the four types that were hard-coded in the clients, plus the extra
-- documents from the new onboarding design (personal documents back side,
-- vehicle photo, vehicle licence back side, personal photo).
INSERT OR IGNORE INTO document_types (id, title_ar, title_en, icon, required, sort_order, active) VALUES
  ('license',             'رخصة القيادة',                        'Driving licence',            'card_membership', 1, 10, 1),
  ('national_id',         'البطاقة الشخصية',                     'National ID',                 'badge',           1, 20, 1),
  ('criminal_record',     'صحيفة الحالة الجنائية',               'Criminal record',            'fact_check',      1, 30, 1),
  ('criminal_record_back','الجانب الخلفي لصحيفة الحالة الجنائية', 'Criminal record (back side)','fact_check',      0, 40, 1),
  ('vehicle_reg',         'رخصة السيارة',                        'Vehicle registration',        'directions_car',  1, 50, 1),
  ('vehicle_reg_back',    'الجانب الخلفي للشهادة',               'Vehicle certificate (back)',  'directions_car',  0, 60, 1),
  ('vehicle_photo',       'صورة المركبة',                        'Vehicle photo',               'directions_car',  0, 70, 1),
  ('profile_photo',       'صورة شخصية',                          'Personal photo',              'account_circle',  1, 5,  1);
