-- 0018: Captain search radius
--
-- The radius chips on the captain's "رحلات متاحة" screen were pure widget
-- state: they filtered that one list and nothing else. Dispatch still fanned
-- every open trip in the neighbourhood (9 geohash cells ≈ 7km) out to the
-- captain's inbox and FCM, and GET /captain/offers applied no distance filter
-- at all — so a captain hunting inside 5km still got pushed, badged and
-- notified about trips 7km away that they had explicitly excluded.
--
-- Persisting the radius on the captain row makes it the single source of
-- truth for all three surfaces: the browsable queue, the pushed offers inbox,
-- and the dispatch fanout.
--
-- Backfill: 15 km is the radius the app defaulted to client-side, so every
-- existing captain keeps exactly the reach they had the moment this ships.
-- NULL is still tolerated at read time and resolves to the same default.

ALTER TABLE captains ADD COLUMN search_radius_km REAL;

UPDATE captains SET search_radius_km = 15 WHERE search_radius_km IS NULL;
