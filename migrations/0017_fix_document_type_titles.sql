-- 0017: Repair mojibake Arabic titles in document_types
--
-- migrations/0014_document_types.sql was committed with a UTF-8 BOM and its
-- Arabic seed values double-encoded (UTF-8 bytes read as cp1252, then re-saved
-- as UTF-8). The result is that every title_ar in document_types reads as
-- 'Ø±Ø®ØµØ© Ø§Ù„Ù‚ÙŠØ§Ø¯Ø©' instead of 'رخصة القيادة'.
--
-- That text is user-facing on both ends: the captain app renders its onboarding
-- upload grid from GET /captain/document-types, and the admin verification page
-- groups pending documents by the same titles. Both have been showing garbage.
--
-- Fixing 0014 in place does not help any environment that already ran it —
-- migrations apply once — so the repair has to be a forward migration. Values
-- are matched by primary key and rewritten unconditionally, which is safe
-- because these eight rows are seed data owned by the migration, not admin
-- input. Rows an admin added later through POST /admin/document-types are
-- untouched.

UPDATE document_types SET title_ar = 'رخصة القيادة',                          updated_at = datetime('now') WHERE id = 'license';
UPDATE document_types SET title_ar = 'البطاقة الشخصية',                       updated_at = datetime('now') WHERE id = 'national_id';
UPDATE document_types SET title_ar = 'صحيفة الحالة الجنائية',                 updated_at = datetime('now') WHERE id = 'criminal_record';
UPDATE document_types SET title_ar = 'الجانب الخلفي لصحيفة الحالة الجنائية',  updated_at = datetime('now') WHERE id = 'criminal_record_back';
UPDATE document_types SET title_ar = 'رخصة السيارة',                          updated_at = datetime('now') WHERE id = 'vehicle_reg';
UPDATE document_types SET title_ar = 'الجانب الخلفي لرخصة السيارة',           updated_at = datetime('now') WHERE id = 'vehicle_reg_back';
UPDATE document_types SET title_ar = 'صورة المركبة',                          updated_at = datetime('now') WHERE id = 'vehicle_photo';
UPDATE document_types SET title_ar = 'صورة شخصية',                            updated_at = datetime('now') WHERE id = 'profile_photo';

-- The English titles in 0014 were ASCII and survived encoding intact, but two
-- were truncated mid-word by the same corruption. Normalise them here so the
-- English column is trustworthy for the future en locale.
UPDATE document_types SET title_en = 'Criminal record (back side)',    updated_at = datetime('now') WHERE id = 'criminal_record_back';
UPDATE document_types SET title_en = 'Vehicle registration (back side)', updated_at = datetime('now') WHERE id = 'vehicle_reg_back';
