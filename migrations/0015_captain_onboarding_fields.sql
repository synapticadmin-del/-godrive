-- 0015: Captain onboarding profile fields
--
-- The four-step captain onboarding (personal info â†’ driving licence â†’
-- personal documents â†’ vehicle info) collects more than the original schema
-- could hold: the four-part Arabic name, date of birth, national ID number,
-- licence expiry date and vehicle year. All nullable â€” existing captain rows
-- keep working, and the onboarding flow fills them in step by step via
-- POST /captain/profile (partial updates, COALESCE semantics).

ALTER TABLE captains ADD COLUMN first_name TEXT;
ALTER TABLE captains ADD COLUMN father_name TEXT;
ALTER TABLE captains ADD COLUMN grandfather_name TEXT;
ALTER TABLE captains ADD COLUMN family_name TEXT;
ALTER TABLE captains ADD COLUMN birth_date TEXT;
ALTER TABLE captains ADD COLUMN national_id_number TEXT;
ALTER TABLE captains ADD COLUMN license_expiry TEXT;
ALTER TABLE captains ADD COLUMN vehicle_year INTEGER;
