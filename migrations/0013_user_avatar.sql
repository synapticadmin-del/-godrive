-- 0013: Profile photo on users
-- The rider app's avatar picker used to offer four hardcoded stock photo URLs
-- and wrote the choice to SharedPreferences only — the server was never told,
-- so the photo lived on one device and vanished on logout or reinstall.
--
-- This column is the real home for it. POST /user/avatar uploads the image to
-- the shared R2 bucket under avatars/<userId>/ and stores the API-relative
-- path to it here (`/user/avatar/<userId>/<file>`), which GET /user/avatar/*
-- serves back. Nothing else writes the column: it is intentionally absent from
-- the PATCH /user/profile schema so a client cannot repoint someone's photo at
-- an arbitrary third-party URL that the captain app would then render.
--
-- Nullable with no backfill — NULL means "no photo", and both apps already
-- fall back to the initial-letter placeholder in that case. Existing rows and
-- every current query keep working unchanged.

ALTER TABLE users ADD COLUMN avatar_url TEXT;
