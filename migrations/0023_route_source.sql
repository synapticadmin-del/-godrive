-- 0023: Record which engine priced each trip
--
-- E15 / launch-gate item 11. Number 0023 reserved for E15 in
-- board/exec/MIGRATION-LOCK.md.
--
-- Item 11 is a definition/call-site pair — see WAVE-PLAN §4 and §7. E15 ships
-- this column and the `source` field on getRoute's return; **E09 writes the
-- value at the trip INSERT site in trips.ts**, which E15 does not own. Neither
-- half closes the item alone, and a verifier must not close it on E15's PR.
--
-- Forward-only and additive: one ALTER TABLE ADD COLUMN and one index. No
-- table is rebuilt, no existing row is rewritten, no backfill — this is not a
-- fifth irreversible backfill alongside 0005/0009/0017/0018.
--
-- Rollback (forward repair, per PROTOCOL-EXEC §6):
--   DROP INDEX idx_trips_route_source;
--   UPDATE trips SET route_source = NULL;
-- leaving the column present but unread. Dropping it for real means the table
-- rebuild rehearsed under E18's restore — `trips` carries 20 columns added by
-- ALTER across six migrations and several dependent indexes, so a rebuild here
-- is the single most expensive schema operation in this repository. Adding a
-- nullable column costs nothing and removing it costs that; the asymmetry is
-- why this is nullable rather than NOT NULL DEFAULT.

-- ---------------------------------------------------------------------------
-- Why a column at all
-- ---------------------------------------------------------------------------
-- F-21-02: when OSRM fails, a bare `catch` in lib/routing.ts silently swaps in
-- haversine × 1.35. Because a negotiated fare is never recomputed, that
-- estimate **becomes the settled price**. The plan's wording for item 11 is
-- exact: it is "a permanent mispricing engine with no metric distinguishing the
-- two states". This column is that metric. Without it, the difference between
-- "routed" and "guessed" is unobservable after the fact, and every reconciliation
-- of a disputed fare is guesswork.
--
-- NULL is meaningful and is the reason this is not NOT NULL DEFAULT 'unknown':
-- every row written before this deploy genuinely has no recorded source, and a
-- default would paint that unknown state with the same brush as a row E09 failed
-- to populate. Those are different faults and the metric must not merge them.
--
-- Vocabulary is CHECK-constrained because this is the column an alert threshold
-- will be built on, and a typo'd 'osrm ' that silently never matches is exactly
-- the R3 shape — a value defined and nothing ever reading it.
ALTER TABLE trips ADD COLUMN route_source TEXT
  CHECK (route_source IS NULL OR route_source IN (
    'osrm',       -- a real route from the contracted engine
    'haversine',  -- the × 1.35 straight-line fallback: this trip was NOT routed
    'cached'      -- served from a previously routed identical leg
  ));

-- The alert query is "how many trips in the last hour were priced off a straight
-- line", and the reconciliation query is "show me the haversine trips in this
-- window". Both are (route_source, created_at); leading with the discriminator
-- keeps the fallback rows — which should be the rare ones — contiguous.
CREATE INDEX IF NOT EXISTS idx_trips_route_source
  ON trips(route_source, created_at);
