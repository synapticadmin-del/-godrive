-- 0009: Captain working city
-- The offers endpoints (/captain/offers, /captain/nearby-requests) now scope
-- trips to the captain's working city instead of returning every open
-- request nationwide. POST /captain/online and POST /captain/location write
-- this column; it is cleared on going offline so a stale city cannot follow
-- the captain into a later shift in a different city.
--
-- Backfill: existing online captains are assumed to work the default city
-- (all production traffic is Cairo today), so their queues are unchanged
-- the moment the filter ships. Offline rows stay NULL and resolve through
-- DEFAULT_CITY at read time.

ALTER TABLE captains ADD COLUMN city TEXT;

UPDATE captains SET city = 'cairo' WHERE is_online = 1 AND city IS NULL;

CREATE INDEX IF NOT EXISTS idx_captains_city_online ON captains(city, is_online);
