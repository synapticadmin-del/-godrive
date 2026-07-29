-- 0012: Identity metadata on driver_documents
-- Lets the captain attach the data the admin verifies visually today:
-- the four-part legal name (as printed on the national ID), the national
-- ID number, and each document's expiry date.
--
-- All columns are nullable so existing rows and any document type that does
-- not carry the data (e.g. criminal_record has no expiry in some flows)
-- continue to work unchanged.

ALTER TABLE driver_documents ADD COLUMN holder_full_name TEXT;
ALTER TABLE driver_documents ADD COLUMN national_id_number TEXT;
ALTER TABLE driver_documents ADD COLUMN expires_at TEXT;
