-- 0016: Platform-wide system configuration
--
-- The admin dashboard has shipped a "إعدادات وقواعد المنصة الأساسية" form
-- (SettingsPage, tab 2) since the first release, but the submit handler only
-- ever called setMessage('تم حفظ الإعدادات بنجاح') — it never sent a request.
-- Every value the admin typed (default commission, captain search radius, free
-- cancellation window, cancellation fee, support contacts) was discarded on the
-- next render while the UI reported success. This migration gives that form a
-- real place to live.
--
-- Shape: a narrow key/value table rather than one column per setting. New
-- settings can then be introduced by the code that reads them, without a
-- migration per knob. `value` is stored as TEXT and coerced by the reader; the
-- `type` column tells the API how to coerce and lets the admin UI pick a widget.
--
-- Note on commission: pricing_rules.commission_rate stays the per-city source of
-- truth used by fare math. The value here is only the default applied when a new
-- city is created and no explicit rate is supplied.

CREATE TABLE IF NOT EXISTS system_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  type        TEXT NOT NULL DEFAULT 'string'
                CHECK (type IN ('string', 'number', 'boolean')),
  -- Free-text note surfaced as helper copy in the admin UI.
  description TEXT NOT NULL DEFAULT '',
  updated_by  TEXT REFERENCES users(id),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed with the exact defaults the admin form was displaying, so switching the
-- form from local state to the API is not a behavioural change for the operator.
INSERT OR IGNORE INTO system_config (key, value, type, description) VALUES
  ('default_commission_pct', '20',            'number',  'نسبة عمولة المنصة الافتراضية للمدن الجديدة (%)'),
  ('search_radius_km',       '5',             'number',  'قطر البحث عن الكباتن المتاحين (كم)'),
  ('free_cancel_min',        '3',             'number',  'مهلة الإلغاء المجاني للراكب (دقائق)'),
  ('cancel_fee_egp',         '15',            'number',  'غرامة الإلغاء المتأخر (ج.م)'),
  ('support_phone',          '+201000000000', 'string',  'هاتف مركز دعم العملاء'),
  ('support_whatsapp',       '+201000000000', 'string',  'رقم واتساب المساعدة المباشرة'),
  ('auto_assign',            'true',          'boolean', 'التوزيع التلقائي للرحلات على أقرب كابتن');
