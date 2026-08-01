# 05 — Pricing, Surge & Bidding Economics

> Track: A — Foundation & safety-critical · Reviewer: `chat-20260801-1228-83a3` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `f906e0b06240ea84b20ef5c7b5633fd9abe02f8b`

Every `path:line` in this document was read at that commit. Where a claim could not be
verified from code it is labelled `needs-check` and never quietly assumed safe.

---

## 1. Scope

This document covers the whole surface on which a number becomes money:

- the fare formula and the route/distance inputs that feed it;
- the fare estimate (`POST /trips/estimate`) and the price frozen at trip creation;
- the rider's offer, the captain's counter-offer, bid acceptance and the assignment race;
- surge, promotions, vehicle-class multipliers and the per-city pricing table;
- the amount actually settled at `POST /trips/:id/complete`, and the contribution margin
  that amount produces.

**Explicitly out of scope**, owned by siblings:

| Not covered here | Owner |
|---|---|
| Wallet ledger invariants, double-entry correctness, balance reconciliation | **T03** |
| PSP integration mechanics, Paymob webhooks, captain payout rails | **T04** |
| Which captain is offered a trip, radius/dispatch fan-out, OfferScheduler waves | **T06** |
| Broadcast/WebSocket delivery of price events | **T07** |
| Column types, migration hygiene and constraint design as a discipline | **T08** |
| Authentication and object-level authorization as a discipline | **T01**, **T02** |
| Rider/captain screen-by-screen journeys | **T09**, **T10** |
| Systematic cross-app divergence | **T27** |

Where a pricing finding lands in a sibling's territory it appears in §9, not in §6.

One correction to the brief, stated up front because two of its premises are wrong and
following them would send an implementer to the wrong file:

1. The brief points at `migrations/0003_global_transport.sql` for `pricing_rules` and
   `vehicle_types`. Neither is there. `pricing_rules` is created and seeded in
   `migrations/0001_init.sql:46-56` and `:117-133`; `vehicle_types` is created and seeded in
   `migrations/0002_enhancements.sql:83-93`. Migration 0003 only adds
   `trips.surge_multiplier` (`migrations/0003_global_transport.sql:54`).
2. The brief asks about `pricing_rules.surge_multiplier`. **That column does not exist.**
   The only surge column in the schema is on `trips`. This is not pedantry — it is the
   reason surge is dead code (F-05-13).

---

## 2. What I actually read

Read in full, at the pinned commit:

| File | Note |
|---|---|
| `apps/api/src/lib/pricing.ts` | 38 lines. `pricingFromRow`, `estimateTripFare`, `cellKey`. `estimateTripFare` turns out to be dead. |
| `apps/api/src/lib/routing.ts` | OSRM client, 8 s abort, haversine fallback, `fareFromRoute`. The fare's real entry point. |
| `packages/shared/src/index.ts` | `calculateFare`, `haversineKm`, `estimateDurationMin`, `DEFAULT_PRICING`, `TRIP_TRANSITIONS`. |
| `packages/shared/src/index.test.ts` | 84 lines. The only fare tests that exist. |
| `apps/api/src/lib/schemas.ts` | Zod contracts; `createTripSchema`, `createBidSchema`, `pricingUpdateSchema` are the money-bearing ones. |
| `apps/api/src/routes/trips.ts` | 1371 lines. Read closely: `/estimate` (315-344), create (348-604), cancel (709-827), accept (829-889), complete (951-1088), bid (1144-1209), bids (1212-1259), accept-bid (1262-1371). |
| `apps/api/src/routes/promo.ts` | 108 lines, all four endpoints. |
| `apps/api/src/routes/captain.ts` | Read `/offers` (439-498) — what the captain is actually shown. Rest skimmed. |
| `apps/api/src/routes/admin.ts` | Read the pricing CRUD (333-415) and the dead cancellation-fee config. Rest skimmed. |
| `apps/api/src/routes/intercity.ts` | Read the per-seat price path (99-102, 394-431). Rest skimmed. |
| `apps/api/src/routes/payments.ts`, `apps/api/src/lib/paymob.ts` | Skimmed for the PSP fee basis. No fee rate is stored in the repo. |
| `apps/api/src/middleware/rateLimit.ts` | Default key is `cf-connecting-ip` (`:20`). |
| `apps/api/src/lib/types.ts` | `DbPricing` has no surge field — confirms F-05-13. |
| `migrations/0001_init.sql` | `pricing_rules` DDL + the three seeded cities. |
| `migrations/0002_enhancements.sql` | `vehicle_types`, `promo_codes`, `trip_promo`, `audit_log`. |
| `migrations/0003_global_transport.sql` | `trips.surge_multiplier`, intercity tables. |
| `migrations/0004_bidding_system.sql` | 18 lines. The entire bidding schema. |
| `migrations/0005_integer_currency_and_idempotency.sql` | The piastres migration — and what it missed. |
| `migrations/0016_system_config.sql` | Seeds `cancel_fee_egp` / `free_cancel_min`, which nothing reads. |
| `apps/admin/src/pages/PricingPage.tsx` | 760 lines. Six editable fields, a read-only multiplier badge, a hand-rolled preview calculator. |
| `apps/rider/lib/screens/home/fare_estimate_sheet.dart` | 831 lines. Where `offeredPrice` is built. |
| `apps/rider/lib/screens/home/vehicle_selector.dart` | 419 lines. Second copy of the multiplier table. |
| `apps/rider/lib/screens/ride/captain_bids_sheet.dart` | 789 lines. The rider's bid list and accept call. |
| `apps/captain/lib/screens/home/offer_card.dart` | 1006 lines. What the captain sees before accepting. |
| `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart` | 335 lines. The counter-offer modal. |
| `docs/BIDDING_SYSTEM.md`, `docs/COST.md`, `docs/API.md`, `docs/IMPROVEMENTS.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/CHECKLIST.md` | Read for intent and cost basis; treated as claims, not evidence. |

Skimmed rather than read: the non-pricing halves of `admin.ts`, `captain.ts`, `payments.ts`,
`intercity.ts`. Not read: the Durable Object implementations, `AppState`/`CaptainState`
Flutter service layers (this matters — see the caveat in F-05-02), `wrangler.toml`.

---

## 3. How it works today

### 3.1 The fare formula

`calculateFare` (`packages/shared/src/index.ts:83-119`) is the single source of fare truth:

```
distanceFare = distanceKm  * rule.perKm  * vehicleMult        index.ts:98
timeFare     = durationMin * rule.perMin * vehicleMult        index.ts:99
baseFare     = rule.baseFare             * vehicleMult        index.ts:100
rawUnsurged  = baseFare + distanceFare + timeFare + rule.bookingFee   index.ts:102
rawSurged    = rawUnsurged * surge                            index.ts:103
finalBefore  = max(rule.minFare, round2(rawSurged))           index.ts:104
total        = max(0, round2(finalBefore - discount))         index.ts:105
commission   = round2(total * rule.commissionRate)            index.ts:106
```

Three things to notice. `bookingFee` is *not* vehicle-multiplied but *is* surged. `minFare`
is applied **before** the discount (`:104` then `:105`), so a promo can push a fare below the
city's advertised floor — the repo's own test suite carries a `TODO` about exactly this
(`packages/shared/src/index.test.ts:41-49`). And every money value here is a JavaScript
`number`: the fare engine is floating-point end to end (`index.ts:17-38`).

The three `options` — `surgeMultiplier`, `vehicleMultiplier`, `discount` (`index.ts:94-96`) —
are implemented correctly and unit-tested in isolation. **No production call site passes any
of them.** `fareFromRoute` (`apps/api/src/lib/routing.ts:164-173`) calls
`calculateFare(distanceKm, durationMin, rule)` with no fourth argument, and `fareFromRoute` is
what both live endpoints use (`apps/api/src/routes/trips.ts:340`, `:393`). Surge and vehicle
multiplier are therefore always `1.0` and discount always `0` inside the engine; the surge and
discount that *do* reach a trip are applied by hand afterwards in `trips.ts`.

### 3.2 Distance and duration

`getRoute` (`apps/api/src/lib/routing.ts:21-64`) calls OSRM at
`env.OSRM_URL || "https://router.project-osrm.org"` (`routing.ts:15`, `trips.ts:176-178`) with an
8-second `AbortController` timeout (`routing.ts:32-33`). The entire body — URL build, fetch,
status check, JSON parse — sits inside one `try`, and the `catch` is bare:

```ts
} catch {
  return haversineFallback(pickup, dropoff);     // routing.ts:61-62
}
```

No error binding, no log, no metric. The fallback (`routing.ts:66-82`) is
`haversineKm(...) * 1.35` for distance and a flat 22 km/h assumption for duration.

`estimateTripFare` in `apps/api/src/lib/pricing.ts:23-34` implements a *second*, haversine-only
fare path. A repo-wide search finds no caller: it is dead code. The `1.35` road factor is
hardcoded three separate times (`routing.ts:71`, `routing.ts:160`, `pricing.ts:30`).

### 3.3 Estimate → create → assign → settle

**Estimate.** `POST /trips/estimate` (`trips.ts:315-344`) is registered *before*
`tripRoutes.use("*", authMiddleware)` at `trips.ts:346`, so it is **unauthenticated**. It is
rate-limited at 30/min keyed by `cf-connecting-ip` (`trips.ts:317`,
`apps/api/src/middleware/rateLimit.ts:19-20`). It returns the fare *and* the coordinates of
nearby captains (`trips.ts:336-342`). It does **not** apply surge.

**Create.** `POST /trips` (`trips.ts:348-604`) re-runs `getRoute` and `fareFromRoute`, then:

- applies surge by hand (`trips.ts:387-397`) — reading `surge_multiplier` off the
  `pricing_rules` row, a column that does not exist there (F-05-13);
- resolves a promo (`trips.ts:399-426`) and computes
  `finalEstimate = total - discount` (`:428`) and `commission = finalEstimate * rate` (`:429`);
- stores `estimated_fare = finalEstimate`, `offered_price = body.offeredPrice || finalEstimate`
  (`:438`, `:465-466`), and `commission` — but **not** `final_fare`, which stays `NULL`;
- increments `promo_codes.uses_count` immediately (`:499-503`);
- fans the offer out to up to 10 nearby captains (`:561-585`).

**What the captain sees.** `GET /captain/offers` (`apps/api/src/routes/captain.ts:462-467`) is a
bare `SELECT * FROM trips`, so the row carries both `offered_price` and `estimated_fare`. The
offer card renders `offered_price` first (`apps/captain/lib/screens/home/offer_card.dart:239-243`)
— the rider's number.

**Two ways to get assigned.**

*Direct accept* — `POST /trips/:id/accept` (`trips.ts:829-889`). Guarded on approval (`:837`),
online (`:842`), trip status (`:850`) and captain busy-ness (`:854-859`), then a conditional
`UPDATE ... WHERE id = ? AND status IN ('searching','offered')` with a `changes === 0` check
(`:861-870`). This is a correct compare-and-swap. **It sets no price column at all.**

*Bid flow* — `POST /trips/:id/bid` (`trips.ts:1144-1209`) inserts a row into `trip_bids`
(`:1170-1175`). `POST /trips/:id/accept-bid` (`trips.ts:1262-1371`) reads the chosen bid, then
sets `accepted_price = final_fare = bid.counter_price` and recomputes
`commission = acceptedPrice * commissionRate` (`:1299-1310`), again via a conditional UPDATE
with a `changes === 0` guard (`:1312-1314`). Losing bids are marked `rejected` (`:1318`).

**Settle.** `POST /trips/:id/complete` (`trips.ts:951-1088`):

```ts
const finalFare = trip.accepted_price ?? trip.final_fare ?? trip.estimated_fare ?? 0;  // :969
const commission = trip.commission ?? 0;                                                // :970
const captainPayout = Math.max(0, round2(finalFare - commission));                      // :971
```

`offered_price` **is not in that chain.** Cash debits the commission from the captain's wallet
(`:1012-1035`); non-cash credits the payout (`:1036-1054`); wallet additionally debits the rider
(`:993-1011`). All three are idempotency-keyed (`idx_wt_idem`).

### 3.4 The two prices a trip can have

This is the heart of the axis, so it is worth stating as a table. For a trip whose
server-computed estimate is 61.00 EGP and whose rider offered 150.00 EGP:

| Path | `offered_price` | `accepted_price` | Settled `finalFare` | What the captain was shown |
|---|---|---|---|---|
| Direct `/accept` | 150.00 | `NULL` | **61.00** (`estimated_fare`) | **150.00** (`offer_card.dart:239`) |
| Bid → `/accept-bid` | 150.00 | bid price | bid price | bid price |

The rider's offer — the product's entire differentiator — only becomes real money if a captain
goes through the counter-offer flow. A captain who taps "Accept" on the number in front of them
is paid a different, lower number, and nothing anywhere tells them so.

### 3.5 Manipulation matrix

Every client-supplied field that can influence money, at the pinned commit.

| # | Field | Endpoint | Attack | Server stops it today? | Fix |
|---|---|---|---|---|---|
| M1 | `offeredPrice` | `POST /trips` | Offer 1 EGP for a 40 km trip; spray the captain pool with unservable jobs | **Partially** — `z.number().min(1).max(10000)` (`schemas.ts:59`) and nothing else. No relation to the estimate | P0.2 offer band + P0.1 signed quote |
| M2 | `offeredPrice` | `POST /trips` | Offer 10,000 EGP to look attractive, knowing settlement ignores it (§3.4) | **No** — and the divergence is the bug (F-05-01) | P0.1 signed quote; make `offered_price` the settled price on direct accept |
| M3 | `counterPrice` | `POST /trips/:id/bid` | Counter at 10,000 EGP on a 20 EGP trip; one rider mis-tap settles it | **Partially** — `min(1).max(10000)` (`schemas.ts:77`), no relation to the estimate | P0.2 counter band anchored to the estimate |
| M4 | `counterPrice` | `POST /trips/:id/bid` | Re-bid in a loop to dominate the rider's list | **No** — no dedup, no rate limit, no expiry (F-05-08) | P0.3 one live bid per captain + TTL + rate limit |
| M5 | `promoCode` | `POST /trips` | Reuse one code on unlimited trips from one account | **No** — no per-user cap is even expressible in the schema (F-05-16) | P1.2 `promo_redemptions` table |
| M6 | `promoCode` | `POST /trips` | Fire N concurrent creates to blow past `max_uses` | **No** — read at `:418`, increment at `:500`, no guard (F-05-05) | P0.5 conditional atomic UPDATE |
| M7 | `promoCode` | `POST /trips` + `/cancel` | Create+cancel loop to burn the whole promo budget for free | **No** — no decrement, no cancellation fee (F-05-06, F-05-11) | P0.5 redeem-on-complete + P0.6 cancellation policy |
| M8 | `vehicleTypeId` | `POST /trips` | Request `xl`, pay `economy` — the multiplier is never applied | **No** — free-text, unvalidated, never priced (F-05-10) | P0.4 server-side multiplier + FK |
| M9 | `city` | `POST /trips`, `/estimate` | Send `alex` for a Cairo trip to buy the cheaper tariff (11/4.2/0.45 vs 12/4.5/0.5) | **No** — free text, never checked against the coordinates (F-05-19) | Derive city from pickup coordinates server-side |
| M10 | `pickupLat/Lng`, `dropoffLat/Lng` | `POST /trips` | Book a short route, redirect the captain in person, pay the short fare | **No** — the frozen estimate is never reconciled against the driven path | P2.3 post-trip reconciliation |
| M11 | `paymentMethod` | `POST /trips` | Choose `wallet` with an empty balance — the trip still completes | **No** — debit failure is recorded as `failed` and the trip completes anyway (F-05-21) | P0.7 block completion or create a receivable |
| M12 | `bidId` | `POST /trips/:id/accept-bid` | Accept a bid belonging to another trip | **Yes** — `WHERE id = ? AND trip_id = ?` (`trips.ts:1283`) | none needed |
| M13 | trip assignment | `/accept` vs `/accept-bid` | Two captains accept the same instant | **Yes** — conditional UPDATE + `changes === 0` on both paths (`:861-870`, `:1305-1314`) | none needed |

M12 and M13 are the two places this codebase already gets right, and they are worth saying out
loud: the assignment race is properly serialised by D1's single-writer semantics, and the loser
gets a clean `409 TRIP_TAKEN` / `TRIP_CONFLICT`.

---

## 4. Findings

Severity: **S1** blocker (money can be lost or stolen, or the platform cannot go live with it) ·
**S2** major · **S3** moderate · **S4** polish.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-05-01 | S1 | The rider's `offeredPrice` never reaches settlement on the direct-accept path; the captain is shown a price they will not be paid | `apps/api/src/routes/trips.ts:438,466`, `:861-866`, `:969`; `apps/api/src/routes/captain.ts:462-467`; `apps/captain/lib/screens/home/offer_card.dart:239-243` | Captain accepts 150 EGP and is paid on 61 EGP. Silent, systematic, every direct accept | confirmed |
| F-05-02 | S1 | Rider offer has absolute bounds only — no relation to the estimate | `apps/api/src/lib/schemas.ts:59` | 1 EGP for 40 km is accepted and fanned out to 10 captains; economic DoS on captain attention | confirmed |
| F-05-03 | S1 | Captain counter-offer has absolute bounds only, and the counter **is** the settled price | `apps/api/src/lib/schemas.ts:77`; `apps/api/src/routes/trips.ts:1299-1309`, `:969` | A 10,000 EGP counter on a 20 EGP trip is one rider mis-tap from a wallet debit | confirmed |
| F-05-04 | S1 | Accepting a bid silently voids the rider's promo discount | `apps/api/src/routes/trips.ts:428-429` vs `:1299-1310`, `:969` | Rider is charged the undiscounted bid price; the promo use was already burned | confirmed |
| F-05-05 | S1 | `promo_codes.uses_count` is read then incremented with no atomic guard | `apps/api/src/routes/trips.ts:418` and `:500` | Concurrent redemptions blow through `max_uses`; unbounded marketing spend | confirmed |
| F-05-06 | S1 | Promo uses are never released on cancellation, and cancelling is free | `apps/api/src/routes/trips.ts:493-504`, `:709-827` | One scripted account drains an entire campaign budget at zero cost | confirmed |
| F-05-07 | S1 | The promo discount is funded ~85% by the captain, not the platform | `apps/api/src/routes/trips.ts:428-429`, `:969-971` | On a 100 EGP fare with a 20% promo the captain loses 17 EGP, the platform 3 | confirmed |
| F-05-08 | S1 | Unlimited bid spam: no dedup, no rate limit, no expiry on `trip_bids` | `apps/api/src/routes/trips.ts:1144-1175`; `migrations/0004_bidding_system.sql:3-13` | One captain can flood the rider's chooser; stale bids never lapse | confirmed |
| F-05-09 | S1 | OSRM failure silently reprices the trip ~+28% with no log, metric or signal | `apps/api/src/lib/routing.ts:61-62`, `:66-82` | Every rider is overcharged during an OSRM outage and nobody is paged | confirmed |
| F-05-10 | S1 | The vehicle-class multiplier is never applied server-side — XL is priced as economy | `migrations/0002_enhancements.sql:83-93`; `apps/api/src/lib/routing.ts:164-173`; `apps/api/src/routes/trips.ts:393,471,969` | Every premium-tier trip is sold at the economy price; direct revenue loss | confirmed |
| F-05-11 | S1 | No cancellation or no-show fee exists; the admin settings for it are dead | `migrations/0016_system_config.sql:36`; `apps/api/src/routes/admin.ts:426-434` vs `apps/api/src/routes/trips.ts:709-827` | Captains eat every wasted pickup drive; operator believes a policy is live | confirmed |
| F-05-12 | S1 | A wallet trip completes even when the rider's debit fails | `apps/api/src/routes/trips.ts:997-1010` | Trip settles, captain is credited, rider rides free with no receivable | confirmed |
| F-05-13 | S2 | Surge is dead code — it reads a column that does not exist on `pricing_rules` | `apps/api/src/routes/trips.ts:390-392`; `migrations/0001_init.sql:46-56`; `apps/api/src/lib/types.ts:93-102` | Surge is permanently 1.0; no demand response is possible | confirmed |
| F-05-14 | S2 | `/estimate` omits the surge that create applies | `apps/api/src/routes/trips.ts:315-344` vs `:387-397` | The moment surge is wired up, quoted ≠ charged with no code change | confirmed |
| F-05-15 | S2 | `/estimate` is unauthenticated and returns nearby captain coordinates | `apps/api/src/routes/trips.ts:315-346`, `:336-342` | Free fare oracle and a live captain-position feed for anyone with curl | confirmed |
| F-05-16 | S2 | Per-user promo caps are not expressible in the current schema | `migrations/0002_enhancements.sql:54-70` | `trip_promo` is keyed per trip; no `(user, code)` uniqueness exists | confirmed |
| F-05-17 | S2 | Bids from unapproved captains reach the rider's chooser | `apps/api/src/routes/trips.ts:1144-1167` and `:1236-1248` vs `:1291-1297` | Rider picks a captain, then gets a 409; approval is only checked at accept | confirmed |
| F-05-18 | S2 | Any online captain may bid on any open trip regardless of distance or dispatch | `apps/api/src/routes/trips.ts:1157-1167` | A captain 40 km away outside every radius filter can still bid | confirmed |
| F-05-19 | S2 | Client-supplied `city` selects the pricing table, unvalidated against coordinates | `apps/api/src/routes/trips.ts:322,378`, `:24-32`; `migrations/0001_init.sql:117-133` | Tariff arbitrage (alex is ~7% cheaper) and corrupted per-city revenue data | confirmed |
| F-05-20 | S2 | Money is float throughout the fare engine; the bidding columns were never migrated to piastres | `packages/shared/src/index.ts:17-38`; `migrations/0004_bidding_system.sql:7,16,17` vs `migrations/0005_integer_currency_and_idempotency.sql:9-11` | The negotiated price — the one that actually settles — is the one still on `REAL` | confirmed |
| F-05-21 | S2 | The captain decides on a gross fare; commission is never disclosed at decision time | `apps/captain/lib/screens/home/offer_card.dart:239-243,414-429` | Captains cannot compute their own take before accepting | confirmed |
| F-05-22 | S2 | `minFare` is enforced before the discount, so a promo can push a fare under the floor | `packages/shared/src/index.ts:104-105`; `packages/shared/src/index.test.ts:41-49` | The advertised city minimum is not actually a minimum | confirmed |
| F-05-23 | S2 | Intercity bookings appear to bypass commission accounting entirely | `apps/api/src/routes/intercity.ts:99-102`; `migrations/0003_global_transport.sql:94-106` | No `commission` column, no `commission_rate` read; intercity may book zero platform revenue | confirmed |
| F-05-24 | S2 | The rider sees no bid expiry while the captain sees a 15-second countdown | `apps/captain/lib/screens/home/offer_card.dart:69,964-1006` vs `apps/rider/lib/screens/ride/captain_bids_sheet.dart` (absent) | Bids vanish from the rider's list with no explanation | confirmed |
| F-05-25 | S2 | The default OSRM endpoint is the free public demo server | `apps/api/src/lib/routing.ts:15`; `apps/api/src/routes/trips.ts:176-178` | Every fare depends on an unmetered shared host with no SLA | confirmed (default), needs-check (prod override) |
| F-05-26 | S3 | Waiting time, tolls, night rate and airport surcharge do not exist | exhaustive search, zero hits in schema and code | No cost pass-through; captains absorb every delay | confirmed |
| F-05-27 | S3 | Surge granularity would be per-city with no time window even if it worked | `migrations/0001_init.sql:47`; `apps/api/src/routes/trips.ts:24-32` | Blast radius is an entire metro area with no expiry | confirmed |
| F-05-28 | S3 | `estimateTripFare` is dead code; the 1.35 road factor is hardcoded three times | `apps/api/src/lib/pricing.ts:23-34`, `:30`; `apps/api/src/lib/routing.ts:71,160` | Two fare implementations, one live; drift risk | confirmed |
| F-05-29 | S3 | The vehicle multiplier table is duplicated in three places with no shared constant | `apps/rider/.../fare_estimate_sheet.dart:53-57`; `apps/rider/.../vehicle_selector.dart:291-313`; `apps/admin/src/pages/PricingPage.tsx:186-211` | Three copies must be edited in lockstep by convention alone | confirmed |
| F-05-30 | S3 | The counter-offer sheet can emit 2-decimal prices nothing else displays | `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart:65,210-211` | 47.33 EGP enters a system that renders whole EGP everywhere | confirmed |
| F-05-31 | S3 | The rider's bid list has no sort — bids render in arrival order | `apps/rider/lib/screens/ride/captain_bids_sheet.dart:105,282-303` | The cheapest offer is not surfaced in a price-negotiation UI | confirmed |
| F-05-32 | S3 | The counter-offer field is pre-seeded at rider offer + 10 EGP regardless of fare size | `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart:53-55` | +67% anchor on a 15 EGP trip, +5% on a 200 EGP trip | confirmed |
| F-05-33 | S4 | `currency` accepts any 3-character string | `apps/api/src/lib/schemas.ts:223` | An admin can set a city's currency to `XXX` | confirmed |
| F-05-34 | S4 | "offer", "bid" and "counter" are used interchangeably for one primitive | `apps/rider/.../fare_estimate_sheet.dart:663`; `apps/captain/.../offer_card.dart:398,688`; `packages/flutter_shared/.../counter_offer_sheet.dart:15` | Reader and user confusion across both apps | confirmed |
| F-05-35 | S4 | A failed audit write on a pricing change is swallowed | `apps/api/src/lib/audit.ts:33-35`; `apps/api/src/routes/admin.ts:402-409` | A tariff change can land with no trail | confirmed |

Positive findings, recorded so nobody re-raises them: the assignment race is correctly
serialised on both paths (`trips.ts:861-870`, `:1305-1314`); wallet moves are idempotency-keyed
against `idx_wt_idem` (`trips.ts:994`, `:1019`, `:1039`); `pricingUpdateSchema` genuinely bounds
`commissionRate` to `0..1` (`schemas.ts:229`), contrary to what the brief anticipated; pricing
updates are audited (`admin.ts:402-409`); intercity per-seat price is fully server-authoritative
and cannot be client-supplied (`intercity.ts:99-102`); and both route fetches carry real
timeouts (`routing.ts:32-33`, `:111`).

### F-05-01 — The rider's offer never becomes money (S1)

This is the most important finding in the document, because it breaks the product's
differentiator quietly rather than loudly.

At creation the rider's number is stored: `offered_price = body.offeredPrice || finalEstimate`
(`trips.ts:438`, bound at `:466`). `GET /captain/offers` hands the captain a raw
`SELECT * FROM trips` row (`captain.ts:462-467`), and the offer card reads `offered_price`
first (`offer_card.dart:239-243`). So the captain's accept button says the rider's number.

`POST /trips/:id/accept` (`trips.ts:861-866`) writes `status`, `captain_id`, `assigned_at`,
`captain_lat`, `captain_lng`, `updated_at`. **No price column.** `accepted_price` stays `NULL`
and `final_fare` was never set at creation.

Settlement then resolves `trip.accepted_price ?? trip.final_fare ?? trip.estimated_fare`
(`trips.ts:969`) — and lands on `estimated_fare`, the server's own number. `offered_price`
appears nowhere in that chain.

Worked example, using the seeded Cairo tariff for an 8 km / 20 min trip (estimate 61.00 EGP):

| | Rider offers 150 | Rider offers 30 |
|---|---|---|
| Shown on the captain's accept button | 150.00 | 30.00 |
| `accepted_price` after `/accept` | `NULL` | `NULL` |
| Settled `finalFare` (`:969`) | **61.00** | **61.00** |
| Captain payout (`:971`, 20% commission) | 48.80 | 48.80 |
| Captain's expectation gap | **−89.00 EGP** | +31.00 EGP |

Both directions are wrong. A captain who accepts a generous offer is underpaid by 89 EGP with
no explanation; a rider who lowballs at 30 EGP is charged 61 EGP after seeing their own offer
accepted. The completion push tells the rider "الأجرة 61 ج.م" (`:1068`) — the first moment
either party learns the negotiated number was decorative.

The bid path is internally consistent (`accepted_price` is set at `:1306` and settles at `:969`),
which is precisely why this is easy to miss: the flow the team tests works, and the flow a
captain uses when they simply agree with the price does not.

### F-05-02 / F-05-03 — Offers and counters have no relation to the estimate (S1)

`offeredPrice: z.number().min(1).max(10000).optional()` (`schemas.ts:59`) and
`counterPrice: z.number().min(1).max(10000)` (`schemas.ts:77`) are the only server-side bounds
that exist. Neither references the trip's own estimate.

Answering the brief's question 3 directly: **yes, a rider can offer 1 EGP for a 40 km trip**,
and the server will accept it, create the trip, and push an FCM notification to ten captains
(`trips.ts:574-585`). **Yes, a captain can counter at 10,000 EGP** — and unlike the rider's
offer, the counter is real money: `accepted_price = final_fare = counter_price`
(`trips.ts:1306-1309`), settled verbatim at `:969`, debited from a wallet rider's balance at
`:997-1001`.

The Flutter clients do clamp — `[1, 10000]` on the rider stepper and typed field
(`fare_estimate_sheet.dart:110-111`, `:129-136`) and the same range on the captain counter
(`counter_offer_sheet.dart:64-70`) — but these are the *same* absolute bounds, mirrored
deliberately (the code comments say so). There is no relative band anywhere, on either side, in
either layer. The rider app's own comment states this is intentional:
"the rider is deliberately not clamped to a band around the suggestion… the market, not the
pricing table, settles the final figure" (`fare_estimate_sheet.dart:604-611`). That is a
defensible product stance for the *rider's* offer; it is not defensible for the *captain's*
counter, which settles automatically on one tap.

Caveat: the exact JSON bodies are assembled in `AppState` / `CaptainState`, which I did not
read. The field names above come from the Dart call sites and the schemas they validate
against, which agree.

### F-05-04 — Accepting a bid voids the promo discount (S1)

At creation, a promo produces `discount`, `finalEstimate = total - discount` and
`commission = finalEstimate * rate` (`trips.ts:421-429`), and `uses_count` is incremented
immediately (`:499-503`).

`accept-bid` then overwrites the money columns wholesale:

```ts
const acceptedPrice = selectedBid.counter_price;              // trips.ts:1299
const commission = round2(acceptedPrice * commissionRate);    // trips.ts:1302
UPDATE trips SET accepted_price = ?, final_fare = ?, commission = ? ...   // :1306-1309
```

`discount` is not consulted. Settlement takes `accepted_price` (`:969`). The rider booked with
a promo, saw a discounted estimate, had the promo consumed against the campaign budget — and
pays the full negotiated price. The `trips.discount` column still holds the number, so the data
says a discount was granted while the ledger says it was not.

Promotions and the bidding flow are, as shipped, mutually exclusive. Any campaign run before
this is fixed will generate support tickets from riders who can see the discount they did not
receive.

### F-05-05 / F-05-06 — The promo budget has no floor (S1)

Two independent holes in the same surface.

*The race.* `uses_count < max_uses` is evaluated at `trips.ts:418`; the increment is a bare
`UPDATE promo_codes SET uses_count = uses_count + 1 WHERE code = ?` at `:500`, roughly eighty
lines of I/O later. There is no conditional predicate on the write and no transaction. N
concurrent creates all read the same stale count and all succeed. With `max_uses = 100` and 150
simultaneous requests, 150 discounts are granted.

*The drain.* Cancellation (`trips.ts:709-827`) never decrements `uses_count` and never touches
`trip_promo`. Combined with F-05-11 (cancelling is free), the loop is: create with promo →
`uses_count++` → cancel → repeat. Each iteration permanently consumes campaign budget for a
trip that never happened, at zero cost and zero risk to the caller. A single scripted account
can exhaust a 500-use campaign in under a minute.

The fix for both is the same shape: redeem at completion, not creation, and make the increment
conditional (`UPDATE ... WHERE code = ? AND (max_uses IS NULL OR uses_count < max_uses)`,
checking `changes`).

### F-05-07 — The captain funds the discount (S1)

Commission is computed on the *post*-discount amount (`trips.ts:429`), stored, and read back
unchanged at settlement (`:970`), where the payout is `finalFare - commission` (`:971`). The
payout formula has no term that restores what the promo removed.

100 EGP fare, 20% promo, 20% commission (the seeded Cairo rate, `0001_init.sql:120`):

| | No promo | With 20% promo | Delta |
|---|---|---|---|
| Fare charged to rider | 100.00 | 80.00 | −20.00 |
| Platform commission | 20.00 | 16.00 | **−4.00** |
| Captain payout | 80.00 | 64.00 | **−16.00** |

The platform gives up 4 EGP of a 20 EGP discount; the captain gives up 16. The captain never
consented to the campaign, is never told a promo was applied (the completion push at `:1081`
reports only the payout), and cannot detect it from the app. In a market where captains compare
per-trip earnings across apps daily, a marketing campaign that quietly cuts driver earnings by
16% is a supply-side event, not a growth one.

### F-05-08 — Bid spam is unbounded (S1)

`POST /trips/:id/bid` (`trips.ts:1144-1209`) checks trip status (`:1157`) and the captain's
online flag (`:1165`), then inserts (`:1170-1175`). It does not check for an existing pending
bid from the same captain, carries no `rateLimit` middleware (compare `trips.ts:317` and `:351`,
where the authors did apply it), and `trip_bids` has no expiry column at all
(`0004_bidding_system.sql:3-10`: `id`, `trip_id`, `captain_id`, `counter_price`, `status`,
`created_at`).

Answering the brief's question 5: there is **no round limit, nothing expires a bid, and nothing
stops a captain from re-bidding endlessly**. `GET /trips/:id/bids` returns every `pending` row
ordered by `created_at DESC` (`:1236-1248`), so a captain looping the endpoint owns the top of
the rider's chooser. The rider's sheet re-polls every 5 seconds and renders the list unsorted
(`captain_bids_sheet.dart:105`), so the spam is displayed faithfully.

### F-05-09 — OSRM failure silently reprices every trip (S1)

The `catch` at `routing.ts:61-62` binds no error and logs nothing. This is conspicuous because
the same codebase logs comparable degradations elsewhere (`trips.ts:68`, `:762`, `:789`).

The fallback multiplies straight-line distance by 1.35 and assumes 22 km/h. For an 8 km
straight-line Cairo trip on the seeded tariff (`base 12`, `per_km 4.5`, `per_min 0.5`,
`booking 3`, `min 25`):

| | OSRM path (8 km / 20 min) | Haversine fallback |
|---|---|---|
| Distance used | 8.00 km | 10.80 km (`8 × 1.35`) |
| Duration used | 20 min | 29 min (`10.80 / 22 × 60`) |
| Distance fare | 36.00 | 48.60 |
| Time fare | 10.00 | 14.50 |
| Base + booking | 15.00 | 15.00 |
| **Total** | **61.00 EGP** | **78.10 EGP** |
| Commission (20%) | 12.20 | 15.62 |

**+17.10 EGP, +28.0%.** That is the *floor*, not the ceiling: it assumes the true road route
has no detour at all. In Cairo — river crossings, one-way grids, ring-road funnelling — real
road/straight-line ratios routinely exceed 1.35, and the fallback's error grows with them.

Nothing branches on `route.source` (`routing.ts:12,60,81`). The field is returned in the API
response and written to `trip_events` as `routeSource` (`trips.ts:342,511,597`), but no code
path treats it as a control signal, no metric counts it, and no alert fires. A multi-hour OSRM
outage would present as a quiet 28% revenue uplift and a wave of rider complaints, with nothing
in the logs connecting the two.

Compounding it: the default endpoint is `https://router.project-osrm.org`
(`routing.ts:15`), OSRM's public demo host, which rate-limits and offers no SLA. Whether
production overrides `OSRM_URL` is `needs-check` — `wrangler.toml` was out of scope.

### F-05-10 — Vehicle classes are priced identically (S1)

`vehicle_types` carries a real multiplier column, seeded `economy 1.0`, `comfort 1.25`,
`xl 1.5` (`0002_enhancements.sql:83-93`). `calculateFare` implements `vehicleMultiplier`
correctly (`shared/index.ts:95,98-100`).

They are never connected. `fareFromRoute` calls `calculateFare(distanceKm, durationMin, rule)`
with no options object (`routing.ts:164-173`), and that is the only fare path both endpoints use
(`trips.ts:340,393`). `body.vehicleTypeId` is validated as `z.string().max(40).optional()`
(`schemas.ts:62`) — no existence check against the table — and stored as a label (`trips.ts:471`).
Settlement never joins back to `vehicle_types` (`trips.ts:969`, `:1299-1302`).

So a rider who selects XL is charged the economy fare. Worse, the rider *app* multiplies the
displayed price by 1.6 locally (`vehicle_selector.dart:322-337`,
`fare_estimate_sheet.dart:53-57` — and note both the values and the tiers disagree with the
server's seed: the apps use 1.0/1.3/1.6, the database says 1.0/1.25/1.5). The rider sees an
inflated XL price, the server charges the economy fare, and if the rider's client-side number
became their `offeredPrice`, F-05-01 then discards it anyway.

Every premium-tier trip sold today is sold at the base price. This is pure, silent revenue loss
on the highest-margin product line.

### F-05-12 — A failed wallet debit still completes the trip (S1)

The rider debit is conditional on sufficient balance
(`UPDATE ... WHERE id = ? AND wallet_balance >= ?`, `trips.ts:997-1001`). If it matches nothing,
the code records `txnStatus = 'failed'` (`:1003`) and inserts a `failed` transaction row
(`:1005-1010`) — and then **continues**. The trip was already marked `completed` at `:973-977`,
and the captain is credited their payout at `:1040-1052` regardless.

The rider gets the ride, the captain gets paid, and the platform absorbs the fare with a `failed`
row as the only record. There is no receivable, no negative balance, no retry and no block on
booking again. Wallet is a first-class `paymentMethod` in the schema (`schemas.ts:60`), so this
is reachable today.

This straddles T03's ledger axis — flagged there in §9 — but it belongs here too because it
determines the final settled amount.

### F-05-13 / F-05-14 — Surge does not exist, and will diverge when it does (S2)

`trips.ts:390-392` casts the `pricing_rules` row to `DbPricing & { surge_multiplier?: number }`
and reads the field. `pricing_rules` has nine columns and none of them is `surge_multiplier`
(`0001_init.sql:46-56`); `DbPricing` agrees (`types.ts:93-102`). The read is always `undefined`,
so `surgeMultiplier` is always `1.0` and the branch at `:395` never fires. The comment above it
describes parsing `"surge:1.5"` out of a comment field — a mechanism that does not exist
anywhere in the repo.

The only real surge column is `trips.surge_multiplier` (`0003_global_transport.sql:54`), written
once per trip with the constant `1.0` (`trips.ts:476`). No admin endpoint writes surge
(`admin.ts:333-415` covers six fields, none of them surge) and the admin console has no surge
control (`PricingPage.tsx`, 760 lines, no surge field). Answering the brief's question 6: surge
is **dormant**, not manual and not computed. Nothing in the codebase reads demand, supply, or a
heatmap.

The trap is F-05-14. `/estimate` (`trips.ts:315-344`) has no surge logic at all, while create
(`:387-397`) does. Today both produce the same number because surge is always 1.0. The day
someone adds the column and populates it, `/estimate` keeps quoting un-surged fares while
`POST /trips` charges the multiple — quoted ≠ charged, with no code change to either endpoint
and no test that would catch it. Fixing surge without fixing the estimate path is the wrong
order of operations, and P1.1 below sequences them together.

### F-05-15 — The estimate endpoint is public (S2)

`tripRoutes.post("/estimate", ...)` is registered at `trips.ts:315`;
`tripRoutes.use("*", authMiddleware)` at `:346`. Hono composes matched handlers in registration
order, so a handler registered before the middleware returns its response without the middleware
running. `/trips/estimate` therefore requires no token.

It is IP-rate-limited to 30/min (`:317`, default key `cf-connecting-ip` at
`middleware/rateLimit.ts:19-20`), which bounds the abuse but does not remove it. Two
consequences: the complete tariff for every city is enumerable by anyone (a competitor can map
the pricing surface in a few hundred requests), and the response embeds `nearbyCaptains` with
coordinates (`:336-342`) — an unauthenticated live feed of captain positions. The location
disclosure is more T02/T25's problem than mine and is handed off in §9; the fare-oracle aspect
is mine, and it is the reason the signed-quote design in P0.1 must bind a quote to a user.

### F-05-17 / F-05-18 — The bid endpoint trusts too much (S2)

`/bid` checks the trip's status and the captain's online flag. It does **not** check
`approval_status` — that check exists only in `accept-bid` (`trips.ts:1291-1297`) and in direct
`/accept` (`:837`). `GET /trips/:id/bids` joins `captains` for display fields but does not filter
on approval (`:1236-1248`). So an unapproved captain can bid, appear in the rider's chooser with
name, photo, vehicle and rating, and the rider only discovers the problem as a
`CAPTAIN_NOT_APPROVED` 409 after choosing them.

`/bid` also performs no distance or dispatch-membership check. The captain need not be in the
9-cell neighbourhood, need not be within their own configured radius, and need not have been
offered the trip at all — the dispatch filtering that `POST /trips` carefully applies
(`trips.ts:518-531`) is simply bypassed by calling `/bid` directly with a trip id. Trip ids are
discoverable by any online captain in the city through `GET /captain/offers`
(`captain.ts:462-467`), which returns up to 20 open trips before radius scoping is applied in
application code (`:483-491`).

### F-05-19 — The client picks its own tariff (S2)

`const city = body.city || c.env.DEFAULT_CITY || "cairo"` (`trips.ts:322` for estimate, `:378`
for create), and `getPricing` looks the tariff up by that string (`:24-32`). `createTripSchema`
constrains `city` to `z.string().max(60).optional()` (`schemas.ts:58`) — no enum, no check
against the pickup coordinates.

The seeded tariffs differ (`0001_init.sql:117-133`): Cairo and Giza are
`12 / 4.5 / 0.5 / 3 / min 25`, Alexandria is `11 / 4.2 / 0.45 / 3 / min 22`. Sending
`city: "alex"` for the 8 km Cairo trip yields `11 + 33.6 + 9 + 3 = 56.60` against Cairo's
`61.00` — a 4.40 EGP (7.2%) saving that scales with distance.

Honest qualification: this is partly self-defeating today, because `city` also scopes dispatch —
`GET /captain/offers` filters trips by the captain's own city (`captain.ts:457-467`), so a Cairo
trip labelled `alex` would only be visible to Alexandria captains and would likely never be
served. That makes it a weak fare-arbitrage vector in isolation but a genuine one in collusion
(a captain and rider coordinating), and unconditionally a data-integrity problem: per-city
revenue, demand and supply reporting are all computed off a field the client controls.

### F-05-20 — The negotiated price is the one still on floats (S2)

Migration 0005 added integer piastres columns for `estimated_fare`, `final_fare`, `commission`
and `wallet_balance` (`0005:9-12`) with an explicit rationale: "zero-floating-point financial
accounting."

Migration 0004, which created the bidding system, declared `trip_bids.counter_price REAL`,
`trips.offered_price REAL` and `trips.accepted_price REAL` (`0004:7,16,17`). Migration 0005 did
not touch any of them. So the hardening was applied to the columns the non-bidding path uses,
and skipped the three columns the product's actual pricing model uses — including
`accepted_price`, which is first in the settlement chain at `:969`. `calculateFare` itself
remains float throughout (`shared/index.ts:17-38`), converting to piastres only at the wallet
boundary (`trips.ts:995`, `:1017`, `:1038`).

### F-05-21 / F-05-24 — What each side is allowed to know (S2)

The captain's offer card renders the fare and nothing else (`offer_card.dart:239-243`,
`:414-429`): no commission, no net earnings, no indication of whether a promo has reduced the
fare (which, per F-05-07, comes mostly out of their pocket). They are asked to commit to a job
on a gross number. The commission only appears afterwards, in the completion push
(`trips.ts:1080`).

Symmetrically, the rider is shown a single total with no breakdown — `fare_estimate_sheet.dart`
reads only `fare.total` (`:97`) and never unpacks base, per-km, per-minute, surge or discount —
and no bid expiry. The captain's side treats time pressure as a first-class animated element
(a 15 s countdown ring, `offer_card.dart:69`, `:964-1006`) while the rider's chooser has no
countdown at all; a bid simply disappears between 5-second polls with no explanation
(`captain_bids_sheet.dart`).

### Price lock (brief question 7)

Worth stating explicitly since it is a rare piece of good news. Once `accepted_price` is set at
`trips.ts:1306`, nothing can change it: no endpoint accepts a fare adjustment, `/complete` takes
no body and recomputes nothing (`:969-971`), and the status-advance helper touches only
timestamps (`:913-917`). The price is genuinely immutable after agreement.

The flip side is that **nothing can legitimately change it either**. Waiting time, a route
change, an added stop, tolls and night rates are all absent from the schema and the code
(F-05-26). `trips.waypoints` is stored at creation (`:475`) and never priced. A captain who
waits 25 minutes or takes a toll road absorbs the cost personally.

---

## 5. Benchmark gap

Competitor mechanisms below are marked **confident** where they are publicly documented or
directly observable in the products, **assumed** where they are informed inference.

| Axis | inDrive | Uber | Careem | Synaptic Go today |
|---|---|---|---|---|
| Price origin | Rider offers, anchored to a recommended price (**confident**) | Server-issued upfront quote, signed and echoed back at request (**confident**) | Server quote with fare lock (**confident**) | Rider offers with no anchor enforced; the offer is then **discarded** on direct accept (F-05-01) |
| Offer bounds | Offer bounded around the recommendation; extreme lowballs rejected client- and server-side (**confident**) | N/A — no rider offer | N/A | `1..10000` absolute, no relation to the estimate (F-05-02) |
| Counter bounds | Limited counter rounds, bounded increments (**confident**) | N/A | N/A | `1..10000`, unlimited rounds, no expiry (F-05-03, F-05-08) |
| Quote integrity | Quote tied to a session (**assumed**) | Signed quote token; tampering rejected (**confident**) | Fare lock on the quote id (**confident**) | None — every price input is re-derived from client-supplied fields (M1–M11) |
| Surge | No surge; transparent demand hints instead (**confident**) | Multiplier with explicit rider confirmation, per-cell and time-boxed (**confident**) | Peak pricing with disclosure (**confident**) | Dead code; permanently 1.0 (F-05-13) |
| Vehicle tiers | Tier affects the recommendation (**confident**) | Tier is a distinct product with its own rate card (**confident**) | Same (**confident**) | Tier is a label; all tiers cost the same (F-05-10) |
| Waiting / tolls / night | Driver-negotiated, so folded into the offer (**confident**) | Explicit line items on the receipt (**confident**) | Explicit line items (**confident**) | Absent (F-05-26) |
| Cancellation | Fee after a grace window (**assumed**) | Fee after grace, with no-show charge (**confident**) | Fee after grace (**confident**) | None; the config exists and is dead (F-05-11) |
| Promo funding | Platform-funded (**assumed**) | Platform-funded; driver is paid on the gross fare (**confident**) | Platform-funded (**assumed**) | ~80% captain-funded (F-05-07) |
| Route basis | Road routing (**confident**) | Road routing with traffic (**confident**) | Road routing (**confident**) | OSRM, silently degrading to haversine × 1.35 at +28% (F-05-09) |

The honest summary: Synaptic Go has implemented the *shape* of the inDrive model — an offer
field, a bid table, a counter-offer sheet — without the three mechanisms that make that model
safe. inDrive's negotiation works because the recommended price is an enforced anchor, counters
are bounded and finite, and the agreed number is the number that settles. Synaptic Go currently
has none of those three. Against Uber the gap is narrower in ambition but wider in integrity:
Uber's entire upfront-pricing model rests on a signed quote the client cannot alter, which is
exactly the primitive missing here.

---

## 6. Improvement plan

### P0.1 — Signed fare quotes

- **Goal.** The price a trip is created with is a price the server issued, for these
  coordinates, for this user, recently — not a number reconstructed from client fields.
- **Design.** `POST /trips/estimate` returns a `quote` object plus a `quoteToken`: an HMAC
  (`SHA-256`, key from a new `QUOTE_SIGNING_KEY` secret) over a compact payload of
  `{quoteId, userId, city, pickupLat, pickupLng, dropoffLat, dropoffLng, vehicleTypeId, distanceKm, durationMin, surgeMultiplier, total, routeSource, issuedAt, expiresAt}`.
  TTL 10 minutes. `POST /trips` requires `quoteToken`, verifies the HMAC, rejects on expiry
  (`QUOTE_EXPIRED`), on `userId` mismatch (`QUOTE_NOT_YOURS`), and on coordinates drifting more
  than 100 m from the signed ones (`QUOTE_COORDS_MISMATCH`). The server then prices the trip
  **from the signed payload**, not from the request body — `city`, `vehicleTypeId`, `distanceKm`,
  `surgeMultiplier` are all read from the token. This closes M1, M2, M8, M9, M10 in one change.
  Requires making `/estimate` authenticated (see P0.8) so the token can be bound to a user.
- **Files to change.** `apps/api/src/lib/quote.ts` (new), `apps/api/src/routes/trips.ts`
  (`/estimate` 315-344, create 348-604), `apps/api/src/lib/schemas.ts` (add `quoteToken`),
  `apps/rider/lib/screens/home/fare_estimate_sheet.dart` (carry the token through to create).
- **DB.** `0020_fare_quotes.sql` — optional but recommended replay guard:
  `CREATE TABLE fare_quotes (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, payload TEXT NOT NULL, consumed_at TEXT, expires_at TEXT NOT NULL);`
  plus `CREATE INDEX idx_fq_user ON fare_quotes(user_id, expires_at);`
- **API contract.** `/estimate` response gains `{ quoteId, quoteToken, expiresAt }`.
  `POST /trips` request gains required `quoteToken: string`. New errors:
  `QUOTE_EXPIRED`, `QUOTE_INVALID`, `QUOTE_NOT_YOURS`, `QUOTE_COORDS_MISMATCH` (all 400 except
  the last, 409).
- **Effort.** M (2–3 days including the Flutter change).
- **Risk.** Old app builds without the token break trip creation. Mitigate with a two-phase
  rollout: accept a missing token behind a `REQUIRE_SIGNED_QUOTE` flag, log unsigned creates,
  flip the flag once telemetry shows the old builds are drained. Rollback is the flag.
- **Acceptance criteria.** A create with a tampered `total` is rejected. A create with another
  user's token is rejected. A create with a token older than 10 minutes is rejected. A create
  whose `city` differs from the signed one is priced on the signed city. Unsigned creates are
  zero in production telemetry before the flag flips.
- **Tests.** Unit tests over sign/verify including tamper, expiry, and user mismatch;
  integration test asserting the settled fare equals the signed total.

### P0.2 — Bounded offers and counters

- **Goal.** Every negotiated number sits in a defensible band around the server's estimate.
- **Design.** Add to `system_config`: `offer_floor_pct` (default 0.70), `offer_ceiling_pct`
  (1.50), `counter_floor_pct` (0.80), `counter_ceiling_pct` (1.60), `counter_max_rounds` (3).
  On create, validate `offeredPrice` against the *signed quote's* total (P0.1). On `/bid`,
  load the trip, compute the band from `estimated_fare`, reject outside it with
  `OFFER_OUT_OF_BAND` (422) carrying `{min, max}` so the client can render a useful message.
  Bands are configurable because the right numbers are a market question, not an engineering one.
- **Files to change.** `apps/api/src/routes/trips.ts` (create, `/bid`),
  `apps/api/src/lib/schemas.ts`, `apps/api/src/routes/admin.ts` (expose the four percentages),
  `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart` (clamp to the served band),
  `apps/rider/lib/screens/home/fare_estimate_sheet.dart` (same).
- **DB.** None — `system_config` already exists (`migrations/0016_system_config.sql`).
- **API contract.** `/bid` and `POST /trips` may now return 422 `OFFER_OUT_OF_BAND`.
  `/estimate` response gains `{ offerMin, offerMax }` so the client renders the band.
- **Effort.** S.
- **Risk.** Too tight a band suppresses the negotiation that differentiates the product. Ship
  wide (0.6–1.8), watch the rejection rate, tighten. Rollback is a config write.
- **Acceptance criteria.** A 1 EGP offer on a 61 EGP estimate is rejected. A 10,000 EGP counter
  on a 20 EGP trip is rejected. Both clients show the band before the user types.
- **Tests.** Table-driven boundary tests at floor, ceiling and just outside each.

### P0.3 — One live bid per captain, with a TTL

- **Goal.** The rider's chooser shows a bounded, current, ranked set of offers.
- **Design.** Unique index on `(trip_id, captain_id)` for pending bids; re-bidding updates the
  existing row and increments `round`, refusing beyond `counter_max_rounds`. Add
  `expires_at` (default 90 s) and filter `GET /trips/:id/bids` on it. Rate-limit `/bid` at
  10/min per captain using the existing middleware. Order the bid list by `counter_price ASC`
  server-side, and surface the remaining TTL to the rider's UI.
- **Files to change.** `apps/api/src/routes/trips.ts` (`/bid` 1144-1209, `/bids` 1212-1259),
  `apps/rider/lib/screens/ride/captain_bids_sheet.dart` (countdown + sorted render).
- **DB.** `0021_bid_lifecycle.sql`:
  ```sql
  ALTER TABLE trip_bids ADD COLUMN expires_at TEXT;
  ALTER TABLE trip_bids ADD COLUMN round INTEGER NOT NULL DEFAULT 1;
  CREATE UNIQUE INDEX idx_bids_trip_captain_pending
    ON trip_bids(trip_id, captain_id) WHERE status = 'pending';
  ```
- **API contract.** `/bids` rows gain `expiresAt` and `round`; `/bid` may return 429 or 409
  `BID_ROUNDS_EXHAUSTED`.
- **Effort.** M.
- **Risk.** The partial unique index needs a one-off cleanup of duplicate pending rows before it
  will build. Ship the dedup query in the same migration.
- **Acceptance criteria.** A captain bidding twice updates one row. A bid older than its TTL
  never appears in `/bids`. The list is price-ascending. A fourth round is refused.
- **Tests.** Concurrency test issuing 50 bids from one captain and asserting one row.

### P0.4 — Make the vehicle tier real

- **Goal.** XL costs more than economy, server-side, at settlement.
- **Design.** Validate `vehicleTypeId` against `vehicle_types` on create (404
  `UNKNOWN_VEHICLE_TYPE` if absent or inactive), load `multiplier`, and pass it to
  `calculateFare` via the `vehicleMultiplier` option that already exists
  (`shared/index.ts:95`). Bind the multiplier into the signed quote (P0.1) so it cannot be
  swapped after quoting. Reconcile the client tables (1.0/1.3/1.6) against the seed
  (1.0/1.25/1.5) — one source of truth, served from `GET /admin/vehicle-types` or a public
  `GET /vehicle-types`, and delete both hardcoded Dart tables.
- **Files to change.** `apps/api/src/lib/routing.ts:164-173` (thread options through
  `fareFromRoute`), `apps/api/src/routes/trips.ts:393`, `apps/api/src/lib/schemas.ts:62`,
  `apps/rider/lib/screens/home/vehicle_selector.dart:291-313`,
  `apps/rider/lib/screens/home/fare_estimate_sheet.dart:53-57`.
- **DB.** None.
- **API contract.** New `GET /vehicle-types` (authenticated) returning `{id, name, multiplier}`.
  `POST /trips` may return 404 `UNKNOWN_VEHICLE_TYPE`.
- **Effort.** S.
- **Risk.** Fares for comfort/XL rise immediately — this is a real price change and needs a
  product decision and rider comms, not just a deploy. Sequence it with a pricing announcement.
- **Acceptance criteria.** An `xl` quote is exactly `multiplier ×` the economy quote on
  base/distance/time (booking fee excluded, per `shared/index.ts:98-102`). An unknown
  `vehicleTypeId` is rejected. No multiplier constant remains in Dart.
- **Tests.** Fill the `vehicleMultiplier` gap in `packages/shared/src/index.test.ts`, including
  its interaction with surge, discount and `minFare`.

### P0.5 — Make promotions safe

- **Goal.** A campaign cannot overspend its budget, and it cannot be drained by cancellations.
- **Design.** Three changes. (a) Redeem at **completion**, not creation: mark the intended promo
  on the trip at create, and only increment `uses_count` in `/complete`. (b) Make the increment
  conditional —
  `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE code = ? AND (max_uses IS NULL OR uses_count < max_uses)`
  — and treat `changes === 0` as "budget exhausted", dropping the discount rather than granting
  it. (c) Recompute the discount at settlement so the bid path honours it (fixes F-05-04):
  settlement takes `finalFare`, applies the recorded promo, then computes commission on the
  **pre-discount** fare (fixes F-05-07).
- **Files to change.** `apps/api/src/routes/trips.ts` (create 399-504, complete 951-1088,
  cancel 709-827), `apps/api/src/routes/promo.ts`.
- **DB.** `0022_promo_integrity.sql`:
  ```sql
  ALTER TABLE trips ADD COLUMN promo_redeemed_at TEXT;
  ALTER TABLE promo_codes ADD COLUMN min_fare_egp REAL;
  ALTER TABLE promo_codes ADD COLUMN platform_funded INTEGER NOT NULL DEFAULT 1;
  ```
- **API contract.** Unchanged externally; `/promo/validate` gains `minFare` in its response.
- **Effort.** M.
- **Risk.** Moving redemption to completion changes when a code appears "used up", so a burst of
  in-flight trips can oversubscribe by the number of concurrent rides. Accept it, or reserve at
  create with a TTL release. Recommend accepting it — the exposure is bounded by concurrency.
- **Acceptance criteria.** 200 concurrent redemptions against `max_uses = 100` yield exactly
  100. A create+cancel loop consumes zero budget. A promo trip settled through the bid path
  charges the discounted price. Captain payout is identical with and without a promo.
- **Tests.** Concurrency test on the conditional update; settlement test asserting captain
  payout invariance under promo.

### P0.6 — Cancellation and no-show policy

- **Goal.** Wasted captain time has a price, and abuse in both directions has a cost.
- **Design.** Wire the config that already exists (`cancel_fee_egp`, `free_cancel_min` from
  `migrations/0016_system_config.sql:36`). Rider cancels after the grace window **and** after
  `assigned` → charge the fee, credit the captain net of commission. Captain cancels after
  accepting → count it against an acceptance-rate metric (T17's territory) and, past a
  threshold, apply a fee. No-show: captain marks `arrived`, waits `no_show_wait_min` (new, 5),
  then may complete as `no_show` and charge the fee. All of it emits `wallet_transactions` rows
  with a new `cancellation_fee` type.
- **Files to change.** `apps/api/src/routes/trips.ts` (cancel 709-827, a new `/no-show`),
  `apps/api/src/routes/admin.ts` (surface the config), both Flutter apps' cancel dialogs.
- **DB.** `0023_cancellation_fees.sql`: add `cancel_fee_charged REAL`, `cancelled_by TEXT`,
  `no_show INTEGER DEFAULT 0` to `trips`; extend the `wallet_transactions.type` allow-list.
- **API contract.** `POST /trips/:id/cancel` response gains `{ feeCharged, reason }`; new
  `POST /trips/:id/no-show` (captain).
- **Effort.** L.
- **Risk.** Charging fees on a pre-production base with no dispute flow generates support load.
  Ship in shadow first — compute and log the fee without charging for two weeks, review the
  distribution, then enable.
- **Acceptance criteria.** Cancelling inside the grace window is free. Cancelling after
  assignment past the window charges exactly `cancel_fee_egp`. A no-show pays the captain. Every
  charge has a ledger row.
- **Tests.** Time-boundary tests either side of the grace window.

### P0.7 — Settle only what was actually collected

- **Goal.** A completed trip cannot leave the platform silently out of pocket.
- **Design.** If the wallet debit matches no row (`trips.ts:997-1001`), do not proceed to a plain
  completion: either refuse with `INSUFFICIENT_FUNDS` and require the captain to switch the trip
  to cash, or complete and write a `receivable` row against the rider that blocks new bookings
  until cleared. Recommend the second — refusing to complete strands a captain at the kerb.
- **Files to change.** `apps/api/src/routes/trips.ts:993-1011`, `apps/api/src/routes/wallet.ts`.
- **DB.** `0024_receivables.sql`:
  `CREATE TABLE receivables (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, trip_id TEXT NOT NULL, amount_piastres INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL DEFAULT (datetime('now')));`
- **API contract.** `POST /trips` returns 402 `OUTSTANDING_BALANCE` when a rider has an open
  receivable.
- **Effort.** M. **Risk.** Blocking bookings on a stale receivable is a bad first impression;
  cap the block at balances above a threshold. Coordinate with **T03**.
- **Acceptance criteria.** A wallet completion with insufficient funds creates exactly one open
  receivable and blocks the next booking. **Tests.** Integration test on the zero-balance path.

### P0.8 — Authenticate the estimate; observe the route source

- **Goal.** Quotes are attributable, and a routing outage is visible within a minute.
- **Design.** Move the `/estimate` registration below `tripRoutes.use("*", authMiddleware)`
  (`trips.ts:346`) and re-key its rate limit to the user id. Bind `console.error` plus a counter
  metric into the OSRM catch (`routing.ts:61-62`) — the error must be captured, not discarded.
  Stamp `route_source` on the trip row and alert when the haversine share of a 5-minute window
  exceeds 5%. Split the nearby-captain probe into its own authenticated endpoint so the fare
  path stops returning captain coordinates.
- **Files to change.** `apps/api/src/routes/trips.ts:315-346`, `apps/api/src/lib/routing.ts:61-62`.
- **DB.** `0025_route_source.sql`: `ALTER TABLE trips ADD COLUMN route_source TEXT;`
- **Effort.** S. **Risk.** Any unauthenticated caller of `/estimate` breaks — grep the Flutter
  apps for pre-login estimate calls before shipping.
- **Acceptance criteria.** `/estimate` returns 401 without a token. An OSRM outage produces log
  lines and a metric within one minute.

### P1.1 — Real surge, wired to both paths at once

- **Goal.** Demand response that the rider is told about before they book.
- **Design.** Delete the dead read at `trips.ts:390-392`. New `surge_cells` table keyed by
  `(city, geohash5, window_start)` — the geohash primitive already exists
  (`shared/index.ts:129-169`, `pricing.ts:36-38`) and is used by dispatch. A cron computes, per
  5-minute window, `demand = open trips in cell`, `supply = online idle captains in cell`, then
  `raw = clamp(demand / max(supply,1), 1.0, cap)` with a configurable `cap` (default 2.0) and
  exponential smoothing (`α = 0.3`) against the previous window to stop oscillation. Lookup is
  by pickup cell with a fallback to city-wide 1.0. **Critically, both `/estimate` and create
  read the same helper** so they cannot diverge (F-05-14), and the multiplier is carried inside
  the signed quote (P0.1). The rider must see and confirm the multiplier before booking.
- **Files to change.** `apps/api/src/lib/surge.ts` (new), `apps/api/src/routes/trips.ts`
  (both paths), `apps/api/src/index.ts` (cron), `apps/admin/src/pages/PricingPage.tsx` (a surge
  heat view and a manual override with an expiry), rider fare sheet (disclosure).
- **DB.** `0026_surge_cells.sql`:
  ```sql
  CREATE TABLE surge_cells (
    city TEXT NOT NULL, cell TEXT NOT NULL, window_start TEXT NOT NULL,
    demand INTEGER NOT NULL, supply INTEGER NOT NULL, multiplier REAL NOT NULL,
    PRIMARY KEY (city, cell, window_start)
  );
  CREATE INDEX idx_surge_lookup ON surge_cells(city, cell, window_start DESC);
  ```
- **API contract.** `/estimate` gains `{ surgeMultiplier, surgeReason }`; create requires
  `surgeAcknowledged: true` when the multiplier exceeds 1.0.
- **Effort.** L. **Risk.** Surge on a thin pre-production supply base swings wildly; the cap and
  smoothing are the controls, and a kill switch (`surge_enabled`) should ship with it.
- **Acceptance criteria.** Quoted and charged multipliers are always equal. Multiplier never
  exceeds the cap. A rider cannot be charged surge they did not acknowledge.

### P1.2 — Per-user promo limits · P1.3 — Fare integrity in integers · P1.4 — Receipt line items

- **P1.2.** New `promo_redemptions (promo_code, user_id, trip_id, redeemed_at)` with a unique
  index on `(promo_code, user_id)` when the code is single-use-per-user; add `first_trip_only`
  and `city` scope columns. Closes F-05-16, M5. **Effort** S. **Files**
  `apps/api/src/routes/promo.ts`, `trips.ts`. **DB** `0027_promo_redemptions.sql`.
- **P1.3.** Move `calculateFare` to integer piastres end to end and backfill
  `offered_price`, `accepted_price`, `counter_price` into `*_piastres` columns, finishing what
  migration 0005 started (F-05-20). Also fix the `minFare`-before-discount ordering
  (F-05-22, `shared/index.ts:104-105`). **Effort** M. **Risk** touches every money read; do it
  behind a parity test that runs both implementations and asserts equality on a large sample of
  historical trips. Coordinate with **T03**.
- **P1.4.** A structured receipt: base, distance, time, booking fee, surge delta, discount,
  waiting, tolls, total — persisted per trip and rendered in both apps. Prerequisite for
  P2.1 and for any dispute process. **Effort** M.

### P2.1 — Waiting time and tolls · P2.2 — Fare-change events · P2.3 — Route reconciliation

- **P2.1.** Price the waiting minutes between `arrived_at` and `started_at` beyond a free
  allowance, and add a toll line item the captain can attest to. Requires P1.4.
- **P2.2.** A `trip_fare_events` audit trail so any post-agreement change to the settled amount
  is attributable — the precondition for ever allowing one.
- **P2.3.** Compare the driven GPS path against the quoted route and flag material divergence
  for review, closing M10. Depends on T21's path data.

---

## 7. Phasing

| Item | Phase | Effort | Owner type | Closes |
|---|---|---|---|---|
| P0.1 Signed fare quotes | P0 | M | backend + Flutter | F-05-01 (partly), M1, M2, M8, M9, M10 |
| P0.2 Bounded offers and counters | P0 | S | backend + Flutter | F-05-02, F-05-03 |
| P0.3 One live bid per captain + TTL | P0 | M | backend + Flutter | F-05-08, F-05-24, F-05-31 |
| P0.4 Vehicle tier priced server-side | P0 | S | backend + Flutter | F-05-10, F-05-29 |
| P0.5 Promotion integrity | P0 | M | backend | F-05-04, F-05-05, F-05-06, F-05-07 |
| P0.6 Cancellation and no-show policy | P0 | L | backend + Flutter + ops | F-05-11 |
| P0.7 Settle only what was collected | P0 | M | backend | F-05-12 |
| P0.8 Auth the estimate; observe routing | P0 | S | backend | F-05-09, F-05-15, F-05-25 |
| **Settle `offered_price` on direct accept** | **P0** | **S** | **backend** | **F-05-01 (core)** |
| P1.1 Real surge, both paths | P1 | L | backend + admin + Flutter | F-05-13, F-05-14, F-05-27 |
| P1.2 Per-user promo limits | P1 | S | backend | F-05-16, M5 |
| P1.3 Integer money + minFare ordering | P1 | M | backend | F-05-20, F-05-22 |
| P1.4 Structured receipt line items | P1 | M | backend + Flutter | F-05-21 |
| Approval + dispatch checks on `/bid` | P1 | S | backend | F-05-17, F-05-18 |
| Delete dead code; single road-factor constant | P1 | S | backend | F-05-28 |
| P2.1 Waiting time and tolls | P2 | L | backend + Flutter | F-05-26 |
| P2.2 Fare-change audit events | P2 | M | backend | — |
| P2.3 Route reconciliation | P2 | L | backend | M10 |
| Intercity commission accounting | P2 | M | backend | F-05-23 |
| Currency allow-list; audit-failure alerting | P2 | S | backend | F-05-33, F-05-35 |

The one-line change at the top of P0 deserves emphasis: making `/accept` set
`accepted_price = offered_price` and `commission = offered_price × rate` (mirroring
`trips.ts:1299-1310`) is a handful of lines and closes the single worst finding in this
document. It should ship first, before the larger quote work, because every day it is not
shipped is a day captains are paid a different number than the one they agreed to.

---

## 8. Metrics

| Metric | Definition | Current | Target |
|---|---|---|---|
| Quote→charge divergence | `abs(settled − quoted) / quoted`, p99 | unmeasured; **structurally unbounded** on direct accept (F-05-01) | 0 for 100% of trips |
| Unsigned trip creates | creates with no valid `quoteToken` | 100% | 0 before the P0.1 flag flips |
| Offer-band rejection rate | 422 `OFFER_OUT_OF_BAND` ÷ create attempts | n/a | 1–5% (higher means the band is too tight) |
| Haversine fare share | trips priced with `route_source = 'haversine'` | **unmeasured and unmeasurable** (F-05-09) | < 1% daily; alert above 5% in 5 min |
| Fare error vs OSRM | fallback fare ÷ OSRM fare on replayed routes | +28% modelled | < +8% after recalibrating the road factor |
| Bids per trip | median and p99 pending bids | unbounded (F-05-08) | median ≤ 4, p99 ≤ 10 |
| Bid staleness | age of bids shown to riders | unbounded — no TTL | p99 < 90 s |
| Promo overspend | redemptions beyond `max_uses` | possible today (F-05-05) | exactly 0 |
| Promo cost split | share of discount borne by the platform | ~20% | 100% |
| Captain earnings variance under promo | payout with promo ÷ payout without, same fare | 0.80 | 1.00 |
| Cancellation rate after assignment | cancels after `assigned` ÷ assignments | unmeasured | baseline, then < 8% |
| Tier price ratio realised | mean XL fare ÷ mean economy fare, same distance band | **1.00** (F-05-10) | matches the configured multiplier ±2% |
| Wallet completions on failed debit | completions where the debit did not match | unmeasured, non-zero possible (F-05-12) | 0 |
| Contribution margin per trip | see §8.1 | 19.5% cash / 17.0% card (modelled) | tracked weekly per city |

### 8.1 Unit economics — 8 km / 20 min Cairo trip

Confirmed inputs: `base_fare 12`, `per_km 4.5`, `per_min 0.5`, `booking_fee 3`, `min_fare 25`,
`commission_rate 0.2` (`migrations/0001_init.sql:117-121`). Gross fare 61.00 EGP (§4, F-05-09).

| Line | Cash | Card | Basis |
|---|---|---|---|
| Gross fare | 61.00 | 61.00 | **confirmed** — `calculateFare` on the seeded tariff |
| Platform commission (20%) | 12.20 | 12.20 | **confirmed** — `0001_init.sql:120`, `trips.ts:429` |
| PSP fee | 0.00 | −1.53 | **assumed** 2.5% of gross. No PSP rate exists anywhere in the repo; `docs/COST.md:19` names "online payment fees (% of GMV)" without a number. Replace with the signed Paymob rate before using this for any decision |
| Infrastructure | −0.33 | −0.33 | **assumed** — `docs/COST.md` growth band ($100–200/mo at 500–1000 trips/day), midpoint, at an assumed 49 EGP/USD. No FX rate is in the repo |
| **Contribution margin** | **11.87** | **10.34** | |
| **Margin % of gross** | **19.5%** | **17.0%** | |
| **Margin % of commission** | **97.3%** | **84.8%** | the PSP fee eats ~13% of the platform's own take on card |

Captain payout is 48.80 EGP on both, because the PSP fee is absorbed by the platform, not passed
through (`trips.ts:969-971`, `:1036-1054`) — **confirmed**, and the right call.

Three caveats that change the picture materially. This model assumes the fare *is* 61.00: under
F-05-01 the captain may have agreed to a different number, and under F-05-09 an OSRM outage
makes it 78.10. Under a 20% promo, F-05-07 moves 16 EGP of the 20 EGP discount onto the captain,
so the platform's modelled margin *understates* the damage — the platform still clears 9.47 EGP
while the captain drops to 64 EGP. And with F-05-10 unfixed, every XL trip in this table is
earning economy revenue against a higher-cost vehicle. Fixing P0.4 alone lifts realised revenue
per premium trip by 25–50% at zero marginal cost.

---

## 9. Cross-cutting notes

- **T27 (cross-app parity)** — the parity load here is heavy. The vehicle multiplier table is
  hardcoded three times with two different value sets: rider `1.0/1.3/1.6`
  (`fare_estimate_sheet.dart:53-57`, `vehicle_selector.dart:291-313`) versus the DB seed
  `1.0/1.25/1.5` (`0002_enhancements.sql:88-92`) and a third hand-rolled copy in the admin
  preview (`PricingPage.tsx:186-211`). Currency rendering uses four different strategies across
  four files: an inline `isAr` ternary (`vehicle_selector.dart:391`), an Arabic-only literal
  (`captain_bids_sheet.dart:459`), a localised `strings.egp` (`offer_card.dart:414-429`), and a
  hardcoded `'ج.م'` inside `packages/flutter_shared` (`counter_offer_sheet.dart:221`) — a shared
  widget with no i18n at all. Rounding drifts too: everything renders whole EGP except the
  captain's counter field, which emits two decimals (`counter_offer_sheet.dart:65`). Vocabulary
  drifts across "offer", "bid" and "counter" for one primitive
  (`fare_estimate_sheet.dart:663`, `offer_card.dart:398,688`, `counter_offer_sheet.dart:15`).
  And the captain app defensively reads both `offered_price` and `offeredPrice`
  (`offer_card.dart:239-241`) because REST returns snake_case rows while the WebSocket payload is
  camelCase — the client is absorbing a transport inconsistency that should be fixed at source.
  The countdown asymmetry (15 s ring for the captain, nothing for the rider) is the most
  user-visible of these.
- **T03 (money integrity)** — F-05-12 (a wallet trip completing on a failed debit,
  `trips.ts:997-1010`) is as much a ledger problem as a pricing one; P0.7 sketches a receivable
  but the ledger design is yours. F-05-20 (bidding columns still `REAL` while migration 0005
  converted the others) needs your integer strategy. Note also that commission is computed once
  at create (`:429`) and re-derived at accept-bid (`:1302`) — two sites that must agree forever.
- **T04 (payments/payouts)** — no PSP fee rate exists anywhere in the repo, so the margin model
  in §8.1 rests on an assumed 2.5%. If you can pin the real Paymob rate card, §8.1 should be
  recomputed. Card trips lose ~13% of platform take to the PSP on the assumed rate.
- **T06 (dispatch)** — `/bid` bypasses every dispatch control: no radius check, no membership in
  the offered set, no approval check (F-05-17, F-05-18). Your radius filtering at
  `trips.ts:518-531` is carefully done and then trivially sidestepped by calling `/bid` with a
  trip id from `GET /captain/offers`.
- **T02 / T25 (authz, privacy)** — `POST /trips/estimate` is unauthenticated
  (`trips.ts:315` registered before the middleware at `:346`) and returns live captain
  coordinates (`:336-342`). The fare-oracle aspect is mine; the location disclosure is yours.
- **T08 (data model)** — `trip_bids` has no expiry, no round counter and no uniqueness
  (`0004_bidding_system.sql`); `promo_codes` has no per-user dimension
  (`0002_enhancements.sql:54-70`); `trips.surge_multiplier` exists while `pricing_rules` has no
  surge column, which is the root of F-05-13.
- **T11 (admin)** — `PricingPage.tsx` re-implements the fare formula by hand
  (`:186-211`, acknowledged in a comment at `:176-183`) rather than importing
  `@synaptic-go/shared`, so the operator's preview can silently disagree with production. The
  console also has no surge control and no cancellation-fee control even though
  `system_config` stores the values.
- **T17 (safety/trust)** — cancellation and no-show policy (P0.6) needs an acceptance-rate and
  dispute model to sit on; the fee mechanics are mine, the behavioural response is yours.
- **T20 (intercity/B2B)** — intercity fares appear to bypass commission entirely
  (`intercity.ts:99-102`, no `commission` column in `0003_global_transport.sql:94-106`). Either
  there is a revenue model I could not find, or intercity currently books zero platform revenue.
- **T22 (observability)** — the silent OSRM catch (`routing.ts:61-62`) and the swallowed audit
  failure (`audit.ts:33-35`) are both blind spots on money-bearing paths.
- **T23 (testing)** — `packages/shared/src/index.test.ts` is the only fare test file. It does not
  cover `vehicleMultiplier` at all, never combines two options, and never exercises the non-Cairo
  tariffs. The bid, accept-bid and complete handlers have no tests I could find.

---

## 10. Open questions

1. **Should the rider's offer be binding on direct accept?** Options: (a) `/accept` settles
   `offered_price` — honours the negotiation, but a captain tapping accept on a lowball is stuck
   with it; (b) `/accept` settles `estimated_fare` and the captain UI stops showing
   `offered_price` — honest, but discards the differentiator; (c) direct accept is removed for
   bidding-mode trips, forcing every assignment through an explicit price agreement.
   **Recommendation: (a) now, (c) later.** (a) is a few lines and matches what the captain
   already sees; (c) is the cleaner end state once P0.2's bands make lowballs impossible.
2. **How wide should the offer band be?** Recommendation: launch at 0.6–1.8× the estimate for
   riders and 0.8–1.6× for counters, then tighten on data. Too tight and the product becomes
   Uber with extra steps; too wide and F-05-02 persists in spirit.
3. **Who funds promotions?** Recommendation: the platform, unconditionally — pay the captain on
   the pre-discount fare and book the discount as marketing cost. The `platform_funded` flag in
   P0.5 leaves room for genuinely captain-funded campaigns later, but the default must flip.
4. **Surge, or inDrive-style transparency?** The product is positioned against inDrive, which
   deliberately has no surge and shows demand hints instead. Recommendation: implement P1.1 but
   ship it disabled, and launch with demand hints ("many riders nearby") plus a wider offer band
   at peak. Revisit once supply data exists.
5. **Cancellation fee level and grace window?** `system_config` seeds 3 minutes; the fee amount
   needs a market decision. Recommendation: 3-minute grace, fee at ~50% of `min_fare` (12.50 EGP
   in Cairo), shadow-logged for two weeks before charging.
6. **Do comfort/XL launch at the DB multipliers or the app's?** They disagree (1.25/1.5 vs
   1.3/1.6). Recommendation: the DB is the source of truth, served over an endpoint; pick the
   values deliberately as a pricing decision rather than inheriting whichever file was edited last.
7. **Is `OSRM_URL` overridden in production?** `needs-check` — `wrangler.toml` was out of scope.
   If it still points at `router.project-osrm.org`, that is a P0 infrastructure item independent
   of everything above.
8. **What is the real Paymob rate?** Not in the repo. Every card-trip margin number in §8.1 moves
   with it.
