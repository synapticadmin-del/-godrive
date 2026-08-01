# 21 — Maps, Routing & Geospatial Accuracy

> Track: D — Engineering excellence & production readiness · Reviewer: `chat-20260801-1405-aac2` · Date: 2026-08-01
> Base commit reviewed: `7f9e5d6b5615177bf1e19e7b4db4287d9f229593`

Everything a rider believes about time, distance and price in this product is
produced by three third-party services that Synaptic Go does not own, does not
pay for, and is not licensed to use. All three are pointed at their public
free-tier endpoints in the production Worker config. That is the headline, and
the rest of this document is the arithmetic behind it.

---

## 1. Scope

**Covered.** The geo dependency chain end to end: driving routes and ETAs
(OSRM), forward/reverse geocoding and place search (Nominatim), map tiles
(CARTO), the geohash cell layer used for proximity, route geometry and path
point persistence, pickup precision, client-side location acquisition on both
Flutter apps, and city/geofence handling.

**Not covered — owned elsewhere.** The dispatch and matching algorithm itself
(**T06**); pricing rules, surge and bidding economics (**T05**); the wallet and
commission ledger (**T03**); WebSocket transport and Durable Object lifecycle
(**T07**); D1 schema design and storage growth (**T08**); the rider and captain
journeys as product surfaces (**T09**, **T10**); Arabic copy and RTL layout
(**T14**); accessibility (**T15**); and the systematic rider↔captain drift
(**T27**). Where my evidence touches those axes I record it in §9 rather than
planning it here.

One boundary is worth stating plainly because it decides how severe several
findings are. Distance and duration are inputs to price, and **T05** owns the
pricing formula — but this document owns the *numbers fed into it*. A wrong
`perKm` rate is T05's problem. A wrong `distanceKm` is mine.

---

## 2. What I actually read

Every file below was downloaded at commit `7f9e5d6b56` and read from disk; line
numbers in this document are real line numbers in those files. Files marked
*skimmed* were read for a specific question rather than end to end.

### API — routing and geo core

| File | Note |
|---|---|
| `apps/api/src/lib/routing.ts` | 173 lines. `getRoute`, `getDurationsToPoint`, the haversine fallbacks, `fareFromRoute`. The centre of this review. |
| `apps/api/src/lib/geocode.ts` | 130 lines. Nominatim reverse + search, KV caching, cache key construction. |
| `apps/api/src/lib/nearby.ts` | 105 lines. Geohash neighbourhood fan-out for captain proximity. |
| `apps/api/src/lib/pricing.ts` | 38 lines. `estimateTripFare` (a second, unrouted distance path) and `cellKey`. |
| `apps/api/src/lib/schemas.ts` | Zod input contracts — coordinate and `city` validation. |
| `apps/api/src/lib/types.ts` | `DbTrip` shape incl. `route_geometry`. Skimmed. |
| `apps/api/src/lib/utils.ts` | `resolveSearchRadiusKm`, id helpers. Skimmed. |
| `apps/api/src/routes/geocode.ts` | 37 lines. The two public geo endpoints and their rate limits. |
| `apps/api/src/routes/trips.ts` | 1371 lines. `/estimate`, trip creation, `attachCaptainEtas`, geometry read, `/path`, completion. |
| `apps/api/src/routes/captain.ts` | 700 lines. `POST /location`, path-point sampling, city-scoped offer queries. |
| `apps/api/src/routes/intercity.ts` | 463 lines. Fixed-route intercity model. Skimmed for geo handling. |
| `apps/api/src/routes/search.ts` | 48 lines. Admin text search — no geo component, confirmed not in scope. |
| `apps/api/src/index.ts` | Route mounting and auth ordering. |
| `apps/api/src/middleware/rateLimit.ts` | Rate-limit key derivation. |
| `apps/api/src/durable-objects/GeoCell.ts` | 82 lines. Presence storage, haversine ranking, 3-minute expiry alarm. |
| `apps/api/src/durable-objects/TripRoom.ts` | Location broadcast path. Skimmed. |
| `apps/api/wrangler.toml` | 180 lines. `OSRM_URL` and `DEFAULT_CITY` across all three environments. |
| `packages/shared/src/index.ts` | `haversineKm`, `estimateDurationMin`, `calculateFare`, `encodeGeohash`, `geohashCellSpan`. |

### Migrations

| File | Note |
|---|---|
| `migrations/0002_enhancements.sql` | `trip_path_points` DDL and its indexes. |
| `migrations/0001_init.sql` | `trips` geo columns. Skimmed. |
| `migrations/0009_captain_city.sql` | The `captains.city` column and its backfill rationale. |
| `migrations/0018_captain_search_radius.sql` | `search_radius_km` persistence. |
| `migrations/0003_global_transport.sql`, `0010`, `0019` | Skimmed for geo columns. |

### Flutter — rider, captain, shared

| File | Note |
|---|---|
| `apps/rider/lib/services/location_service.dart` | 303 lines. Geometry parsing, `RoutePreview`, search, debouncing. |
| `apps/rider/lib/screens/home/home_screen.dart` | 1509 lines. Map construction, tile layer, pin picking, nearby polling. |
| `apps/rider/lib/screens/home/location_search_sheet.dart` | 623 lines. Search UX, hardcoded quick spots. |
| `apps/rider/lib/screens/home/fare_estimate_sheet.dart` | 831 lines. Skimmed for distance/ETA display. |
| `apps/rider/lib/screens/trip/trip_screen.dart` | 835 lines. Live trip map and route polyline. |
| `apps/rider/lib/services/app_state.dart` | 696 lines. Skimmed for estimate/trip calls. |
| `apps/captain/lib/services/captain_state.dart` | 1189 lines. GPS stream, accuracy profiles, lifecycle handling, push cadence. |
| `apps/captain/lib/screens/home/home_tab.dart` | 394 lines. Skimmed. |
| `apps/captain/lib/screens/home/active_trip_panel.dart` | 708 lines. Skimmed for navigation hand-off. |
| `apps/captain/lib/screens/home/nearby_requests_screen.dart` | 366 lines. Skimmed for radius UI. |
| `packages/flutter_shared/lib/theme/app_theme.dart` | Contains `MapTiles` — the tile URLs and the unused attribution constant. |
| `packages/flutter_shared/lib/widgets/map_controls.dart` | 232 lines. |
| `packages/flutter_shared/lib/widgets/vehicle_map_marker.dart` | 194 lines. |
| `packages/flutter_shared/lib/widgets/navigation_button.dart` | 64 lines. External navigation hand-off. |
| `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml`, `packages/flutter_shared/pubspec.yaml` | Map/location package versions. |

### Admin

| File | Note |
|---|---|
| `apps/admin/src/pages/LiveMapPage.tsx` | 265 lines. Leaflet + CARTO tiles, straight-line trip polylines. |

### External evidence gathered first-hand

- **14 live queries against `nominatim.openstreetmap.org`** with Egyptian
  Arabic strings a real rider would type, run on 2026-08-01 with a descriptive
  User-Agent at ~1 req/s. Raw results are quoted in §4 (F-21-06) — this is
  measured, not inferred, and it is the strongest evidence in the document.
- OSRM API usage policy, OSMF Nominatim policy, OSMF tile policy, Geofabrik
  extract sizes, and 2025–2026 list pricing for Google/Mapbox/MapTiler/Stadia.
  Cited inline in §5 and §6.

---

## 3. How it works today

### 3.1 The three external dependencies

| Concern | Service | Configured at | Auth | Paid |
|---|---|---|---|---|
| Driving route + duration | OSRM `router.project-osrm.org` | `wrangler.toml:88`, **`:148` (prod)**, `:176` (staging); default `routing.ts:15` | none | no |
| Geocode + place search | Nominatim `nominatim.openstreetmap.org` | `geocode.ts:39`, `geocode.ts:100` (hardcoded) | none | no |
| Map tiles | CARTO `cartodb-basemaps-{s}.global.ssl.fastly.net` | `app_theme.dart:488,490` (mobile); `LiveMapPage.tsx:71-72` (admin) | none | no |

Only OSRM is overridable — via the `OSRM_URL` var, read at `trips.ts:176-178`.
The Nominatim host is a string literal inside `geocode.ts` with no env
indirection, so switching geocoding provider is a code change, not a config
change. Both apps identify themselves as
`SynapticGo/0.2 (ride-hailing; contact=admin@synapticstudio.tech)`
(`geocode.ts:48`, `geocode.ts:108`) — a real, attributable identity attached to
every policy-violating request.

### 3.2 Fare estimate → booking → trip

1. Rider app calls **`POST /trips/estimate`** (`trips.ts:315`). Note this route
   is registered *before* `tripRoutes.use("*", authMiddleware)` at
   `trips.ts:346`, so it is **unauthenticated**, rate-limited only by IP at
   30 requests / 60 s (`trips.ts:317`, key derived at `rateLimit.ts:20`).
2. It runs `getRoute()` and `findNearbyCaptains()` in parallel
   (`trips.ts:330-339`). `getRoute` issues one OSRM `/route/v1/driving` request
   with `overview=full&geometries=geojson` and an 8 s abort
   (`routing.ts:27-37`).
3. On success it returns real road distance, real free-flow duration, and a
   full polyline, converting OSRM's `[lng,lat]` to `[lat,lng]`
   (`routing.ts:54-60`). **On any failure — HTTP error, timeout, `code != "Ok"`,
   or a thrown parse error — the `catch` at `routing.ts:61-63` silently returns
   `haversineFallback()`**: straight-line distance × 1.35, duration at a flat
   22 km/h, and a two-point geometry that is literally the pickup and the
   dropoff (`routing.ts:66-82`).
4. `fareFromRoute` (`routing.ts:164`) feeds whichever distance survived into
   `calculateFare` (`packages/shared/src/index.ts:83`).
5. **`POST /trips`** (`trips.ts:348`) repeats the whole thing — a *second*
   independent `getRoute` call at `trips.ts:382` — then persists
   `distance_km`, `duration_min`, `estimated_fare` and the polyline as JSON in
   `route_geometry` (`trips.ts:446-472`).

The response carries `source: "osrm" | "haversine"` (`routing.ts:60`,
`routing.ts:80`) and the rider app does read it — `RoutePreview` sets
`isApproximate` when it sees `haversine` (`location_service.dart:98`). What it
does with that flag is covered in F-21-02.

### 3.3 Why the estimate is final

`POST /trips/:id/complete` computes:

```ts
const finalFare = trip.accepted_price ?? trip.final_fare ?? trip.estimated_fare ?? 0;
```
— `trips.ts:969`

There is no recomputation from the distance actually driven. This is correct
for an inDrive-style negotiated-price product: rider and captain agree a price
up front and that is the price. The consequence for this review is severe and
non-obvious — **there is no meter to correct a bad estimate.** A distance error
at estimate time is not a display bug that self-heals when the trip ends; it is
the final settled amount, and it is wrong in the ledger forever.

### 3.4 Captain arrival ETA

`attachCaptainEtas` (`trips.ts:241`) fills `eta_min` on each bid using OSRM's
`/table` service in a single fan-in request (`routing.ts:107-153`) with a
tighter 3.5 s timeout, degrading **per origin** rather than per call
(`routing.ts:143-149`). Results cache in KV for 60 s keyed `eta:<tripId>:<captainId>`
(`trips.ts:268`, `trips.ts:305-309`), and stale fixes older than 10 minutes are
dropped rather than routed (`trips.ts:190`, `trips.ts:266`).

This is the best-engineered geo code in the repository. The reasoning in its
docblock (`trips.ts:217-239`) — why the cache key is the pair and not the
rounded position, why the fallback is cached under its own marker — is correct
and worth preserving through any provider migration.

### 3.5 Proximity: geohash cells

Captain presence lives in one `GeoCell` Durable Object per geohash-5 cell,
keyed `<city>:<geohash>` (`pricing.ts:36-38`). `POST /captain/location`
(`captain.ts:190`) writes the D1 row and heartbeats the cell
(`captain.ts:211-221`). Lookup fans out to the 9-cell neighbourhood by stepping
one full cell span in each direction (`nearby.ts:40-53`), queries all cells in
parallel, and merges by `userId` keeping the closest reading
(`nearby.ts:71-104`). Ranking inside a cell is haversine (`GeoCell.ts:57`).
Presence expires at 120 s for reads (`GeoCell.ts:49`) and is deleted by alarm at
180 s (`GeoCell.ts:73`).

Note the unit mismatch this creates: `findNearbyCaptains` returns
**straight-line** `distanceKm` (`GeoCell.ts:57`), while the bid ETA is
**routed** minutes. Two different notions of "how far away is this captain"
coexist, and only one of them knows the Nile exists.

### 3.6 Path points

While a trip is `assigned`/`arrived`/`in_progress`, each captain location POST
updates `trips.captain_lat/lng` and appends to `trip_path_points` — but only if
30 s have elapsed since the last point (`captain.ts:237-252`). The table
(`migrations/0002_enhancements.sql:14-24`) carries `lat`, `lng`, `heading`,
`speed`, `recorded_at`. **`speed` is never written** — the INSERT at
`captain.ts:247-251` binds only `heading`. No snap-to-road is applied at write
or read; `GET /trips/:id/path` (`trips.ts:682`) returns raw fixes.

### 3.7 Caching — the complete inventory

| Cache | Key | TTL | Where |
|---|---|---|---|
| Reverse geocode | `geo:<lat4dp>,<lng4dp>` | 30 days | `geocode.ts:19-21`, `:82` |
| Place search | `geosearch:<lowercased raw query>` | 7 days | `geocode.ts:94`, `:128` |
| Captain arrival ETA | `eta:<tripId>:<captainId>` | 60 s | `trips.ts:268`, `:305-309` |

**That is the entire list. There is no route cache.** `getRoute` has no KV read
or write on any path — verified by grepping every `SESSIONS.get`/`SESSIONS.put`
in the API. Every fare estimate and every booking is an uncached OSRM round
trip, and the rider app re-polls `/trips/estimate` every 45 s while the home
screen is open (`home_screen.dart:197-205`) purely to refresh the nearby-car
markers.

### 3.8 Geofencing

There is none in the geometric sense. `city` is a **free-text string** the
client supplies (`schemas.ts:45`, `schemas.ts:58`, `schemas.ts:186`), falling
back to `DEFAULT_CITY` = `"cairo"` (`trips.ts:322`, `trips.ts:378`,
`captain.ts:203`). It is never validated against the coordinates. Coordinates
themselves are validated only to global range — `z.number().min(-90).max(90)`
(`schemas.ts:41-44`) — so nothing rejects a trip from Paris to London.

That string then does real work: it selects the pricing row
(`getPricing(DB, city)`, `trips.ts:323`), it namespaces the geohash cell
(`pricing.ts:37`), and it filters the captain's offer queue by exact equality —
`WHERE t.status IN ('searching','offered') AND t.city = ?` (`captain.ts:378`).

Intercity is a separate world: `intercity_routes` rows carry `origin_city` /
`destination_city` text, a `base_price` and a `duration_minutes`
(`intercity.ts:46-49`). No routing, no geometry, no coordinates.
---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-21-01 | **S1** | Production routing points at the OSRM public demo server, whose policy forbids exactly this use and permits withdrawal without notice | `apps/api/wrangler.toml:148` (prod), `:88`, `:176`; default `apps/api/src/lib/routing.ts:15` | Every fare estimate depends on a free server with no SLA that may block the app at any moment | confirmed |
| F-21-02 | **S1** | When OSRM fails, the silent haversine×1.35 fallback becomes the **settled price**, because a negotiated fare is never recomputed after the trip | `routing.ts:61-63`, `routing.ts:71`, `trips.ts:969` | Permanent mispricing on every fallback trip; captain underpaid or rider overcharged, with no correction path | confirmed |
| F-21-03 | **S1** | Public Nominatim is used for end-user place search — a use the OSMF policy names as forbidden, and ride-hailing is called out as required to self-host | `geocode.ts:86-129`, `routes/geocode.ts:26-36`, UA at `geocode.ts:108` | Search breaks for all users when the app's User-Agent is blocked; the UA identifies the company | confirmed |
| F-21-04 | **S1** | No route cache exists at all, and the endpoint that calls OSRM is unauthenticated and IP-keyed | `trips.ts:315` vs `trips.ts:346`; `index.ts:112`; `rateLimit.ts:20`; no `SESSIONS` use in `routing.ts` | Third-party quota is spent on uncached and unauthenticated traffic; trivially abusable into a ban | confirmed |
| F-21-05 | **S2** | Tile attribution is defined, documented as legally required, and never rendered in either Flutter app | `app_theme.dart:495` (defined); zero usages in `apps/rider`, `apps/captain` | Breach of CARTO and ODbL attribution terms on the two surfaces users actually see | confirmed |
| F-21-06 | **S2** | Nominatim returns **zero results** for the landmark-relative phrasing Egyptians actually use | Measured, 2026-08-01 (§4 F-21-06 table); code path `geocode.ts:99-102` | The primary way riders describe destinations returns an empty list | confirmed |
| F-21-07 | **S2** | Search sends no `viewbox`/`bounded` bias, so top hits land in the wrong governorate — up to ~700 km away | `geocode.ts:99-102` (only `countrycodes=eg`) | Riders offered destinations in Red Sea or Qalyubia for Cairo queries | confirmed |
| F-21-08 | **S2** | No traffic model anywhere: OSRM default profile is free-flow, the fallback is a flat 22 km/h constant | `routing.ts:72`, `routing.ts:161`, `packages/shared/src/index.ts:72` | ETAs roughly half of reality in Cairo peak; drives cancellations and captain distrust | confirmed |
| F-21-09 | **S2** | `city` is unvalidated client-supplied free text that selects the pricing row and filters dispatch | `schemas.ts:45,58,186`; `trips.ts:322-323`, `captain.ts:378` | Client can select another city's tariff; no check that coordinates are in the claimed city, or in Egypt | confirmed |
| F-21-10 | **S2** | Captain GPS push cadence during a trip can exceed the server's own rate limit by ~2× | `captain_state.dart:623-626` (10 m filter, no time floor) vs `captain.ts:192-197` (30/60 s) | Location updates dropped mid-trip, exactly when the rider is watching the car | confirmed |
| F-21-11 | **S2** | No background location: GPS and pushes stop when the captain's screen sleeps | `captain_state.dart:1082-1089` | Captain's marker freezes on the rider's map for most of a real trip | confirmed |
| F-21-12 | **S2** | Route geometry is fetched once at trip load and never refreshed | `trip_screen.dart:46-54` | Displayed route diverges from the driven route after any detour; useless for live reassurance | confirmed |
| F-21-13 | **S2** | The 2-point fallback geometry renders as a normal polyline — a straight line across the Nile — flagged only by a small "تقريبي" label | `home_screen.dart:586-607`, `location_service.dart:49` (`hasRealGeometry` never checked), label `home_screen.dart:1297-1304` | Riders shown a physically impossible route with no meaningful warning | confirmed |
| F-21-14 | S3 | Path points sampled at 30 s with no snap-to-road, and the `speed` column is never written | `captain.ts:237-252`; `migrations/0002_enhancements.sql:20` | ~250 m gaps at road speed; insufficient to settle a "you took the long way" dispute | confirmed |
| F-21-15 | S3 | Search cache key is the raw lowercased query, with no Arabic normalisation | `geocode.ts:94` | Arabic morphology and diacritics fragment the key space; low hit rate against a 1 req/s budget | confirmed |
| F-21-16 | S3 | Booking performs a second, independent `getRoute` rather than reusing the estimate | `trips.ts:330-339` then `trips.ts:382-386` | Doubles OSRM load per trip; the booked route can silently differ from the quoted one | confirmed |
| F-21-17 | S3 | No curated pickup zones for airports, malls or stadiums | Absence across `home_screen.dart`, `location_search_sheet.dart` | GPS-unreliable venues produce unreachable pickup pins | confirmed |
| F-21-18 | S3 | No tile caching; `NetworkTileProvider` only, and no offline handling | `home_screen.dart:571` | Map goes blank in tunnels and dead zones with no fallback or banner | confirmed |
| F-21-19 | S3 | Result lists are shown unfiltered and undeduplicated | Measured (duplicate Maadi metro rows) | Near-identical entries and far-away namesakes shown side by side | confirmed |
| F-21-20 | S3 | `estimateTripFare` is a second, permanently unrouted fare path — dead today, a trap tomorrow | `pricing.ts:23-34`; no call sites in `apps/api/src` | If ever wired up it produces haversine×1.35 fares with no OSRM attempt at all | confirmed |
| F-21-21 | S4 | Cairo centre `30.0444, 31.2357` hardcoded in at least four places with no shared constant | `home_screen.dart:556`, `trip_screen.dart:240-243`, `location_search_sheet.dart:52`, `LiveMapPage.tsx:68` | Multi-city expansion requires hunting literals | confirmed |
| F-21-22 | S4 | Admin loads Leaflet from `unpkg.com` with no Subresource Integrity | `LiveMapPage.tsx:60-61` | CDN compromise executes in an authenticated admin session | confirmed |

---

### F-21-01 — Production routes through a demo server that forbids this

`apps/api/wrangler.toml:148`, inside `[env.prod.vars]`:

```toml
OSRM_URL = "https://router.project-osrm.org"
```

The same value appears in the default block (`:88`) and staging (`:176`), and
is hardcoded twice more as a fallback default (`routing.ts:15`,
`trips.ts:177`). There is no environment in which this product routes against
infrastructure it controls.

The OSRM project's API usage policy is unambiguous. It permits demo-server
queries subject to rules including *"Excessive use is not allowed. If your
requests are impacting the service stability, we will block you"*, and under
commercial use: *"Access to the Demo Server shall be withdrawn at any time and
without giving a reason"* and *"We don't give any quality guarantees. The Demo
Server is supplied on best effort basis."* The policy closes by warning that
*"Commercial services … should be especially aware that access may be withdrawn
at any point: you may no longer be able to serve your paying customers if access
is withdrawn."*

The failure mode is not a clean outage. Because `getRoute` catches everything
(`routing.ts:61`), a block or a throttle does not surface as an incident — it
surfaces as F-21-02: the platform quietly starts pricing every trip off a
straight line. There is no metric, no log, and no alert distinguishing the two
states. `source` is returned to the client but never recorded server-side; the
`trips` table has no column for it, so after the fact nobody can tell which
trips were priced by a router and which by a ruler.

**One line makes this observable before it makes it correct**: persist
`route_source` on the trip row. Even without changing provider, that turns an
invisible degradation into a number someone can watch.

### F-21-02 — The fallback is not an estimate, it is the price

```ts
} catch {
  return haversineFallback(pickup, dropoff);
}
```
— `routing.ts:61-63`

```ts
const distanceKm = Math.round(straight * 1.35 * 100) / 100;
```
— `routing.ts:71`

In most ride-hailing systems a bad pre-trip estimate is embarrassing but
self-correcting: the meter runs on the real trip and the final fare reflects
reality. **This product has no meter.** `trips.ts:969` settles on
`accepted_price ?? final_fare ?? estimated_fare`, all of which trace back to the
estimate. A wrong distance at quote time is the amount that lands in the
ledger.

So the accuracy of the constant `1.35` is a money question. Cairo's road network
makes it a bad constant, principally because the Nile is crossed at a limited
number of bridges and a straight line ignores every one of them.

Worked examples. Straight-line distance is computed with the same haversine the
code uses; road distance is an informed estimate from Cairo's network geometry
and is labelled as such.

| Route | Straight km | Road km *(est.)* | True ratio | Code km (×1.35) | Error |
|---|---|---|---|---|---|
| Tahrir → Zamalek (Qasr El Nil) | 2.60 | 4.10 | 1.58 | 3.51 | −14% |
| Maadi Corniche → Mohandessin (Abbas Br.) | 11.03 | 16.80 | 1.52 | 14.89 | −11% |
| Maadi Metro → Maadi Road 9 (intra-district) | 0.67 | 1.80 | 2.68 | 0.91 | **−49%** |
| Garden City → Talaat Harb (one-way grid) | 1.43 | 2.50 | 1.75 | 1.93 | −23% |
| Nasr City → 6th October (Ring Road) | 40.57 | 60.00 | 1.48 | 54.77 | −9% |
| Dokki → Cairo Int'l Airport | 20.27 | 28.50 | 1.41 | 27.37 | −4% |
| Nasr City intra (City Stars → Zahraa) | 1.56 | 2.20 | 1.41 | 2.11 | −5% |
| 6th October City → Tahrir | 30.30 | 40.00 | 1.32 | 40.90 | +2% |
| New Cairo → Agouza | 26.60 | 32.50 | 1.22 | 35.91 | +10% |
| Heliopolis (Roxy) → Airport | 7.63 | 8.20 | 1.07 | 10.30 | **+26%** |

Mean true detour ratio **1.54**, median **1.45**, against a coded **1.35**. The
constant is not merely imprecise, it is **biased low**: it under-states road
distance on 7 of these 10 routes. And the spread matters more than the mean —
the true ratio ranges from 1.07 to 2.68, so no single constant can serve both a
700 m trip through a one-way grid and a 40 km Ring Road run.

Two structural points fall out of the table:

- **Short trips are the worst case, and short trips are the common case.** The
  ratio explodes below ~2 km because a straight line ignores the block
  structure entirely. The `minFare` floor absorbs part of the fare error, which
  is precisely why this stays invisible — the *fare* looks plausible while the
  *distance shown to the captain* is half of what they will drive.
- **The error changes sign.** Nile crossings and dense grids under-state (the
  captain absorbs it); unusually direct corridors like Heliopolis→Airport
  over-state (the rider absorbs it). A platform cannot even describe this as a
  consistent discount or a consistent markup — it is noise applied to money.

Fare impact, using an illustrative 2026 Cairo tariff (base 18 EGP, 5.50 EGP/km,
0.80 EGP/min, booking fee 5 EGP, min fare 30 EGP — *assumed, needs-check against
the live `pricing_rules` row*): per-trip deltas run from **−16.8 EGP**
(Nasr City → 6th October, captain underpaid) to **+38.8 EGP** (New Cairo →
Agouza, rider overcharged). At 10,000 trips/day with a 5% fallback rate, that is
on the order of **15,000 mispriced trips per month**. The aggregate EGP figure
depends entirely on trip-mix and is not worth a false-precision total; the count
is the number that matters, because each one is a potential dispute with no
underlying data to resolve it (see F-21-14).

**The fallback should not be silent, and arguably should not exist for
booking.** Estimating is a reasonable degradation for the map preview; *pricing
a contract* off a straight line is not. Options are costed in §6 (P0.2).

### F-21-03 — Public Nominatim for autocomplete is explicitly forbidden

`geocode.ts:86-129` implements place search against
`https://nominatim.openstreetmap.org/search`, exposed unauthenticated at
`GET /geocode/search` (`routes/geocode.ts:26-36`, mounted `index.ts:112`).

The OSMF Nominatim usage policy states an *"absolute maximum of 1 request per
second"* **per application, not per user** — *"the sum of traffic by all your
users should not exceed the limits."* It then names this exact feature:

> *"Auto-complete search: This is not yet supported by Nominatim and you must
> not implement such a service on the client side using the API."*

and this exact industry:

> *"Applications and services whose primary function is related to geocoding
> must run their own service. This includes but is not limited to package/vehicle
> tracking applications and API resellers."*

A ride-hailing app is a vehicle-tracking application whose search box is an
autocomplete. The rider app debounces at 400 ms with a 2-character minimum
(`location_search_sheet.dart:42`, `:75`), which is good client hygiene and does
not change the analysis: a single user typing one destination can emit several
requests, and the budget is one per second **across the entire platform**.

The 7-day KV cache (`geocode.ts:128`) is the only thing holding this together,
and F-21-15 explains why it leaks. When the block lands it will be keyed on the
User-Agent at `geocode.ts:108`, which names the company and an admin contact
address — so the failure arrives as an email, and search returns `[]` for every
user until someone ships a code change (the host is a literal, not a var).

### F-21-04 — No route cache, on an unauthenticated endpoint

Grepping every `SESSIONS.get` / `SESSIONS.put` in the API returns three caches
(§3.7). None of them caches a route. `getRoute` performs a network call on every
single invocation.

Compounding it, the endpoint that calls it is public. `POST /trips/estimate` is
registered at `trips.ts:315`; `authMiddleware` is applied at `trips.ts:346`,
*after* it. `GET /geocode/*` is likewise unauthenticated. Both are rate-limited
only by `cf-connecting-ip` (`rateLimit.ts:20`) at 30/60 s and 20/60 s
respectively — per IP, so the ceiling is the number of IPs an attacker has.

Legitimate traffic already amplifies this: the rider home screen re-polls
`/trips/estimate` every 45 seconds while open (`home_screen.dart:197-205`),
mostly to refresh nearby-car markers rather than to re-quote a fare — and each
poll is a full OSRM route request with `overview=full`. Booking then issues yet
another (F-21-16).

Three things are true at once: the platform is spending someone else's free
quota, it cannot see how much of it it is spending, and anyone on the internet
can spend it on the platform's behalf under the platform's name.

### F-21-05 — Attribution is written down and never shown

`packages/flutter_shared/lib/theme/app_theme.dart:494-495`:

```dart
/// Required by the CARTO / OpenStreetMap terms of use.
static const String attribution = '© OpenStreetMap contributors © CARTO';
```

`MapTiles.urlForContext` is used at `home_screen.dart:567` and
`trip_screen.dart:248`. `MapTiles.attribution` is used **nowhere** — grep across
`apps/rider`, `apps/captain` and `packages/flutter_shared` returns only the
definition. Neither map builds a `RichAttributionWidget` or any equivalent.

The admin console does it correctly: `LiveMapPage.tsx:73` passes
`'&copy; OpenStreetMap & CARTO'` to the tile layer. So the requirement is
understood by the team and satisfied on the surface with the fewest users,
while both consumer apps ship without it. That pattern — a correct
implementation existing next to an unused constant — is the same failure T12
documented for design tokens.

### F-21-06 — Nominatim returns nothing for how Egyptians actually speak

This is measured, not inferred. Fourteen queries an Egyptian rider would
plausibly type were run against the live endpoint on 2026-08-01 with exactly
the parameters the code sends (`format=jsonv2&countrycodes=eg&limit=5&accept-language=ar,en`,
per `geocode.ts:100-102`), at ~1 req/s with a descriptive User-Agent.

| Query | Meaning | Result | Verdict |
|---|---|---|---|
| `أمام سيتي ستارز` | "in front of City Stars" | `[]` | **empty** |
| `بجوار مستشفى الدمرداش` | "next to Demerdash Hospital" | `[]` | **empty** |
| `محطة مترو المعادي` | "Maadi Metro Station" | `[]` | **empty** |
| `كوبري أكتوبر` | "October Bridge" | `كوبرى طريق الواحات`, 6th of October City, **Giza** (29.911, 30.931) | **wrong** — ~30 km off, wrong governorate |
| `سيتي ستارز` | "City Stars" | #1 = `مدينه سيتى ستارز`, **Red Sea** (27.304, 33.724); #2 = the actual mall | **wrong first hit** — ~700 km off |
| `مترو المعادي` | "Maadi metro" | `مترو حدائق المعادى` (Maadi *Gardens*), returned twice | near-miss + duplicate |
| `ميدان التحرير` | "Tahrir Square" | #1 correct (30.044, 31.236); #2 Tahrir Sq in **Benha**, Qalyubia | ok, with noise |
| `كوبري ٦ أكتوبر` | with Arabic-Indic ٦ | correct, 30.049, 31.232 | ok |
| `كوبري قصر النيل` | Qasr El Nil Bridge | correct | ok |
| `مطار القاهرة الدولي` | Cairo Int'l Airport | correct | ok |
| `عزبة الهجانة` | informal settlement | correct neighbourhood polygon | ok |
| `شارع التسعين الجنوبي` | South 90th St, New Cairo | correct | ok |
| `المعادي` | Maadi district | correct | ok |
| `مول العرب` | Mall of Arabia | correct | ok |

**8 clean, 3 empty, 3 wrong or misleading.** The pattern is sharp and it is not
about Arabic support — Arabic works fine. Nominatim is a *name matcher*, and
every failure is a query that is not purely a name:

- **Relative prefixes annihilate the query.** `سيتي ستارز` succeeds; `أمام سيتي
  ستارز` returns `[]`. The words `أمام` (in front of) and `بجوار` (next to) are
  how Egyptians give addresses, and they take the result count from five to
  zero.
- **A generic noun does the same.** `مترو المعادي` returns results;
  `محطة مترو المعادي` — adding the word "station" — returns none.
- **Ambiguity fails loudly and confidently.** `كوبري أكتوبر` is one of Cairo's
  best-known bridges. The API matched the token `أكتوبر` to the city *6th of
  October* and returned an unrelated trunk-road bridge in Giza. A rider who taps
  the first result is routed to the wrong side of the metropolis, and the fare
  is quoted for that trip.

Encouragingly, the informal-settlement case (`عزبة الهجانة`) and the
Arabic-Indic numeral case both worked, so OSM's Egypt coverage is better than
folklore suggests. The gap is **query understanding**, not data.

This is the single biggest usability gap in the product, as the brief
anticipated. It is also not fixable by swapping providers alone — a landmark
grammar is needed (§6, P1.2).

### F-21-07 — No geographic biasing on search

`geocode.ts:99-102` builds the search URL with `countrycodes=eg` and nothing
else. Nominatim supports `viewbox` plus `bounded=1` to constrain results, and
the code passes neither, even though the rider's position is known.

The measured consequences are in the table above: a Cairo rider searching
`سيتي ستارز` is offered a Red Sea locality first, and `ميدان التحرير` returns
Benha alongside the real one. The rider app partially masks this by sorting
results by distance when a reference point is supplied
(`location_service.dart:259-261`) — which reorders the list but still spends
result slots on entries 700 km away, and does nothing for the reverse-geocode
path. Adding `viewbox` around the rider's city with `bounded=1` is a two-line
change and the cheapest accuracy win in this document.

### F-21-08 — Nothing in the system models traffic

Three separate speed assumptions exist and none consults live conditions:

- OSRM's default `driving` profile — free-flow, from OSM `maxspeed` tags.
- `estimateDurationMin(distanceKm, 22)` in the fallback (`routing.ts:72`,
  `routing.ts:161`).
- A library default of 25 km/h (`packages/shared/src/index.ts:72`).

TomTom's 2025 Traffic Index for Cairo measures a **26.8 km/h** daily average,
**26.2 km/h** in the morning peak and **21.1 km/h** in the evening peak, with
congestion up 2.5 points year on year. Against a free-flow OSRM estimate of
roughly 45–55 km/h on Cairo arterials, peak-hour ETAs are optimistic by
approximately **45–58%** — a 12-minute promise on a 28-minute drive.

The fallback's flat 22 km/h is, by accident, close to reality in the evening
peak (−5%) and badly wrong off-peak (+80% at 02:00). So the system's *least*
sophisticated path is its most accurate one at exactly the hour it matters
most, which is a good illustration of how little signal is in any of these
numbers.

ETA error does not move the price here (the fare is negotiated), so this is S2
rather than S1. It moves everything else: captains judge whether a pickup is
worth accepting on a number that is half-real, and riders wait for a car whose
promised arrival was never achievable.

The cheapest meaningful fix needs no new vendor: replace the constant with a
time-of-day speed table, then learn real speeds from `trip_path_points` the
platform is already collecting (§6, P1.3).

### F-21-09 — `city` is client-supplied and it picks the tariff

`schemas.ts:45` and `:58`: `city: z.string().max(60).optional()`. No enum, no
cross-check against `pickupLat/Lng`. At `trips.ts:322-323` that string selects
the pricing row:

```ts
const city = body.city || c.env.DEFAULT_CITY || "cairo";
const pricing = await getPricing(c.env.DB, city);
```

So the client names the city and the server prices the trip accordingly. If any
second city is ever seeded with a cheaper tariff (`migrations` comments at
`schemas.ts:302` anticipate exactly that), a modified client selects it. Today
only `cairo` is configured, which is the only reason this is S2 and not S1 —
**it becomes S1 on the day a second city launches**, and the launch is unlikely
to remember this line.

The same string filters dispatch by exact equality (`captain.ts:378`), so a
captain who came online in `giza` cannot see a `cairo` trip picked up 2 km
away across a bridge. There is no polygon, no bounding box, no boundary of any
kind — "city" is a label two parties must spell identically, and the edge
behaviour the brief asks about is simply: the trip is invisible.

Coordinates are validated only to planetary range (`schemas.ts:41-44`), so
nothing rejects a booking from Paris to London — OSRM would route it happily
and the Cairo tariff would price it.

### F-21-10 & F-21-11 — The captain's position is unreliable exactly when it matters

Two client-side defects combine into one user-visible symptom: during a real
trip, the car on the rider's map stops moving.

**Cadence.** `captain_state.dart:623-626` sets `LocationAccuracy.high` with
`distanceFilter: 10` during a trip, and no time floor. At 40 km/h a vehicle
crosses 10 m roughly every 0.9 s, and every fix triggers a POST
(`captain_state.dart:651-653`). The server allows 30 requests per 60 s
(`captain.ts:192-197`) — about **2× under** what the client can emit. Excess
requests are rejected, so the rider sees a stale position and the server's own
`trip_path_points` record thins out.

**Backgrounding.** `captain_state.dart:1082-1089` stops the location stream on
`AppLifecycleState.paused/inactive/hidden`. No Android foreground service or iOS
background-location mode was found. A captain who pockets the phone or lets the
screen sleep — normal driving behaviour — stops reporting entirely until they
wake the app.

Note the interaction with F-21-14: the 30-second path sampler cannot record what
the client never sends, so both the live experience and the forensic record
degrade together.

The idle profile (50 m filter, `captain_state.dart:621`) is well within budget;
only the in-trip profile is misconfigured. A 3-second minimum interval alongside
the distance filter fixes the cadence half, and it costs nothing.

### F-21-12 & F-21-13 — The rider is shown a route that is stale, or invented

`trip_screen.dart:46-54` loads geometry once when the trip screen opens and
never refetches. Any detour, reroute or road closure leaves the drawn line
describing a journey that is no longer happening.

Worse is what happens when the geometry is the fallback. `routing.ts:76-79`
returns exactly two points — pickup and dropoff. `location_service.dart:49`
defines `hasRealGeometry => points.length > 2`, which is the right test, and
**nothing ever calls it**. `home_screen.dart:586-607` renders any polyline with
at least two points identically. The rider sees a confident line straight across
the Nile, with no bridge, distinguished only by a small `تقريبي` ("approximate")
label at `home_screen.dart:1297-1304`.

The information needed to do better is already in the response — `source` is
plumbed all the way to `isApproximate` (`location_service.dart:98`) and then
spent on a text label. Rendering that state as a dashed line with an explicit
"route unavailable" treatment is a small change that stops the product from
asserting something false.
---

## 5. Benchmark gap

### 5.1 How the competition solves this

**Uber** *(confident)* runs its own map layer over licensed and self-collected
data, with traffic-aware ETAs trained on its own historical trip telemetry —
the same class of data sitting unused in `trip_path_points`. Its most relevant
mechanism for Egypt is **curated pickup points**: at airports, malls and
stadiums, Uber does not trust the GPS pin, it offers a named list of surveyed
pickup zones ("Terminal 3, Door 4"). Synaptic Go has nothing equivalent
(F-21-17). Uber also snaps the driven path to roads for its fare receipt and
dispute flow.

**Careem** *(confident on direction, assumed on implementation detail)* invested
specifically in the problem F-21-06 measures: addressing in Arabic-speaking
markets where street numbers are not how people navigate. Its search is built
around landmarks and saved places rather than street parsing, and it carries a
curated POI set for exactly the queries Nominatim returns `[]` for. For an
Egyptian competitor this is the benchmark that matters most — Careem's Cairo
search understands `أمام` and Synaptic Go's returns an empty list.

**inDrive** *(confident)* is the closest model, since Synaptic Go copies its
negotiated-price mechanic. Worth noting what that implies: because inDrive's
price is also agreed up front, inDrive's *distance estimate is also final* — and
inDrive still shows both parties a real routed distance before they agree. The
negotiated model does not excuse a straight-line estimate; it raises the stakes
on it.

### 5.2 Where Synaptic Go sits

| Capability | Uber | Careem | inDrive | **Synaptic Go** |
|---|---|---|---|---|
| Routing infrastructure | owned | licensed | licensed | **public demo server** (F-21-01) |
| Traffic-aware ETA | yes | yes | yes | **none** (F-21-08) |
| Fallback when routing fails | rare, and priced conservatively | rare | rare | **straight line, becomes the price** (F-21-02) |
| Landmark / relative-address search | yes | **core investment** | yes | **returns `[]`** (F-21-06) |
| Curated pickup zones | yes | yes | partial | none (F-21-17) |
| Snap-to-road path for disputes | yes | yes | yes | raw 30 s fixes (F-21-14) |
| Tile licence | owned | licensed | licensed | free CARTO, **unattributed** (F-21-05) |
| Live captain position in background | yes | yes | yes | **stops on screen sleep** (F-21-11) |

Synaptic Go is not behind on *ambition* — the geohash cell layer, the OSRM
`/table` fan-in for arrival ETAs and the per-origin degradation in
`routing.ts:143-149` are genuinely competent pieces of engineering. It is
behind on **foundation**: all of that sophistication is built on services it
does not own and is not permitted to use at this scale.

### 5.3 Provider comparison and recommendation

Volumes assume, per trip: ~3 routing calls (estimate poll, quote, booking),
~4 matrix elements for arrival ETAs, ~2 geocode sessions, ~2 reverse geocodes,
~15 tile loads. At 1,000 trips/day that is ~90k routing calls and ~450k tiles a
month; at 10,000 trips/day, ~900k and ~4.5M. *These multipliers are assumptions,
stated so they can be argued with; F-21-16 and the 45 s poll mean today's real
figure is higher.*

| Provider | Routing accuracy (Cairo) | Traffic | Arabic search | Licence fit | ~1k trips/day | ~10k trips/day | Migration |
|---|---|---|---|---|---|---|---|
| **Status quo** (OSRM demo + Nominatim + CARTO) | good when it answers | none | poor (F-21-06) | **violates all three** | $0 | $0 | — |
| **Self-hosted OSRM** + MapTiler tiles | good | none | n/a (pair with geocoder) | clean | **~$40/mo** | ~$800–1,300/mo | **M** |
| **Self-hosted OSRM + tiles + Pelias** | good | none | moderate | clean | ~$40/mo | **~$60–85/mo** | **L** |
| **Mapbox** (routing + geocode + tiles) | good | partial | moderate | clean | **~$0** (free tiers) | ~$4,900/mo | **S–M** |
| **Google** (Routes + Places + tiles) | **best** | **best** | **best** | restrictive: results may not be drawn on a non-Google map | ~$1,550/mo | ~$15,800/mo | **M** |
| Stadia Maps (hosted Valhalla) | good | partial | moderate | clean | ~$20–80/mo | ~$80–250/mo | S–M |

*Prices are 2025–26 list prices; Google's per-SKU structure and any subscription
tiering should be re-checked before budgeting (`needs-check`). Self-hosted OSRM
sizing: the Geofabrik `egypt-latest.osm.pbf` extract is ~169 MB, which
preprocesses and serves comfortably on an 8 GB VM (~$9–17/mo at Hetzner,
~$48–60 at DigitalOcean/AWS).*

**Recommendation — split the stack by where quality actually pays.**

1. **Routing and matrix → self-hosted OSRM.** Egypt is a small extract; this is
   a ~$10–20/month box that removes the S1 dependency, removes the rate limit,
   and makes the fallback rare rather than routine. It buys no traffic
   awareness, which is fine because OSRM has none today either — this is a
   licence and reliability fix, deliberately not an accuracy change.
2. **Search and autocomplete → a commercial geocoder, Google Places preferred.**
   This is the one place where paying is clearly correct. F-21-06 shows the
   current search failing on the most natural phrasing in the market, and no
   amount of self-hosting fixes query understanding. Google's Arabic Egypt POI
   coverage is materially better than OSM's, and session-token billing keeps
   autocomplete cost low. *Constraint to design around: Google's terms forbid
   rendering Google-sourced results on a non-Google map, so either the map moves
   to Google too, or Places is used strictly for resolving a text query to
   coordinates.* That constraint is the main argument for Mapbox as the
   pragmatic alternative.
3. **Tiles → MapTiler or Mapbox on a paid plan, with attribution rendered.**
   Cheap, and it retires F-21-05 and the CARTO free-tier exposure together.

Total at 1,000 trips/day lands around **$40–80/month**. The current bill is
zero and the current risk is the whole platform.

---

## 6. Improvement plan

### P0.1 — Stand up owned routing infrastructure

- **Goal.** Fare estimates stop depending on a server that is entitled to block
  the platform without notice.
- **Design.** Deploy OSRM on a small VM from the Geofabrik Egypt extract
  (~169 MB), MLD pipeline, behind a health-checked hostname. Set `OSRM_URL` per
  environment. Keep the existing client code — `routing.ts` already takes the
  base URL as a parameter (`routing.ts:24`, `routing.ts:110`), so no call-site
  changes are needed. Add a weekly cron to re-extract and re-preprocess.
- **Files to change.** `apps/api/wrangler.toml:88,148,176` (the three
  `OSRM_URL` values); `routing.ts:15` and `trips.ts:177` (make the hardcoded
  demo default an error in production rather than a silent default); new
  `docs/plan/assets/21-osrm-deploy.md` for the runbook.
- **DB.** none.
- **API contract.** none.
- **Effort.** M (1–3 days including preprocessing and a runbook).
- **Risk.** A single VM is a new SPOF — mitigate by keeping the haversine
  fallback as the last resort and alerting on `route_source` (P0.3). Rollback is
  a config value.
- **Acceptance criteria.** No environment references `router.project-osrm.org`;
  `/trips/estimate` p95 latency ≤ current; a forced OSRM outage produces alerts
  rather than silence.
- **Tests.** Integration test asserting `source == "osrm"` against the deployed
  host; a test that boots with `OSRM_URL` unset and fails closed in prod.

### P0.2 — Stop pricing contracts off a straight line

- **Goal.** A routing failure never silently becomes the settled fare.
- **Design.** Split the two callers, which today share one function and one
  behaviour:
  - **`/trips/estimate`** (preview) may fall back, but must return
    `source: "haversine"` prominently and the client must render it as
    unavailable rather than approximate (P1.1).
  - **`POST /trips`** (the contract) must **not** silently fall back. On OSRM
    failure, retry once, then return `503 ROUTE_UNAVAILABLE` and let the rider
    retry. Booking is a deliberate act seconds long; failing it is recoverable,
    while mispricing it is not.
  Additionally raise the fallback factor from 1.35 toward the measured Cairo
  median of ~1.45, and make it a config value rather than a literal — but treat
  that as damage limitation, not a fix.
- **Files to change.** `apps/api/src/lib/routing.ts:61-63` (add a
  `allowFallback` parameter); `apps/api/src/routes/trips.ts:382-386` (booking
  path); `apps/api/src/lib/routing.ts:71,160` (factor → config).
- **DB.** Migration `0020_trip_route_source.sql` — `ALTER TABLE trips ADD COLUMN
  route_source TEXT;` (values `osrm` | `haversine`), written at
  `trips.ts:441-481`.
- **API contract.** `POST /trips` gains `503 { error, code: "ROUTE_UNAVAILABLE" }`.
  `POST /trips/estimate` response is unchanged in shape.
- **Effort.** S.
- **Risk.** Booking failures become user-visible during an OSRM outage. That is
  the intent, and P0.1 makes such outages rare. Rollback: re-enable fallback via
  the same flag.
- **Acceptance criteria.** No trip row can be created with a haversine-derived
  distance; `route_source` is populated on 100% of new trips; a simulated OSRM
  outage yields 503s and zero mispriced bookings.
- **Tests.** Unit test with OSRM stubbed to fail, asserting 503 from `POST
  /trips` and a flagged estimate from `/trips/estimate`.

### P0.3 — Make geo degradation observable

- **Goal.** Someone finds out when routing quality drops, without a customer
  telling them.
- **Design.** Emit counters for OSRM success/failure/timeout, Nominatim
  success/empty/failure, and fallback rate. Alert when the fallback rate over
  15 minutes exceeds 2%, or when Nominatim empty-result rate exceeds 25%
  (today's measured baseline is ~21% — see F-21-06 — so this alert would fire
  on arrival, which is the point).
- **Files to change.** `routing.ts:61`, `routing.ts:150` (instrument the catch
  blocks — they currently swallow silently); `geocode.ts:52-60`, `:114`;
  observability config in `wrangler.toml:151,179`.
- **DB.** none (metrics only).
- **API contract.** none.
- **Effort.** S.
- **Risk.** Negligible. Coordinate with **T22** so this lands in the same
  telemetry pipeline rather than a parallel one.
- **Acceptance criteria.** A dashboard shows fallback rate per hour; killing
  OSRM in staging fires the alert within 15 minutes.
- **Tests.** Assert counters increment on stubbed failure.

### P0.4 — Render tile attribution

- **Goal.** Stop shipping a licence breach in both consumer apps.
- **Design.** Add an attribution widget to every `FlutterMap`, sourcing the
  constant that already exists.
- **Files to change.** `apps/rider/lib/screens/home/home_screen.dart:553-577`,
  `apps/rider/lib/screens/trip/trip_screen.dart:236-275`, the captain map shell,
  consuming `app_theme.dart:495`. Best done as a shared
  `packages/flutter_shared/lib/widgets/map_attribution.dart` so it cannot drift
  between apps again.
- **DB / API.** none.
- **Effort.** S (< half a day).
- **Risk.** None.
- **Acceptance criteria.** Attribution visible on every map surface in both
  apps, light and dark.
- **Tests.** Widget test asserting the attribution string renders in each map screen.

### P1.1 — Tell the truth about an unavailable route

- **Goal.** Never draw a confident line across the Nile.
- **Design.** Use the `hasRealGeometry` predicate that already exists
  (`location_service.dart:49`) and is never called. When false: render a dashed,
  desaturated line, replace the distance figure with "—", and show an explicit
  "تعذّر حساب المسار" banner rather than the small `تقريبي` label.
- **Files to change.** `apps/rider/lib/screens/home/home_screen.dart:586-607`,
  `:1297-1304`; `apps/rider/lib/services/location_service.dart:98`.
- **DB / API.** none.
- **Effort.** S. **Risk.** None. Coordinate with **T09**/**T12** for the visual
  treatment.
- **Acceptance criteria.** With OSRM stubbed down, no solid polyline is drawn and
  no distance figure is presented as fact.
- **Tests.** Widget test with a 2-point geometry.

### P1.2 — A landmark-aware search layer

- **Goal.** `أمام سيتي ستارز` returns City Stars.
- **Design.** Three layers in front of the geocoder:
  1. **Normalise the query.** Strip Arabic diacritics, unify `أإآ→ا`, `ة→ه`,
     `ى→ي`, convert Arabic-Indic digits, and **strip leading relative
     prepositions** (`أمام`, `بجوار`, `جنب`, `خلف`, `قدام`, `تحت`, `عند`) before
     dispatching. This alone converts three measured `[]` results into hits.
  2. **A curated Cairo POI table** consulted before the network call — malls,
     metro stations, bridges, hospitals, universities, stadiums, airport
     terminals — with Arabic aliases and colloquial spellings. A few hundred rows
     covers the overwhelming majority of destination searches.
  3. **Commercial geocoder** as the network tier (§5.3), with `viewbox`+`bounded`
     biasing to the rider's city (fixes F-21-07 immediately, even before any
     provider change).
  Then use the normalised string as the cache key, fixing F-21-15.
- **Files to change.** `apps/api/src/lib/geocode.ts:86-129` (normalisation,
  viewbox, cache key), `:19-21`; new `apps/api/src/lib/places.ts`.
- **DB.** Migration `0021_curated_places.sql` — `curated_places(id, name_ar,
  name_en, aliases TEXT, lat REAL, lng REAL, city TEXT, category TEXT,
  pickup_hint TEXT)` plus an index on `city`.
- **API contract.** `GET /geocode/search` response gains `source: "curated" |
  "provider"` per result; shape otherwise unchanged.
- **Effort.** L (the curated set is data work as much as code).
- **Risk.** A stale curated pin outranks a correct provider result — mitigate
  with an admin edit surface (**T11**) and a freshness column.
- **Acceptance criteria.** All 14 measured queries in F-21-06 return a correct
  first result; zero empty results for the three relative-prefix queries.
- **Tests.** A regression suite built from the F-21-06 table — it is already a
  test corpus.

### P1.3 — Time-of-day speed profiles

- **Goal.** ETAs that are wrong by ~10% instead of ~50%.
- **Design.** Replace the flat 22/25 km/h constants with a lookup by
  hour-of-day and day-of-week, seeded from published Cairo figures (26.8 km/h
  average, 26.2 AM peak, 21.1 PM peak) and then **learned from
  `trip_path_points`**, which already records the platform's own trips. Apply the
  profile as a multiplier on OSRM's free-flow duration too, not only to the
  fallback — OSRM is the more optimistic of the two.
- **Files to change.** `packages/shared/src/index.ts:72`,
  `apps/api/src/lib/routing.ts:72,161`; new `apps/api/src/lib/speed_profile.ts`.
- **DB.** Migration `0022_speed_profiles.sql` — `speed_profiles(city, dow, hour,
  kmh, sample_count, updated_at)`.
- **API contract.** none.
- **Effort.** M. **Risk.** A bad profile degrades ETAs — gate behind a config
  flag and compare against actuals before enabling. Coordinate with **T05**,
  since duration feeds the fare.
- **Acceptance criteria.** p50 absolute ETA error under 15% measured against
  completed trips; profile refreshed weekly.
- **Tests.** Backtest the profile against historical `trip_path_points`.

### P1.4 — Fix captain location cadence and backgrounding

- **Goal.** The car on the rider's map keeps moving for the whole trip.
- **Design.** Add a 3-second minimum interval alongside the 10 m distance filter
  so the client cannot outrun the server's 30/60 s budget, and add a foreground
  service (Android) / background location mode (iOS) for the duration of an
  active trip only, with a visible notification.
- **Files to change.** `apps/captain/lib/services/captain_state.dart:623-626`,
  `:1082-1089`, `:651-653`; Android manifest and iOS `Info.plist`.
- **DB.** none. **API contract.** none.
- **Effort.** M (store-policy paperwork for background location is the long
  pole — coordinate with **T26**).
- **Risk.** Background location triggers store review scrutiny and battery
  complaints; scope it strictly to active trips. Coordinate with **T10**.
- **Acceptance criteria.** Sustained in-trip push rate ≤ 20/min; zero 429s from
  `POST /captain/location` in a 30-minute drive test; position continues updating
  with the screen off.
- **Tests.** Instrumented drive test; unit test on the throttle.

### P1.5 — Route caching and call deduplication

- **Goal.** Cut OSRM calls per trip by well over half, and stop paying twice for
  the same answer.
- **Design.** Two changes. First, **reuse the estimate**: booking currently
  re-routes from scratch (`trips.ts:382`) — cache the quoted route against the
  rider for a short window and reuse it, which also guarantees the booked price
  matches the quoted one. Second, add a **KV route cache** keyed on
  coordinate-rounded endpoints:
  - snap both endpoints to **3 dp** (≈111 m × 96 m at Cairo's latitude) when the
    straight-line distance exceeds 3 km — worst-case added error ~1.5% on a
    10 km trip;
  - keep **4 dp** (≈11 m × 10 m) below 3 km, where a 73 m displacement is a
    material share of the journey;
  - TTL 6 hours (no traffic in the answer, so it does not stale quickly).
  Also drop `overview=full` on the 45-second nearby-cars poll — that call needs
  proximity, not a polyline.
- **Files to change.** `apps/api/src/lib/routing.ts:21-64` (cache wrapper),
  `apps/api/src/routes/trips.ts:330-339,382-386`,
  `apps/rider/lib/screens/home/home_screen.dart:197-205`.
- **DB.** none (KV). **API contract.** none.
- **Effort.** M.
- **Risk.** A cached route outliving a road closure — bounded by the 6 h TTL.
- **Acceptance criteria.** ≥50% cache hit rate on popular corridors after a
  week; OSRM calls per completed trip ≤ 1.5.
- **Tests.** Assert identical rounding keys for endpoints within one cell; assert
  booking reuses the quoted route.

### P2.1 — Curated pickup zones

- **Goal.** Pickups at the airport, City Stars and the stadium actually work.
- **Design.** Extend `curated_places` (P1.2) with named pickup points and
  polygons for venues where GPS is unreliable. When a pickup pin falls inside a
  venue polygon, present a chooser ("Terminal 1 — Departures") instead of
  accepting the raw pin.
- **Files.** `apps/api/src/lib/places.ts`, `home_screen.dart` pin-confirm flow
  (`:1459-1483`), admin CRUD (**T11**).
- **DB.** Migration `0023_pickup_zones.sql`.
- **Effort.** L. **Risk.** Low. **Acceptance.** Airport pickups resolve to a
  named zone in ≥90% of cases.

### P2.2 — Snap-to-road path and a dispute record

- **Goal.** "The captain took the long way" is answerable with data.
- **Design.** Tighten sampling to ~10 s during trips, run the stored points
  through OSRM's `/match` (map matching) at completion, persist the matched
  polyline and its true distance, and write the `speed` column that
  `migrations/0002_enhancements.sql:20` already provides and
  `captain.ts:247-251` ignores. Storage growth must be agreed with **T08**.
- **Files.** `apps/api/src/routes/captain.ts:237-252`,
  `apps/api/src/routes/trips.ts:682-700`, new matching helper.
- **DB.** Migration `0024_trip_matched_path.sql` — `trips.matched_distance_km`,
  `trips.matched_geometry`.
- **Effort.** L. **Risk.** Storage and D1 write volume — see **T08**.
- **Acceptance.** Completed trips carry a matched path; distance reconstructable
  within 5% of the driven route.

### P2.3 — Real geofences

- **Goal.** `city` stops being an honour-system string.
- **Design.** Store city polygons; derive `city` **server-side** from
  `pickupLat/Lng` and ignore the client's value for pricing. Reject coordinates
  outside the service area with a clear error. Define explicit cross-boundary
  behaviour (Cairo↔Giza should share a dispatch pool — they are one metropolitan
  area split by a river, and today they are two invisible silos).
- **Files.** `apps/api/src/lib/schemas.ts:45,58`, `trips.ts:322,378`,
  `captain.ts:203,378`, new `apps/api/src/lib/geofence.ts`.
- **DB.** Migration `0025_city_boundaries.sql`.
- **Effort.** M. **Risk.** Mis-drawn boundaries reject valid trips — ship in
  log-only mode first. Coordinate with **T05** (tariffs) and **T06** (dispatch).
- **Acceptance.** Client-supplied `city` no longer affects pricing; a Giza
  captain sees an adjacent Cairo trip.

### P2.4 — Offline and dead-zone resilience

- **Goal.** The map does not go blank in the Azhar tunnel.
- **Design.** Swap `NetworkTileProvider` (`home_screen.dart:571`) for a cached
  provider with a bounded on-disk cache, and show an offline banner —
  `offline_gate.dart` already exists in `flutter_shared` and is not used by the
  map screens. **Note:** tile pre-caching is forbidden by the OSM tile policy, so
  this depends on the paid tile provider from §5.3.
- **Effort.** M. **Risk.** Licence — resolved by P0.1's provider change.

---

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Owned OSRM | **P0 — before production traffic** | M | backend / ops |
| P0.2 No silent fallback pricing | **P0** | S | backend |
| P0.3 Geo observability | **P0** | S | backend / ops |
| P0.4 Tile attribution | **P0** | S | Flutter |
| P1.1 Honest unavailable-route UI | P1 — first 30 days | S | Flutter |
| P1.2 Landmark search + normalisation + viewbox | P1 | L | backend + data |
| P1.3 Time-of-day speed profiles | P1 | M | backend |
| P1.4 Captain cadence + background | P1 | M | Flutter + ops |
| P1.5 Route cache + dedupe | P1 | M | backend |
| P2.1 Curated pickup zones | P2 — next 90 days | L | backend + admin |
| P2.2 Snap-to-road dispute record | P2 | L | backend |
| P2.3 Real geofences | P2 | M | backend |
| P2.4 Offline tiles | P2 | M | Flutter |

The P0 set is four items, three of them S. **P0.4 and P0.3 are each under a
day.** The only genuinely multi-day item before production traffic is standing
up OSRM, and the cheapest partial mitigation of F-21-07 — adding `viewbox` to
the search URL — is two lines that could ship this week inside P1.2.

---

## 8. Metrics

| Metric | Current | Target |
|---|---|---|
| Fallback rate (`route_source = haversine` ÷ all trips) | **unmeasurable** — not persisted | < 0.5% |
| OSRM error/timeout rate | unmeasurable — swallowed at `routing.ts:61` | < 1% |
| OSRM calls per completed trip | ≥ 3 (estimate poll + quote + booking) | ≤ 1.5 |
| Route cache hit rate | 0% (no cache exists) | > 50% on popular corridors |
| Nominatim/geocoder empty-result rate | **~21% measured** (3 of 14, F-21-06) | < 5% |
| Search first-result-correct rate | **~57% measured** (8 of 14) | > 90% |
| Geocode cache hit rate | unmeasured; low by construction (F-21-15) | > 60% |
| p50 / p90 absolute ETA error vs. actual | est. 45% / 58% in peak (F-21-08) | < 15% / < 30% |
| Distance error vs. matched path | unmeasurable until P2.2 | < 5% |
| `429` rate on `POST /captain/location` | unmeasured; structurally ~2× over budget | ~0 |
| In-trip location gap p95 | unmeasured; unbounded when screen sleeps | < 15 s |
| Monthly geo vendor spend | $0 (unlicensed) | budgeted, ~$40–80/mo at 1k trips/day |

The first two rows are the important ones: **the platform currently cannot
distinguish "routing is healthy" from "routing has been blocked and every fare
is a straight-line guess."** P0.3 exists to make the rest of this table
measurable at all.

---

## 9. Cross-cutting notes

- **T05 (Pricing, Surge & Bidding).** Distance and duration are pricing inputs
  and both are unreliable (F-21-02, F-21-08). Also: `city` is client-supplied
  and selects the tariff row (`trips.ts:322-323`) — today harmless with one city
  configured, an exploitable price selector the moment a second tariff exists
  (F-21-09). Separately, `surge_multiplier` is applied to the total at
  `trips.ts:395-397` *after* `calculateFare` has already applied `minFare`, which
  looked like a possible double-application boundary; it is your call, not mine.
- **T03 (Money Integrity).** Every haversine-priced trip is a permanently
  mispriced ledger entry with no reconstructable evidence (F-21-02 + F-21-14).
  If you are designing dispute/adjustment flows, note there is currently no
  server-side record of whether a trip was priced by a router or a ruler.
- **T02 (Authorization / IDOR).** `POST /trips/estimate` sits above
  `authMiddleware` (`trips.ts:315` vs `:346`) and `GET /geocode/*` is mounted
  unauthenticated (`index.ts:112`). Both are IP-keyed only (`rateLimit.ts:20`)
  and both spend third-party quota on the platform's identity (F-21-04).
- **T06 (Dispatch & Matching).** Two incompatible distance notions coexist:
  `findNearbyCaptains` ranks by straight-line km (`GeoCell.ts:57`) while bid ETAs
  are routed minutes (`trips.ts:293`). Across the Nile these disagree sharply —
  the nearest captain by ruler can be the furthest by road. Also `captain.ts:378`
  filters offers on exact `city` string equality, so Giza and Cairo are separate
  pools with no bridge between them (F-21-09).
- **T07 (Realtime).** `location.captain` broadcasts on every accepted location
  POST (`captain.ts:254-265`); the client cadence problem in F-21-10 is also a
  WebSocket fan-out volume problem.
- **T08 (Data Model).** `trip_path_points` has an unused `speed` column
  (`migrations/0002_enhancements.sql:20`, never bound at `captain.ts:247-251`),
  and P2.2 proposes tightening sampling to ~10 s plus storing a matched
  polyline — please size that growth with me rather than discovering it.
- **T09 / T10 (Rider & Captain journeys).** Rider permission denial is silent
  (`home_screen.dart:139-141`) where the captain app surfaces an error
  (`captain_state.dart:533-543`); the rider takes a single one-shot fix and never
  updates its own position; the captain has no background tracking (F-21-11).
- **T11 (Admin).** The live map draws straight-line polylines between pickup and
  dropoff (`LiveMapPage.tsx:136-139`) and never requests real geometry, so ops
  cannot see actual routes. Curated places and pickup zones (P1.2, P2.1) need an
  admin CRUD surface. Leaflet is loaded from `unpkg.com` without SRI
  (`LiveMapPage.tsx:60-61`).
- **T12 (Design System).** `MapTiles` correctly reads
  `Theme.of(context).brightness` for dark-mode tiles (`app_theme.dart:500-501`) —
  a good pattern. The unused `attribution` constant (`:495`) is another instance
  of the "correct value defined, never consumed" failure T12 documents.
- **T14 (i18n / RTL).** Nominatim returns `display_name` as a long
  comma-separated Arabic string rendered raw (`location_search_sheet.dart:311`);
  it needs structuring, and the search `TextField`
  (`location_search_sheet.dart:178`) sets no explicit `textDirection`.
- **T22 (Observability).** P0.3's counters should land in your pipeline, not a
  parallel one.
- **T24 (Performance & Cost).** F-21-04 and P1.5 are as much a cost story as a
  correctness one; the 45 s nearby-cars poll pulls a full polyline it never uses
  (`home_screen.dart:197-205`, `routing.ts:30`).
- **T25 (Privacy).** `trip_path_points` is a precise movement history with no
  retention policy found; reverse-geocode cache entries persist 30 days keyed by
  ~11 m coordinate cells (`geocode.ts:82`).
- **T26 (Store Readiness).** P1.4's background location will require a
  justification in both stores' review processes.
- **T27 (Cross-App Parity).** Concrete divergences found on this axis, all
  citing both sides: permission-denial UX — rider silent
  (`home_screen.dart:139-141`) vs. captain explicit
  (`captain_state.dart:533-543`); location strategy — rider one-shot
  `getCurrentPosition` (`home_screen.dart:154-159`) vs. captain
  `getPositionStream` with adaptive accuracy profiles
  (`captain_state.dart:619-626`); the Cairo fallback coordinate duplicated across
  `home_screen.dart:556`, `trip_screen.dart:240-243`,
  `location_search_sheet.dart:52` and `LiveMapPage.tsx:68` with no shared
  constant; and attribution absent from both apps while present in admin
  (`LiveMapPage.tsx:73`). `captain_state.dart` (1189 lines) and
  `app_state.dart` (696 lines) independently reimplement HTTP, auth and profile
  handling with no shared base — any fix here must be applied twice, which is
  exactly the systematic problem you own.

---

## 10. Open questions

1. **Do we pay for search quality?** F-21-06 shows the free geocoder failing on
   the most natural Egyptian phrasing. Options: (a) self-host everything and
   accept the gap; (b) self-host routing, pay for Places autocomplete only —
   ~$40–80/month at launch volume; (c) go all-Google for best quality at
   ~$1,550/month at 1k trips/day, accepting the map lock-in.
   **Recommendation: (b).** Pay precisely where the measured gap is, and note
   Careem treats this as a core investment in this market.
2. **Does booking fail when routing fails?** P0.2 proposes a `503` rather than a
   straight-line price. This trades a rare visible failure for the elimination of
   silent permanent mispricing. **Recommendation: yes, fail the booking** — but
   it is a product decision about which failure the business prefers.
3. **Are Cairo and Giza one market or two?** Today they are separate dispatch
   pools by string equality (`captain.ts:378`) despite being one metropolitan
   area. **Recommendation: one pool, with tariffs still resolvable per
   governorate.** Needs T05 and T06 agreement.
4. **What retention applies to `trip_path_points`?** P2.2 increases both
   resolution and volume. Dispute resolution wants long retention; privacy
   (**T25**) and storage cost (**T08**) want short. **Recommendation: 90 days at
   full resolution, then keep only the matched summary polyline.**
5. **Is background captain tracking acceptable?** It is required for a live map
   that works (F-21-11), and it carries store-review and battery-perception
   costs. **Recommendation: yes, strictly scoped to an active trip with a visible
   notification.**
6. **Who owns the curated POI dataset?** P1.2 and P2.1 depend on a few hundred
   Cairo landmarks with Arabic aliases, and it needs an owner and a refresh
   cadence, not just a table. **Recommendation: seed from the measured failure
   corpus in F-21-06 and grow it from real zero-result searches once P0.3 makes
   them visible.**
