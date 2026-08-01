# 20 — Intercity, B2B & New Verticals

> Track: C — Feature parity & new capability · Reviewer: chat-20260801-1352-6e22 · Date: 2026-08-01
> Base commit reviewed: `4fa12c4dd7f133f3eb335953a710875262383681`

## 1. Scope

This document audits the two secondary businesses that already exist in the Synaptic Go
codebase — **intercity seat booking** and **B2B corporate accounts** — and scopes the
**delivery/courier** vertical plus the other verticals the product brief raises
(motorcycle, tuk-tuk, rentals, airport transfers, commuter subscriptions).

**In scope**

- The complete intercity flow: route/schedule definition, seat inventory, payment,
  QR verification, boarding, cancellation and refund.
- The complete B2B flow: company creation, employee binding, spend policy, trip
  tagging, the monthly invoice cron, and the invoice artefact itself.
- The admin-console gap for both verticals (specification only).
- A delivery vertical scoping with data model, endpoints and honest effort.
- A recommendation on which vertical earns the next quarter of engineering time.

**Explicitly out of scope** (owned elsewhere — findings that touch these are routed in §9)

| Not covered here | Owner |
|---|---|
| Wallet/ledger correctness and the REAL→integer currency migration as a whole | T03 |
| Paymob integration correctness, webhook HMAC, captain payouts | T04 |
| The city-ride bidding/surge engine itself | T05 |
| Dispatch and matching internals (GeoCell, CaptainInbox, OfferScheduler) | T06 |
| Migration hygiene and schema-wide integrity | T08 |
| Admin console architecture and shared components | T11 |
| Rider/captain app journeys for *city* rides | T09 / T10 |
| Object-level authorisation as a systematic axis | T02 |
| Privacy/PII and legal posture as a systematic axis | T25 |
| Cross-app duplication and vocabulary drift as a programme | T27 |

A note on what this document is not: it is **not** a claim that intercity and B2B are
half-finished. The finding of this review is stronger and simpler than that, and it is
in §3.

## 2. What I actually read

Every file below was downloaded at base commit `4fa12c4d` and read from disk with real
line numbers. Where I state that something is absent, I verified the absence by grepping
the downloaded file, not by trusting GitHub code search — that index is stale on this
repo and returned a false negative for `company_id` in `trips.ts` that would have
inverted a major finding had I believed it.

**API — read in full**

| File | Note |
|---|---|
| `apps/api/src/routes/intercity.ts` (463 L) | The entire intercity surface. Read line by line. |
| `apps/api/src/routes/companies.ts` (239 L) | The entire B2B surface. Read line by line. |
| `apps/api/src/lib/schemas.ts` (331 L) | Read the intercity/company/payment schemas closely; skimmed the rest. |
| `apps/api/src/lib/utils.ts` | Only to check `id()` entropy for QR tokens — `crypto.randomUUID()`, fine. |
| `apps/api/wrangler.toml` (180 L) | Cron triggers, DO/R2/KV/queue bindings. |

**API — read the relevant regions**

| File | Region read |
|---|---|
| `apps/api/src/index.ts` (372 L) | Route mounting (108–122) and the whole `scheduled()` handler (266–372). |
| `apps/api/src/routes/trips.ts` (1371 L) | Company tagging on trip create (425–500) and completion billing (985–1000). Grepped the whole file for company/cost-centre terms. |
| `apps/api/src/routes/payments.ts` | Intention schema (12–18) and the webhook settlement branch (195–235). |
| `apps/api/src/routes/admin.ts` (36 KB) | Grepped only — to establish that no intercity/company admin endpoint exists. |

**Migrations**

| File | Note |
|---|---|
| `migrations/0003_global_transport.sql` | Read 66–160 in full: the intercity and company DDL. |
| `migrations/0010_intercity_booking_cancel.sql` (9 L) | Read in full. |
| `migrations/0002_enhancements.sql` | `vehicle_types` DDL and seeds (83–93). |
| `migrations/0001_init.sql`, `0011`, `0016` | Skimmed for related tables. |
| Full migration listing (0001–0019) | Listed to confirm no later migration touches these verticals. |

**Clients**

| File | Note |
|---|---|
| `apps/rider/lib/screens/home/vehicle_selector.dart` | Service-category strip. The `enabled:false` categories. |
| `apps/rider/lib/screens/home/home_screen.dart` | Travel-mode plumbing (85, 455–472, 510, 527–543). |
| `apps/rider/lib/screens/home/travel_mode_bottom_bar.dart` (209 L) | The intercity bottom bar. |
| `apps/rider/lib/services/app_state.dart` (696 L) | The rider API client — audited for every endpoint it calls. |
| `apps/rider/lib/screens/home/fare_estimate_sheet.dart` | Where booking is submitted. |
| `apps/rider/lib/screens/ride/schedule_screen.dart` | Dead code — defined, never imported. |
| `apps/captain/**` (all screens + `captain_state.dart`, both WS services) | Grepped exhaustively for intercity/passenger/board/QR. |
| `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml`, `packages/flutter_shared/pubspec.yaml` | Dependency audit for QR/scanner packages. |
| `apps/admin/src/App.tsx` (66 L) | The full admin route table. |
| `apps/admin/src/pages/` | Directory listing only (11 files) — enough to establish the gap. |

**Other**

| File | Note |
|---|---|
| `scripts/generate_pdf.py` (891 L) | Read the header and grepped throughout. It is not what the brief assumes it is. |
| `docs/ROADMAP.md`, `docs/API.md`, `docs/ARCHITECTURE.md` | Skimmed for stated intent on these verticals. |

**Verification I ran rather than asserted**

- **SQLite reproduction** of the invoice period query against D1-shaped `created_at`
  values, to test whether the manual endpoint and the cron agree. They do not. The
  reproduction and its output are in F-20-16.
- **Hono routing test** (real `hono@4.12.33` loaded in Node) to check whether
  `use("/admin/*")` leaves the bare `/admin` routes in `companies.ts` unguarded. **It
  does not** — the wildcard covers the bare path and `requireRole("admin")` runs on all
  four admin routes. I had this written up as an S1 authorisation bypass and deleted it
  when the test came back negative. Recording it here so nobody re-raises it.

**Not read** — the four Durable Object implementations, the notification queue consumer
body, and the admin page components. I reference the DO/queue bindings only as
infrastructure that a delivery vertical would reuse, and I do not make behavioural
claims about them.

## 3. How it works today

### 3.1 The headline: intercity is a complete backend with no front door

The intercity backend is real. `apps/api/src/routes/intercity.ts` is 463 lines and
exposes twelve endpoints across public discovery, rider booking, captain manifest and
admin management. Three tables back it (`intercity_routes`, `intercity_schedules`,
`intercity_bookings`, `migrations/0003_global_transport.sql:69–108`) and a later
migration added cancellation support (`migrations/0010_intercity_booking_cancel.sql:7`).

**No client ever calls any of it.**

The rider app offers a service-category strip with four entries
(`apps/rider/lib/screens/home/vehicle_selector.dart:33–54`):

```dart
static const _categories = <_Category>[
  _Category('ride', 'رحلة', 'Ride', 'assets/images/icons/cat_ride.png'),
  _Category('intercity', 'سفر', 'Intercity', 'assets/images/icons/cat_intercity.png'),
  _Category('freight', 'الشحن', 'Freight', 'assets/images/icons/cat_freight.png', enabled: false),
  _Category('tuktuk', 'تروسيكل', 'Tuk-tuk', 'assets/images/icons/cat_tuktuk.png', enabled: false),
];
```

Selecting **سفر** sets `_category = 'intercity'`, which flips one boolean
(`home_screen.dart:85`) whose only effect is to mount `TravelModeBottomBar` instead of
`MainBottomNav` (`home_screen.dart:527–543`). When the rider then taps continue,
`_showBookingFlow()` runs (`home_screen.dart:455–472`) and **does not pass `_category`**
to the sheet it opens. That sheet calls `createTrip(...)`
(`fare_estimate_sheet.dart:193`), which posts to `/trips`
(`app_state.dart:496–509`) — the ordinary city-ride endpoint, with no seat count, no
schedule, no route id, and no intercity marker of any kind.

The string `intercity` does not appear anywhere in `app_state.dart`. It does not appear
anywhere in `apps/captain/`. The rider's "my orders" tab under travel mode routes to the
ordinary `HistoryScreen`, which reads `GET /trips` (`home_screen.dart:535`, `:510`).

So a rider who selects "سفر", picks two points and books has **not** booked a seat on a
scheduled intercity service. They have requested a normal city ride, which will be
dispatched to a nearby city captain, priced by the city pricing engine, and — if the
destination is Alexandria — offered to captains in Cairo as an ordinary trip.

The consequence for this review is that every other intercity finding below is currently
latent. None of them can hurt a user today because no user can reach the code. They will
all become live on the day someone wires the client up, which is precisely when the
pressure to ship will be highest and the appetite for auditing lowest. That is the case
for fixing them now, as part of the wiring work, rather than after.

### 3.2 The intercity flow as designed

Reading the backend on its own terms, this is what it does.

| Stage | Endpoint | Behaviour | State |
|---|---|---|---|
| Route definition | `POST /intercity/admin/routes` (`intercity.ts:396`) | Admin creates an origin/destination pair with a `base_price` per seat. Validated by `intercityRouteSchema` (`schemas.ts:102–109`). | `intercity_routes` |
| Route edit | `PATCH /intercity/admin/routes/:id` (`:418`) | Whitelisted field update. **No schema validation.** | — |
| Schedule creation | `POST /intercity/admin/schedules` (`:433`) | Admin creates a departure with `seats_total` (default 4, max 50). | `intercity_schedules`, `status='open'` |
| Captain assignment | `POST /intercity/admin/schedules/:id/assign` (`:447`) | Admin sets `captain_id` by raw id and pushes a notification. | — |
| Discovery | `GET /intercity/routes`, `/schedules` (`:16`, `:43`) | Public, unauthenticated. `LIKE %from%` city search. | — |
| Booking | `POST /intercity/bookings` (`:82`) | Validates schedule is open and not departed, computes fare, claims seats, inserts booking, debits wallet if applicable, notifies captain. | `intercity_bookings`, `status='booked'` |
| Rider's bookings | `GET /intercity/bookings` (`:205`) | Lists own bookings joined to schedule and route. | — |
| Cancellation | `POST /intercity/bookings/:id/cancel` (`:225`) | Idempotent, conditional, releases seats, refunds wallet. | `status='cancelled'` |
| Captain manifest | `GET /intercity/captain/schedules[/:id/passengers]` (`:326`, `:340`) | Captain's own open/boarding schedules and their passenger list including `qr_token`. | — |
| Boarding | `POST /intercity/captain/board/:bookingId` (`:367`) | Marks a passenger boarded, optionally checking a QR token. | `status='boarded'` |

**Seat inventory.** There is no seat map — no seat numbers, no seat selection. Inventory
is a pair of integers on the schedule: `seats_total` and `seats_booked`
(`0003:85–86`). "Booking a seat" means incrementing a counter.

**The concurrency guard the brief asks about (Q2) is real and it is correct.** PR #13's
claim holds up. `intercity.ts:116–124`:

```sql
UPDATE intercity_schedules SET seats_booked = seats_booked + ?
 WHERE id = ? AND seats_booked + ? <= seats_total AND status = 'open'
```

```ts
if (claim.meta && claim.meta.changes === 0) {
  return c.json({ error: "Not enough seats available", code: "NO_SEATS" }, 409);
}
```

D1 executes that statement atomically and the `WHERE` clause re-reads `seats_booked` at
execution time, so two concurrent requests for the last two seats cannot both succeed —
the loser flips zero rows and gets a 409. The pattern is the same one used for trip
acceptance, and it is the right pattern. Because inventory is a counter rather than a
seat map, "can the same seat be sold twice" is not strictly meaningful; the correct
question is "can the vehicle be oversold", and the answer is **no, not by this path**.
It can be oversold by the boarding path — see F-20-03.

**Payment.** `intercityBookingSchema` accepts three methods (`schemas.ts:117–123`):

```ts
paymentMethod: z.enum(["cash", "wallet", "card"]).default("cash"),
```

Only one of them is implemented. `wallet` is debited with a conditional update that
cannot drive the balance negative, and on failure it compensates by deleting the booking
and releasing the seats (`intercity.ts:149–171`) — genuinely careful code. `cash` is a
no-op, which is defensible in principle (the captain collects) except that no captain
surface exists to collect it and no commission is ever taken. `card` is a no-op that is
not defensible: the booking is created, the seat is held, `fare` is recorded, and
nothing anywhere charges the rider. See F-20-02.

**Fare.** `intercity.ts:99–102`:

```ts
const route = await c.env.DB.prepare(`SELECT base_price FROM intercity_routes WHERE id = ?`)
  .bind(schedule.route_id).first<{ base_price: number }>();
const fare = (route?.base_price ?? 0) * body.seats;
```

Flat `base_price × seats`. No occupancy curve, no time-of-day, no surge, and no contact
whatsoever with the bidding engine that is the product's stated differentiator (Q4).
The `?? 0` fallback silently produces a free booking if the route row is missing.

**Cancellation and refund (0010).** The policy is documented in the code as
inDrive-style: free cancellation with a full refund at any time before departure
(`intercity.ts:220–224`). The implementation matches the policy and is one of the better
pieces of code in this area — it is idempotent for repeat cancels (`:248–250`), blocks
cancelling after boarding or departure (`:251–256`), takes the state transition with a
conditional update so a concurrent cancel/board cannot double-refund (`:260–268`),
releases seats with a defensive floor (`:271–277`), and only refunds wallet-paid fares
(`:281–294`). The problem is not the code, it is the policy: see F-20-08.

**Lifecycle.** `intercity_schedules.status` permits five values
(`0003:88`): `open`, `boarding`, `departed`, `cancelled`, `completed`. Grepping the
entire route file, **nothing ever writes any value other than the `'open'` set at
insert.** There is no cron, no admin endpoint and no captain action that advances a
schedule. A schedule sits at `open` forever, including after its departure time.

### 3.3 The B2B flow as built

The corporate product has a different shape of problem. It is not unreachable — it is
wired into the trip flow *silently and unconditionally*.

**Company and employee setup.** An admin creates a company
(`companies.ts:70–97`, validated by `companySchema`, `schemas.ts:125–133`) capturing
`legal_name`, `tax_id`, `credit_limit` and `monthly_invoice_day`. An admin then binds an
employee by raw user id (`companies.ts:122–142`) with a `cost_center`,
`spend_limit_month`, `allowed_vehicle_types` and `allowed_hours`.

**Trip tagging — the critical path.** On every trip creation, `trips.ts:431–436` looks up
a binding for the requesting rider:

```ts
// Resolve company binding (B2B) — employee trips are billed to the company.
const emp = await c.env.DB.prepare(
  `SELECT company_id, cost_center FROM company_employees WHERE user_id = ? AND active = 1 LIMIT 1`,
).bind(user.id).first<{ company_id: string; cost_center: string }>();
```

and writes it straight onto the trip (`trips.ts:477–479`):

```ts
emp?.company_id ?? null,
emp?.cost_center ?? null,
emp ? 1 : 0,          // billed_to_company
```

That is the whole of it. **If you are bound to a company, every trip you take is billed
to your employer.** There is no opt-in, no business/personal toggle, no prompt, and no
way to decline. At completion, `trips.ts:993` reads
`trip.payment_method === "wallet" && !trip.billed_to_company` — so even if the employee
selected their own wallet, the corporate flag suppresses the personal debit and the
company pays.

None of the four policy fields is consulted on this path. Grepping the entire API for
`allowed_hours`, `allowed_vehicle_types` and `credit_limit` returns hits **only** in
`companies.ts:27–28` (a `SELECT` list) and `:76`/`:128` (INSERT column lists). They are
never compared against anything.

The one place that does check a limit is `POST /companies/trip`
(`companies.ts:14–65`) — and that endpoint creates nothing. Its own comment says so
(`:53–54`):

```ts
// Don't actually create the trip here — rider flow goes through /trips with
// a `companyId` marker. We just return authorization + booking context.
```

No client calls it. It is a control surface that controls nothing.

**Invoicing.** Two implementations exist for the same job.

| | Manual | Cron |
|---|---|---|
| Entry point | `POST /companies/admin/:id/invoice` (`companies.ts:167`) | `scheduled()` in `index.ts:333–370`, trigger `0 3 1 * *` (`wrangler.toml:64`) |
| Period bounds | JS `Date` → `.toISOString()` (`companies.ts:170–171`) | same (`index.ts:340–341`) |
| Selection predicate | `created_at >= ? AND created_at < ?` — raw string compare (`:176`) | `datetime(created_at) >= datetime(?)` — normalised (`:346`) |
| Flag clearing | `created_at >= ? AND created_at < ?` — raw (`:193`) | `created_at >= ? AND created_at < ?` — raw (`:361`) |
| Guard | none | `sum.trips > 0` (`:350`) |

Both write a `company_invoices` row holding only `total_trips` and `total_amount`
(`0003:144–154`), then clear `billed_to_company` on the period's trips. The two
predicates disagree, and within the cron the SELECT and the UPDATE disagree with each
other. This is F-20-16 and it is proven, not inferred.

**The invoice artefact.** A `company_invoices` row is the entire deliverable. There are
no line items, no VAT, no currency field, no due date, no PDF and no delivery mechanism.
`paymob_order_id` exists on the table (`0003:152`) and is never written or read anywhere
in the API. The invoice cannot be paid through the platform.

The brief asks whether `scripts/generate_pdf.py` is connected to this (Q6). It is not,
and it is not an invoice generator at all — it renders a bilingual project pitch document
("مشروع منصة شاملة لنقل الركاب"), it hardcodes a Windows font directory
(`scripts/generate_pdf.py:26–31`):

```python
FONT_DIR = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("Arabic", os.path.join(FONT_DIR, "tahoma.ttf")))
```

and nothing references it. It is a developer's local artefact that happens to live in the
repo.

**Who is the company's admin?** Nobody. `company_employees` has no role column
(`0003:126–136`). The "company portal" (`companies.ts:217–239`) authorises on the single
condition that the caller is an *active employee of some company*, and then returns that
company's full invoice history plus its last 100 trips including
`pickup_address`, `dropoff_address` and `cost_center`. The most junior employee can read
the CEO's movements. Cross-referenced to T02 and T25 in §9.

### 3.4 Admin blindness

Neither vertical has an operator surface. The admin console registers ten routes
(`apps/admin/src/App.tsx:50–59`): dashboard, live map, captains, verification, trips,
analytics, pricing, users, audit, settings. There is no companies page and no intercity
page, and `apps/api/src/routes/admin.ts` — 36 KB of admin endpoints — contains zero
occurrences of `intercity` or `compan`.

Running either business today means an engineer issuing authenticated `curl` calls
against `/intercity/admin/*` and `/companies/admin/*`. Creating tomorrow's Cairo→Alexandria
departure is a hand-written POST. Onboarding a corporate customer is a hand-written POST
with a user id looked up out of the database by hand.

### 3.5 What exists that a delivery vertical could reuse

For §6.3's scoping, the substrate is better than the verticals built on it:

| Capability | Binding / location | Reusable for delivery? |
|---|---|---|
| Geo matching | `GEO_CELL` DO (`wrangler.toml:26`) | Yes — pickup matching is the same problem |
| Captain offer inbox | `CAPTAIN_INBOX` DO (`:27`) | Yes |
| Offer timing | `OFFER_SCHEDULER` DO (`:28`) | Yes |
| Live trip channel | `TRIP_ROOM` DO (`:25`) | Yes — parcel tracking is a trip room |
| Object storage | `FILES` R2 bucket (`:19–20`) | Yes — this is where proof-of-delivery photos go |
| Push/notify | `NOTIFICATIONS` queue + DLQ (`:46–55`) | Yes |
| Scheduled work | two cron triggers (`:62–65`) | Yes |
| Vehicle classes | `vehicle_types` (`0002:83–93`) | **No** — see below |

`vehicle_types` is three rows with no capacity dimension
(`migrations/0002_enhancements.sql:83–93`):

```sql
CREATE TABLE IF NOT EXISTS vehicle_types (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  multiplier REAL NOT NULL DEFAULT 1.0, active INTEGER NOT NULL DEFAULT 1
);
INSERT OR IGNORE INTO vehicle_types (id, name, multiplier, active) VALUES
  ('economy','Economy',1.0,1), ('comfort','Comfort',1.25,1), ('xl','XL',1.5,1);
```

No motorcycle, no van, no seat capacity, no weight or volume limit. The absent capacity
column is also why intercity cannot validate that an assigned captain's vehicle can
actually seat `seats_total` passengers (F-20-13).

Meanwhile the rider UI already advertises **الشحن** (freight) and **تروسيكل** (tuk-tuk)
as greyed-out chips with a "قريباً" badge (`vehicle_selector.dart:33–54`, with the
intent stated in the comment at `:29–32`). The product is already promising these to
users.

## 4. Findings

Severity is judged **at the point the feature is exposed to traffic**. An intercity
defect that no user can currently reach is still S1 if it would lose money on day one of
the vertical being switched on; the "Live today?" column tells you whether it is bleeding
now or waiting to.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Live today? | Confidence |
|---|---|---|---|---|---|---|
| F-20-01 | S1 | The entire intercity backend is unreachable from any client; "سفر" mode books an ordinary city ride | `vehicle_selector.dart:33–54`, `home_screen.dart:85,455–472`, `app_state.dart:496–509`, `intercity.ts:16–463` | A whole vertical is dead inventory; riders selecting "travel" silently get a city trip | Yes | confirmed |
| F-20-02 | S1 | `paymentMethod:"card"` creates a paid-status booking that is never charged | `schemas.ts:122`, `intercity.ts:105–171`, `payments.ts:12–18,213–220`, `0003:94–106` | Free seats; unbounded revenue loss the day intercity ships | No (latent) | confirmed |
| F-20-03 | S2 | A cancelled and refunded booking can be flipped to `boarded` | `intercity.ts:386–389` vs `:260–277` | Refund plus a free ride; vehicle oversold beyond `seats_total` | No (latent) | confirmed |
| F-20-04 | S2 | QR verification is optional in the API and impossible in the apps | `intercity.ts:383–385`; no QR package in any `pubspec.yaml` | Boarding control is theatre; anyone can claim any booking | No (latent) | confirmed |
| F-20-05 | S2 | Seat claim and booking insert are not atomic and have no compensation | `intercity.ts:116–145` | Orphaned seat holds permanently shrink saleable inventory | No (latent) | confirmed |
| F-20-06 | S2 | No captain intercity surface exists; three endpoints have no consumer | `intercity.ts:326,340,367`; zero hits in `apps/captain/**` | An assigned captain cannot see who is travelling or board them | No (latent) | confirmed |
| F-20-07 | S2 | Schedules are never closed out — no code sets `departed`/`completed`/`cancelled` | `0003:88` vs whole of `intercity.ts`; `:332` | Departed trips stay in captain and admin views forever; no completion accounting | No (latent) | confirmed |
| F-20-15 | S1 | Every employee trip is auto-billed to the employer with no opt-in and no policy check | `trips.ts:431–436,477–479,993` | Personal trips charged to companies; no corporate customer can accept this | **Yes** | confirmed |
| F-20-16 | S1 | Invoice period predicates are string-based; manual and cron bill different trip sets, and the flag-clearing UPDATE clears trips it never billed | `companies.ts:174–196`, `index.ts:343–364` — reproduced in SQLite | Over-billing, silent permanent revenue loss, two irreconcilable invoice paths | **Yes** | confirmed |
| F-20-17 | S1 | `spend_limit_month`, `allowed_vehicle_types`, `allowed_hours`, `credit_limit` are never enforced anywhere | grep across `apps/api/`; only `companies.ts:27–28,76,128` | Every corporate spend control the product advertises is inert | **Yes** | confirmed |
| F-20-18 | S2 | The one spend check that exists is bypassable by changing cost centre and ignores the pending fare | `companies.ts:39–51` | Limits are advisory even where they run | Yes (on a dead path) | confirmed |
| F-20-19 | S2 | Any employee can read all company invoices and the last 100 company trips with addresses | `companies.ts:217–239`; `0003:126–136` has no role column | Colleagues' and executives' movement history exposed internally | **Yes** | confirmed |
| F-20-20 | S2 | Invoices have no line items and no trip→invoice link; the only marker is then zeroed | `0003:144–154`, `companies.ts:193`, `index.ts:361` | A billing dispute cannot be answered; no audit trail | **Yes** | confirmed |
| F-20-21 | S2 | No VAT, no ETA e-invoice fields, no signature; `tax_id` captured but unused | `0003:113–124,144–154` | Invoices are not legally issuable to an Egyptian company | **Yes** | confirmed |
| F-20-22 | S2 | Invoices are not collectible; `paymob_order_id` never written or read, no status transitions | `0003:152`; grep across `apps/api/` | Revenue is recognised on paper and never collected | **Yes** | confirmed |
| F-20-23 | S2 | Employee binding takes a raw user id with no existence check, invitation or consent | `companies.ts:122–142` | Silent enrolment of a person's account into corporate billing; dangling rows on typo | **Yes** | confirmed |
| F-20-27 | S2 | No admin console for either vertical | `App.tsx:50–59`; zero `intercity`/`compan` in `admin.ts` | Both businesses are operated by hand-written curl | **Yes** | confirmed |
| F-20-08 | S3 | Full refund permitted up to the departure instant, no fee, no window | `intercity.ts:220–224,254–256,281–294` | A committed vehicle can be emptied minutes before departure | No (latent) | confirmed |
| F-20-09 | S3 | Intercity pricing is flat `base_price × seats`; bypasses bidding and has no occupancy curve | `intercity.ts:99–102` | No yield management on the vertical most sensitive to it | No (latent) | confirmed |
| F-20-10 | S3 | Missing route row yields `fare = 0` rather than an error | `intercity.ts:99–102` | Free bookings on a data-integrity failure | No (latent) | confirmed |
| F-20-11 | S3 | Intercity and company money columns are `REAL` while core currency moved to integer piastres in 0005 | `0003:74,101,120,131,150`; `migrations/0005_integer_currency_and_idempotency.sql` | Float rounding in fares and invoice totals; inconsistent with the ledger | **Yes** | confirmed |
| F-20-12 | S3 | `PATCH /intercity/admin/routes/:id` has no schema validation, unlike the POST | `intercity.ts:418–431` vs `schemas.ts:102–109` | Negative or non-numeric `base_price` accepted | No (latent) | confirmed |
| F-20-13 | S3 | Captain assignment validates nothing — not role, not verification, not availability, not capacity | `intercity.ts:447–453`; `0002:83–88` has no capacity column | Schedules assignable to non-captains or to a car too small for the seats sold | No (latent) | confirmed |
| F-20-24 | S3 | Invoice generation is not idempotent; no unique constraint on (company, period) | `companies.ts:167–205`; `0003:144–156` | Duplicate and zero-value invoices on retry | **Yes** | confirmed |
| F-20-25 | S3 | `scripts/generate_pdf.py` is a project pitch renderer with a hardcoded Windows font path, not an invoice generator, and is referenced by nothing | `scripts/generate_pdf.py:26–31`; grep | The assumed PDF capability does not exist | **Yes** | confirmed |
| F-20-26 | S3 | `POST /companies/trip` reads as an authorisation gate but creates nothing and is called by nobody | `companies.ts:14–65` | Misleads the next engineer into believing limits are enforced | **Yes** | confirmed |
| F-20-28 | S3 | Intercity bookings cannot be billed to a company — no `company_id` on the table | `0003:94–106` | The most obvious Egyptian B2B use case (staff travel between governorates) is unsupported | No (latent) | confirmed |
| F-20-29 | S3 | `الشحن` (freight) and `تروسيكل` are advertised in the rider UI as "قريباً" with no backend of any kind | `vehicle_selector.dart:29–54` | Demand signalled to users the platform cannot serve | **Yes** | confirmed |
| F-20-30 | S4 | `no_show` booking status is defined but never set | `0003:103`; grep of `intercity.ts` | No-show cannot be recorded, so it cannot be priced or penalised | No (latent) | confirmed |
| F-20-31 | S4 | Public route search uses unanchored `LIKE %from%` with no pagination on routes | `intercity.ts:19–31` | Unindexed scans as the route table grows; noisy matches | No (latent) | confirmed |

**Deliberately not raised.** I drafted an S1 alleging that `companyRoutes.use("/admin/*")`
(`companies.ts:68`) fails to guard the bare `POST /admin` and `GET /admin` routes at
`:70` and `:99`, which would let any authenticated rider create companies and enumerate
every corporate customer. I tested it against real `hono@4.12.33` before writing it up:
the wildcard **does** cover the bare path and `requireRole("admin")` runs on all four
routes. The finding was wrong and is withdrawn.

---

### S1 — expanded

#### F-20-01 · The intercity vertical has no front door

`intercity.ts` is 463 lines of working, reasonably careful code. Three tables, twelve
endpoints, a correct concurrency guard, an idempotent cancellation path with wallet
compensation, audit logging on both booking and cancel. It has never served a request
from a Synaptic Go user, and it cannot, because nothing in either app knows the URLs.

The trace is short. `vehicle_selector.dart:33–54` offers `intercity` as a selectable
category. `home_screen.dart:85` turns that into `_isTravelMode`. That boolean's entire
effect is choosing which bottom bar to mount (`:527–543`). The continue action calls
`_showBookingFlow()` (`:455–472`) which constructs a `FareEstimateSheet` **without
passing the category**, and that sheet submits through `app_state.dart:496–509` to
`POST /trips` with `'city': 'cairo'` hardcoded and no seat, schedule or route field.

What makes this worse than dead code is that it is *reachable* dead code with a
misleading label. A rider in Cairo who wants to get to Alexandria taps "سفر", enters
Alexandria as the destination, and gets an ordinary city-ride request broadcast to
nearby captains at city pricing. Either no captain accepts and the rider concludes the
product does not do intercity, or one does and the platform has just dispatched an
unpriced 220 km trip through a matching engine designed for 8 km ones.

The fix is not "delete the backend". The backend is the more finished half. The fix is to
wire the client, and to do the P0 corrections in §6.1 as part of that wiring rather than
after it.

#### F-20-02 · Card bookings are never charged

`schemas.ts:122` accepts `card`. `intercity.ts:105–112` pre-checks funds only for
`wallet`. `intercity.ts:149–171` debits only for `wallet`. There is no `card` branch
anywhere in the booking handler, and `intercity_bookings` has no payment-status column
at all (`0003:94–106`) — so a booking cannot even represent "awaiting payment".

There *is* a Paymob path with an intercity purpose, and it is worth being precise about
why it does not close the gap. `payments.ts:12–18` defines the intention schema:

```ts
const intentionSchema = z.object({
  amount: z.number().min(1),
  currency: z.string().default("EGP"),
  paymentMethod: z.enum(["card", "wallet", "cash"]).default("card"),
  purpose: z.enum(["wallet_topup", "trip_payment", "intercity_booking"]).default("wallet_topup"),
  tripId: z.string().optional(),
});
```

There is no `bookingId` field. The webhook branch (`payments.ts:213–220`) is candid
about the consequence:

```ts
} else if (intention.purpose === "intercity_booking") {
  // Audit row only; seat accounting lives in intercity_bookings.
  await c.env.DB.prepare(
    `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, status, created_at)
     VALUES (?, ?, 'intercity_booking', 'debit', ?, ?, ?, 'settled', datetime('now'))`,
  )
```

Compare the `trip_payment` branch immediately above it (`:197–206`), which does
`UPDATE trips SET payment_status = 'paid'`. The intercity branch has no equivalent
because there is no column to write and no id to write it against.

So the day intercity ships: a rider books with `card`, receives `{ok:true, status:"booked"}`
and a QR token, holds a seat, and owes nothing. Nothing reconciles. Nobody finds out
until someone manually compares seat counts to Paymob settlements. Additionally the
intention `amount` is client-supplied with no server check against `booking.fare`, so
even a rider who does complete a payment can choose to pay 1 EGP — that half of the
problem belongs to T04 and is routed in §9.

#### F-20-15 · Employees cannot separate work from personal travel

`trips.ts:431–436` resolves any active company binding for the rider on every trip
creation, and `:477–479` writes `billed_to_company = emp ? 1 : 0`. There is no request
field that influences this. The rider app does not send one — it has no corporate UI at
all — and even if it did, the handler does not read one.

At completion the flag actively suppresses personal payment (`trips.ts:993`):

```ts
if (trip.payment_method === "wallet" && !trip.billed_to_company && trip.rider_id) {
```

An employee who deliberately selects their own wallet to pay for a Friday-night personal
trip is not debited. The company is billed instead, and the trip's pickup and dropoff
addresses land in a portal any colleague can read (F-20-19).

This is the finding most likely to lose the first corporate customer, and it is live
today rather than latent. No procurement department will accept a corporate travel
account that captures 100% of an employee's personal movement and spend. The industry
norm — Uber for Business, Careem for Business — is a per-trip profile switch with
business as an explicit choice, and it is the first thing a buyer checks.

#### F-20-16 · The invoice period is computed three different ways, and money falls through the gaps

Both invoice paths build their bounds as JavaScript ISO strings — `"2026-07-01T00:00:00.000Z"`
(`companies.ts:170–171`, `index.ts:340–341`) — and compare them against `created_at`
values that D1 writes with `datetime('now')`, i.e. `"2026-07-15 09:00:00"`: a space
separator, no `T`, no `Z`. Under SQLite's string comparison, `' '` (0x20) sorts before
`'T'` (0x54), so the comparison is wrong exactly on the boundary days — and only there,
which is why it survives casual testing.

I reproduced it rather than reasoning about it. Four trips for one company, spanning the
boundaries, with the real column shapes and the real bounds:

```
Trips: t1 = 2026-07-01 09:00 (100), t2 = 2026-07-15 09:00 (200),
       t3 = 2026-07-31 23:00 (300), t4 = 2026-08-01 01:00 (400)
Bounds: start = 2026-07-01T00:00:00.000Z   end = 2026-08-01T00:00:00.000Z

companies.ts:176  SELECT (raw string compare)   -> rows [t2, t3, t4]  total 900.0
index.ts:346      SELECT (datetime() normalised) -> rows [t1, t2, t3]  total 600.0
index.ts:361      UPDATE clears                  -> rows [t2, t3, t4]
```

Three separate defects fall out of that output:

1. **The manual endpoint over-bills.** It charges the customer 900 EGP for a month whose
   true total is 600 — it drops t1 (a trip genuinely inside the period) and imports t4
   (a trip from the *next* period). An operator clicking "generate invoice" produces a
   materially different document from the one the cron would produce for the same month.
2. **The cron silently loses revenue.** Its SELECT bills `{t1,t2,t3}` but its UPDATE
   clears `{t2,t3,t4}`. t4 was never invoiced and yet its `billed_to_company` flag is
   now `0`, so it will never be picked up by any future run. Every trip taken on the 1st
   of a month before the 03:00 cron is written off. On a fleet of any size that is a
   recurring, invisible leak.
3. **t1 is billed but never cleared**, leaving rows flagged as unbilled that no future
   period will ever match — the flag no longer means anything reliable.

The root cause is that `billed_to_company` is being used as billing state at all. A
boolean that gets destructively rewritten by the process that reads it cannot survive a
partial failure, a retry, or two implementations. The fix in §6.2 replaces it with an
`invoice_id` foreign key and normalised timestamps.

#### F-20-17 · Every corporate spend control is inert

The schema captures four policy fields — `spend_limit_month`, `allowed_vehicle_types`,
`allowed_hours` on `company_employees` (`0003:130–133`) and `credit_limit` on `companies`
(`0003:120`). `companySchema` and `companyEmployeeSchema` validate them
(`schemas.ts:125–142`). An admin can set them.

Grepping the entire `apps/api/` tree for those four names returns hits in exactly three
places: the `SELECT` list at `companies.ts:27–28`, and the `INSERT` column lists at
`:76` and `:128`. They are written and they are read into a variable. They are never
compared to anything.

`allowed_hours` in particular is stored as a JSON range and never parsed, so the
"employees may only take corporate rides 08:00–20:00 on weekdays" policy that a customer
will absolutely ask for in their first meeting is a string sitting in a column.

The only limit logic in the codebase is in `POST /companies/trip`, which does not create
a trip (`companies.ts:53–54`) and which no client calls. So the honest summary for a
buyer is: the platform can *record* your spend policy and can *display* it back to you,
and will not apply it.

### S2 — expanded

#### F-20-03 · Boarding a cancelled booking

`intercity.ts:386–389` is the whole boarding write:

```ts
if (booking.status === "boarded") return c.json({ ok: true, already: true });
await c.env.DB.prepare(`UPDATE intercity_bookings SET status = 'boarded' WHERE id = ?`)
  .bind(bookingId)
  .run();
```

The short-circuit covers `boarded`. It does not cover `cancelled` or `no_show`, and the
`UPDATE` carries no `AND status = 'booked'` guard — which is conspicuous because the
cancel path two hundred lines earlier does exactly that (`:260–268`) and comments on why.

The sequence that hurts: rider books a wallet seat, cancels before departure, is refunded
in full and has the seat released back to inventory (`:271–294`). That released seat is
resold. The rider then presents at the vehicle; the captain — who has no way to know,
since the passenger list filters on `status != 'cancelled'` at `:358` but the captain has
no app anyway — boards them by id. The booking flips to `boarded`. The rider has their
money back and a seat, and the vehicle now carries `seats_total + 1` passengers.

#### F-20-04 · QR verification cannot work, in two independent ways

First, the API makes it optional (`intercity.ts:383–385`):

```ts
if (body.qrToken && body.qrToken !== booking.qr_token) {
  return c.json({ error: "Invalid QR", code: "QR_MISMATCH" }, 400);
}
```

An empty body satisfies this. The check only runs if the caller volunteers a token, so
"verify this passenger" degrades to "assert this passenger" whenever the client omits a
field.

Second, and more fundamentally, no client can produce or consume the token. Neither
`apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml` nor
`packages/flutter_shared/pubspec.yaml` declares `qr_flutter`, `mobile_scanner` or any
equivalent. The string `qrToken` appears nowhere outside `intercity.ts`. The token is
generated with good entropy (`utils.ts:9–12`, `crypto.randomUUID()`), returned in the
booking response, exposed on the manifest (`:355`) — and has no path to a screen or a
camera.

Worth stating plainly for planning: adding QR is a dependency addition plus two screens.
It is not hard. It is simply not started, and the API was written as though it were done.

#### F-20-05 · Orphaned seat holds

`intercity.ts:116–124` claims the seats. `:128–145` inserts the booking. Between them
there is no transaction and no compensation. If the `INSERT` throws — a `qr_token`
uniqueness collision, a D1 timeout, a worker eviction — the counter has already been
incremented and nothing decrements it. That inventory is gone until someone edits the
row by hand.

The author clearly understood the risk, because the wallet branch immediately below does
compensate properly on failure (`:156–163`, deleting the booking and releasing the
seats). The gap is the window before the booking row exists. On D1 the clean fix is
`batch()` so the claim and the insert land as one transaction; §6.1 specifies it.

#### F-20-06 · The captain half of intercity was never built

Three endpoints exist and are correctly authorised: the captain's own schedules
(`:326`), the passenger manifest with ownership check (`:340–352`), and boarding
(`:367`). Zero lines of captain-app code reference any of them — verified by grepping
every downloaded captain screen and service, not by search index.

There is also no scanner dependency (F-20-04) and no manifest screen. So the operational
reality of an intercity departure today would be: the admin assigns a captain by curl,
the captain receives a push notification (`:454–461`) telling them to "open the captain
app for trip details and booked seats", and the captain app has no such screen.

#### F-20-07 · Schedules never end

`0003:88` permits `open`, `boarding`, `departed`, `cancelled`, `completed`. Only `'open'`
is ever written, at insert (`intercity.ts:440`). Nothing transitions a schedule — there
is no cron entry for it (`wrangler.toml:62–65` has only scheduled-trip dispatch and the
monthly invoice), no admin endpoint, and no captain action.

Consequences compound: the captain manifest query filters `status IN ('open','boarding')`
(`:332`) so yesterday's departures stay in the list indefinitely; booking is blocked only
by the `depart_at` timestamp check (`:95–97`) rather than by state; there is no
`completed` event to hang settlement, captain payout or no-show accounting on; and
`seats_booked` is never reconciled against who actually boarded.

#### F-20-19 · The company portal has no notion of a company admin

`companies.ts:217–239`. The route is guarded by `authMiddleware` only. The handler's sole
authorisation check is `:220–225`:

```ts
const emp = await c.env.DB.prepare(
  `SELECT company_id FROM company_employees WHERE user_id = ? AND active = 1 LIMIT 1`,
).bind(user.id).first<{ company_id: string }>();
if (!emp) return c.json({ error: "لا تملك صلاحية بوابة الشركة", code: "NO_COMPANY" }, 403);
```

Any active employee passes. The response then includes the company's entire invoice
history and its last 100 trips with `pickup_address`, `dropoff_address`, `cost_center`,
fare and status (`:231–238`).

`company_employees` has no role column (`0003:126–136`), so this cannot be fixed by
tightening the query — the concept does not exist in the schema. Every corporate account
is therefore either fully transparent to all its staff or unusable. §6.2 adds the role.

#### F-20-20 · An invoice cannot be substantiated

`company_invoices` stores `total_trips` and `total_amount` and nothing else
(`0003:144–154`). The only association between a trip and an invoice is the
`billed_to_company` flag, which the invoice run then sets to `0`
(`companies.ts:193`, `index.ts:361`).

After a run completes there is no query that answers "which trips are on invoice
`inv_x`?". Not a slow query — no query. The information was destroyed by the act of
invoicing. Combined with F-20-16's mismatched row sets, a customer disputing a total
cannot be answered, and the platform cannot even reconstruct its own arithmetic.

#### F-20-21 · The invoice is not legally issuable in Egypt

Egypt's standard VAT rate is 14% (PwC Tax Summaries, Egypt — confident), and the
Egyptian Tax Authority operates a **pre-clearance** e-invoicing regime: a B2B invoice is
submitted to the ETA platform, validated, and assigned a UUID *before* it is issued to
the customer. Paper invoices ceased to be valid for VAT deduction from 1 July 2023, and
B2B coverage was extended to all taxpayers through 2023–2024 (ETA SDK documentation and
Avalara's Egypt tracker — confident on the mechanism and the required fields; treat the
exact phase dates as directional and confirm with counsel).

A compliant invoice must carry, at minimum: issuer type/id (tax registration number),
issuer activity code and branch, receiver type/id, `documentType`/`documentTypeVersion`,
`dateTimeIssued`, an internal document id, at least one invoice line with per-line VAT,
`taxTotals`, the ETA-assigned UUID, and a CAdES-BES digital signature from an X.509
eSeal certificate.

`company_invoices` has: id, company_id, period_start, period_end, total_trips,
total_amount, status, paymob_order_id, created_at. It has no tax fields, no lines, no
UUID, no signature, no currency and no issue/due dates. `companies.tax_id` is captured
(`0003:117`) and used nowhere.

Two consequences for planning. The eSeal certificate is a **procurement** item with
external lead time, not a coding task — it should be started before the engineering. And
because ETA assigns the UUID synchronously, invoice issuance becomes an operation that
can fail and must be retryable, which the current fire-and-forget cron is not shaped for.

#### F-20-22 · Nothing collects the money

`company_invoices.paymob_order_id` (`0003:152`) is never written or read — grep across
`apps/api/` returns zero occurrences outside the DDL. The `status` CHECK permits `paid`
and `overdue` and no code performs either transition. `credit_limit` is not enforced
(F-20-17), so there is no exposure ceiling either.

The end state is a table of invoices that were never delivered to the customer, cannot be
paid through the platform, never age into `overdue`, and trigger no dunning. Revenue is
recognised in a row and collected by nobody.

#### F-20-23 · Silent enrolment

`companies.ts:122–142` inserts a `company_employees` row from a raw `userId` with no
`EXISTS` check against `users`, no invitation, and no acceptance step. Two failure modes:
a mistyped id creates a binding to a non-existent user that will never match a trip and
will sit in the table looking active; a correct id enrols a real person's account into
corporate billing without their knowledge — and given F-20-15, every trip they take from
that moment is billed to the company and visible to their colleagues.

#### F-20-27 · Both businesses are operated by hand

Ten admin routes (`App.tsx:50–59`), none for either vertical, and `admin.ts` has no
endpoint for either. To run intercity an operator must POST a route, POST each schedule,
and POST an assignment with a captain id they looked up themselves; to run B2B they must
POST a company, look up each employee's user id, POST each binding, and POST each
invoice. There is no list view, no occupancy view, no manifest, no invoice history and no
way to correct a mistake short of a direct D1 statement.

This is the finding that most limits the *other* fixes: even after the P0 work, nobody
can operate these verticals daily without §6.4's consoles.

## 5. Benchmark gap

### 5.1 Intercity

**Swvl** is the reference for this exact market and the closest analogue to what
Synaptic Go has built. Their Egyptian intercity product runs scheduled fixed routes
between governorates with fixed per-seat pricing — Cairo–Alexandria shows a single
evening departure at EGP 350 per person (swvl.com intercity pages — confident). Their
own filings describe seats as managed inventory and report seat utilisation rising from
74% (FY2020) to 96% (FY2022) with pricing algorithms responding to route, time of day
and demand (SEC Form 20-F/A FY2022 — confident).

That utilisation number is the benchmark that matters. Synaptic Go's model —
`base_price × seats`, fixed forever, set by hand per route (`intercity.ts:99–102`) — has
no mechanism to move utilisation at all. Swvl's commercial history is the cautionary
half: a March 2022 SPAC listing, an $82.4M operating loss and $123.6M net loss in FY2022,
450+ layoffs that July, five acquisitions in eighteen months followed by divestitures,
and a near-delisting — before a hard pivot to B2B/enterprise TaaS that produced their
first profit ($1.3M net on $24.2M revenue) in FY2025 (Nasdaq releases and SEC filings —
confident). The lesson a small team should take is not "avoid intercity"; it is that
route-level unit economics must clear before any central overhead is added, and that
**their profitable end state was the B2B one**.

**inDrive** takes the opposite architectural position, and it is the one that fits
Synaptic Go's stated differentiator. Their "City to City" product has no schedules, no
seat inventory and no fixed prices: the rider posts a route, date and optional suggested
price; drivers already travelling that corridor respond with offers; the rider picks on
price, rating and vehicle (intercity.indrive.com — confident). It is a marketplace, not a
timetable. Capital and operational overhead are near zero, and reliability is the
trade-off.

Synaptic Go has built the Swvl shape — schedules, seat counters, fixed prices, assigned
captains — while its whole product thesis is the inDrive shape. Nothing in the intercity
code touches the bidding engine. That is the strategic gap, and §10's first open question
puts it to the product owner rather than deciding it here.

**Boarding.** Swvl's boarding confirmation is app-presented; I could not confirm from
primary sources that it is specifically a QR scan (assumed). Either way, both references
have a working two-sided flow — a passenger artefact and a driver surface that reads it.
Synaptic Go has a token with neither end implemented (F-20-04).

### 5.2 B2B

**Uber for Business** is the concrete feature checklist a corporate buyer will hold
Synaptic Go against (Uber Business product and help pages — confident):

| Capability | Uber for Business | Synaptic Go today |
|---|---|---|
| Business vs personal per trip | Employee selects a programme before each ride | **None** — all trips auto-billed (F-20-15) |
| Time-of-day / day-of-week rules | Configurable, multiple ranges | Column exists, never read (F-20-17) |
| Location rules | Allowed/blocked pickup–dropoff, radius | Not modelled |
| Vehicle-class restriction | Configurable | Column exists, never read (F-20-17) |
| Spend caps per trip/day/month | Enforced; overage falls to personal card | Column exists, never read (F-20-17) |
| Trip-count caps | Yes | Not modelled |
| Expense codes / cost centres | Required selection, feeds GL | Column exists; set from the binding, never chosen by the rider |
| Expense-tool integrations | Navan, Ramp, SAP Concur, Expensify, Brex, Coupa, Zoho and others | None |
| Centralised billing | Yes, with personal-card fallback | Yes, without the fallback |
| Reporting | Dashboard with spend, usage, compliance, CO₂ | None |

**Careem for Business** — the regional incumbent, ~200 corporate clients as of mid-2025 —
advertises one dashboard across rides, food, grocery, courier and shops; spend limits by
employee, time window, day and geography; itemised real-time reporting with user
justifications; a single consolidated monthly invoice with payment terms; and a dedicated
commercial manager per account (careem.com C4B — confident). Notably I found no evidence
of Concur/Expensify-style API integrations on their B2B page (assumed gap), which is the
one place Uber is clearly ahead regionally and therefore the one place a new entrant
does *not* need to compete on day one.

Where Synaptic Go actually sits: it has the data model for cost centres, spend limits,
vehicle policy and hours — genuinely more schema than most products have at this stage —
and enforces none of it, cannot produce a compliant invoice, cannot collect one, and
cannot show the customer a single report. The gap to a first paying corporate customer is
not conceptual, it is a fortnight of enforcement plumbing plus the compliance work.

### 5.3 Delivery and other verticals

**Careem's** sequence is the reference path: rides from 2012, food delivery in 2018,
super-app consolidation in 2020, dark-store grocery and a licensed wallet in 2022, with a
$400M e& investment in 2023 partly funding the expansion (careem.com "building the
everything app" — confident on the timeline; the organisational cost is not publicly
broken out — assumed). Delivery came six years after rides and after substantial capital.

**The Egyptian delivery market is not empty.** Food and q-commerce are held by Talabat
(~25,000 couriers across 25 cities by late 2024), Mrsool and Breadfast; e-commerce
last-mile by Bosta, Mylerz, Aramex and the global integrators (Ken Research Egypt CEP
market, Nov 2025, and Egyptian delivery-sector reporting — confident on the players,
directional on the workforce shares).

Two market facts should shape any scoping. **Cash on delivery dominates** — COD is among
the top two payment methods for Egyptian online purchases, with one aggregated source
putting it near 60% in 2022 (Statista Consumer Insights is confident on the ranking; the
60% figure is assumed and should be verified). COD is not a payment detail, it is an
operating model: courier float, doorstep refusal, returns handling and daily cash
settlement back to the merchant. And **motorcycles are the default vehicle** for
last-mile in Egyptian cities across every major platform.

Which runs directly into the regulatory finding. **Law 87 of 2018** governs app-based
ride-hailing in Egypt and covers **passenger cars only** — the Transport Committee stated
during the parliamentary debate that motorbikes and tuk-tuks were deliberately excluded
because only cars met the safety standards (Mada Masr, 7 May 2018 — confident).
Motorcycle ride-hailing is therefore not licensed under the national framework; operators
such as Halan work under other arrangements. Tuk-tuks got their own licensing route via a
March 2024 traffic-law amendment, with a new light-quadricycle category created as the
main-road alternative (Egypt Independent, March 2024 — confident).

The practical reading: a motorcycle **delivery** fleet is ordinary commercial logistics
and is unproblematic. A motorcycle **passenger** class sits outside Law 87 and needs its
own legal opinion before a line of code is written. That asymmetry is what drives the
recommendation in §6.3 and §10.

## 6. Improvement plan

Ordered by the sequence I would actually execute. Migration numbers continue from 0019,
the highest on `main`.

### 6.1 Intercity — make it real or retire it

Everything in 6.1 assumes the product owner answers Q1 in §10 with "keep scheduled
intercity". If the answer is the inDrive model instead, P0.1–P0.4 still apply (they are
correctness fixes to code that would be reused), and P1.5 is replaced by the bidding
integration sketched in §10.

#### P0.1 — Wire the rider client to the intercity API, or hide the entry point

- **Goal** — a rider who selects "سفر" either books a real seat or is told the service is
  not available yet. Not silently issued a city ride.
- **Design** — two-stage. **Stage A, same day:** set `enabled: false` on the `intercity`
  category in `vehicle_selector.dart:33–54`, matching the treatment already used for
  `freight` and `tuktuk`, so the chip shows "قريباً" and cannot be tapped. This is a
  three-line change that stops the misrouting immediately. **Stage B:** build the real
  flow — route search (`GET /intercity/routes?from=&to=`), departure list
  (`GET /intercity/schedules?routeId=&date=`), a seat-count and station picker, booking
  submission, and a ticket screen rendering `qrToken`. Add `qr_flutter` to
  `apps/rider/pubspec.yaml`. Point the travel-mode "orders" tab at
  `GET /intercity/bookings` instead of `HistoryScreen` (`home_screen.dart:535`).
- **Files to change** — `apps/rider/lib/screens/home/vehicle_selector.dart`,
  `home_screen.dart`, new `apps/rider/lib/screens/intercity/{route_search,schedule_list,seat_picker,ticket}_screen.dart`,
  `apps/rider/lib/services/app_state.dart`, `apps/rider/pubspec.yaml`.
- **DB** — none.
- **API contract** — none new; consume the twelve existing endpoints.
- **Effort** — Stage A: S (under an hour). Stage B: L.
- **Risk** — low for Stage A. For Stage B, the risk is shipping the client before P0.2–P0.4
  land, which would expose the payment and boarding defects to real users. Sequence them
  together.
- **Acceptance criteria** — selecting "سفر" never results in a `POST /trips`; a booking
  made in the app appears in `GET /intercity/bookings`; the ticket screen renders a QR
  encoding `qrToken`.
- **Tests** — widget test asserting the intercity path calls `/intercity/bookings`; an
  integration test booking and then cancelling.

#### P0.2 — Close the card-payment hole

- **Goal** — no booking can hold a seat without either being paid or being explicitly
  marked cash-on-boarding.
- **Design** — add `payment_status` to `intercity_bookings` (`pending|paid|failed|refunded`)
  and `payment_ref`. Add `bookingId` to `intentionSchema` (`payments.ts:12–18`) and a
  `booking_id` column on `payment_intentions`. In the booking handler, `card` creates the
  booking with `payment_status='pending'` and a short hold TTL; the Paymob webhook branch
  at `payments.ts:213–220` sets `payment_status='paid'` against the booking id, mirroring
  what `trip_payment` already does at `:197–206`. The webhook must also verify the settled
  amount equals `booking.fare` before marking paid. Add a sweeper to the existing
  every-minute cron that releases seats for `pending` bookings older than the TTL.
- **Files to change** — `apps/api/src/routes/intercity.ts`,
  `apps/api/src/routes/payments.ts`, `apps/api/src/lib/schemas.ts`,
  `apps/api/src/index.ts`.
- **DB** — `migrations/0020_intercity_payment_status.sql`:
  ```sql
  ALTER TABLE intercity_bookings ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'paid';
  ALTER TABLE intercity_bookings ADD COLUMN payment_ref TEXT;
  ALTER TABLE intercity_bookings ADD COLUMN hold_expires_at TEXT;
  ALTER TABLE payment_intentions ADD COLUMN booking_id TEXT;
  CREATE INDEX IF NOT EXISTS idx_int_book_payment ON intercity_bookings(payment_status, hold_expires_at);
  ```
  The `DEFAULT 'paid'` is deliberate: existing rows are wallet/cash and already settled.
- **API contract** — `POST /payments/paymob/intention` gains optional `bookingId: string`.
  `POST /intercity/bookings` response gains `paymentStatus` and, for `card`,
  `holdExpiresAt`.
- **Effort** — M.
- **Risk** — a webhook that fails to arrive strands a seat until the sweeper runs; keep
  the TTL short (10 minutes) and make the sweeper idempotent. Rollback is to stop offering
  `card` in the client.
- **Acceptance criteria** — a `card` booking with no completed payment holds no seat after
  the TTL; a settled webhook for a mismatched amount does not mark the booking paid.
- **Tests** — unit test for the sweeper; a webhook test with amount mismatch; a test that
  a `wallet` booking is unaffected.

#### P0.3 — Guard the boarding transition

- **Goal** — only a live booking can be boarded, and boarding is a verified act.
- **Design** — make the update conditional and require the token when the client can
  supply one. Replace `intercity.ts:386–389` with a guarded write:
  ```sql
  UPDATE intercity_bookings SET status = 'boarded', boarded_at = ?
   WHERE id = ? AND status = 'booked'
  ```
  and return 409 when `changes === 0`, distinguishing `cancelled` from `already boarded`
  by re-reading. Change the QR check at `:383` from optional to required unless the caller
  passes an explicit `manualOverride: true` with a reason, which is written to the audit
  log — captains do need a manual path for a dead phone, but it should be recorded rather
  than being the default.
- **Files to change** — `apps/api/src/routes/intercity.ts`.
- **DB** — `migrations/0021_intercity_boarding_audit.sql`: add `boarded_at TEXT`,
  `boarded_by TEXT`, `board_override_reason TEXT` to `intercity_bookings`.
- **API contract** — `POST /intercity/captain/board/:bookingId` body becomes
  `{ qrToken?: string, manualOverride?: boolean, reason?: string }`; returns 409
  `BOOKING_NOT_BOARDABLE` for cancelled/no-show.
- **Effort** — S.
- **Risk** — negligible. Requires P0.1 Stage B / P1.1 for the scanner to exist, so ship the
  status guard now and the mandatory-QR half with the captain screen.
- **Acceptance criteria** — boarding a cancelled booking returns 409 and does not change
  status; every override carries a reason in `audit_log`.
- **Tests** — cancel-then-board returns 409; double-board is idempotent.

#### P0.4 — Make the seat claim atomic

- **Goal** — a failed insert cannot strand inventory.
- **Design** — replace the two sequential statements at `intercity.ts:116–145` with
  `env.DB.batch([claim, insert])`, which D1 executes as one transaction. Keep the
  `changes === 0` check on the claim result. The wallet debit stays separate with its
  existing compensation. Add a reconciliation query to the daily ops job that reports any
  schedule where `seats_booked` differs from the count of non-cancelled bookings.
- **Files to change** — `apps/api/src/routes/intercity.ts`, `apps/api/src/index.ts`.
- **DB** — none.
- **API contract** — unchanged.
- **Effort** — S.
- **Risk** — low; `batch()` is the documented D1 transaction primitive.
- **Acceptance criteria** — an induced insert failure leaves `seats_booked` unchanged; the
  reconciliation query returns zero drift after a load test.
- **Tests** — a test that forces a `qr_token` collision and asserts inventory is unchanged.

#### P0.5 — Validate the route PATCH and the fare fallback

- **Goal** — no negative or absent prices.
- **Design** — add `intercityRoutePatchSchema` (all fields from `intercityRouteSchema`
  made optional, same bounds) and run `parseBody` in the PATCH at `intercity.ts:418`.
  Change the fare computation at `:99–102` to fail closed: if the route row is missing or
  `base_price <= 0`, return 500 `ROUTE_MISCONFIGURED` rather than computing a zero fare.
- **Files to change** — `apps/api/src/lib/schemas.ts`, `apps/api/src/routes/intercity.ts`.
- **DB** — none.
- **API contract** — PATCH now returns 400 `VALIDATION_ERROR` on out-of-range values.
- **Effort** — S. **Risk** — none meaningful.
- **Acceptance criteria** — `basePrice: -5` is rejected; a booking against an orphaned
  route errors rather than being free.
- **Tests** — schema unit tests.

#### P1.1 — Captain intercity surface

- **Goal** — an assigned captain can see their departures, the manifest and board
  passengers.
- **Design** — three screens in the captain app: upcoming schedules
  (`GET /intercity/captain/schedules`), manifest
  (`GET /intercity/captain/schedules/:id/passengers`) and a scanner that posts to
  `POST /intercity/captain/board/:bookingId`. Add `mobile_scanner` to
  `apps/captain/pubspec.yaml`. Show seats sold vs total and a cash-to-collect subtotal.
  Build these against `packages/flutter_shared` components rather than duplicating rider
  widgets — see §9's note to T27.
- **Files to change** — new `apps/captain/lib/screens/intercity/{schedules,manifest,scanner}_screen.dart`,
  `apps/captain/lib/services/captain_state.dart`, `apps/captain/pubspec.yaml`, navigation.
- **DB** — none. **API contract** — none new.
- **Effort** — L.
- **Risk** — camera permissions on both platforms; needs a manual-entry fallback, which
  P0.3's override provides.
- **Acceptance criteria** — a captain sees only their own schedules; scanning a valid QR
  boards the passenger; scanning a cancelled booking shows a clear refusal.
- **Tests** — widget tests per screen; an ownership test asserting 403 on another
  captain's schedule.

#### P1.2 — Schedule lifecycle

- **Goal** — schedules close out, and departure is an event the system can act on.
- **Design** — extend the existing every-minute cron: move `open → boarding` at
  `depart_at − 30m`, `boarding → departed` at `depart_at`, and `departed → completed` at
  `depart_at + duration_minutes`. On `departed`, mark any still-`booked` bookings as
  `no_show` (which finally gives F-20-30's status a writer) and emit the captain
  settlement event. Add an admin endpoint to cancel a schedule, which must refund every
  wallet booking and notify every rider.
- **Files to change** — `apps/api/src/index.ts`, `apps/api/src/routes/intercity.ts`.
- **DB** — `migrations/0022_intercity_schedule_lifecycle.sql`: add
  `boarding_at`, `departed_at`, `completed_at`, `cancelled_at` to `intercity_schedules`;
  index on `(status, depart_at)`.
- **API contract** — `POST /intercity/admin/schedules/:id/cancel` →
  `{ ok, refunded: number, notified: number }`.
- **Effort** — M.
- **Risk** — the cron must be idempotent and bounded; use conditional updates keyed on the
  current status and cap rows per tick.
- **Acceptance criteria** — a schedule past `depart_at` is not `open`; cancelling refunds
  every wallet booking exactly once.
- **Tests** — time-travel tests over the transition table; a double-tick idempotency test.

#### P1.3 — Cancellation policy with a window

- **Goal** — protect a committed vehicle from late emptying without punishing genuine
  changes of plan.
- **Design** — tiered, configured per route rather than hardcoded: free until
  `depart_at − 6h`; 50% fee from 6h to 1h; no refund inside 1h. Store the tiers in
  `system_config` (the table exists — `migrations/0016_system_config.sql`) so ops can tune
  without a deploy. Return the applicable policy on the booking response and show it on
  the ticket screen before the rider confirms.
- **Files to change** — `apps/api/src/routes/intercity.ts`, rider ticket screen.
- **DB** — `migrations/0023_intercity_cancellation_policy.sql`: add
  `cancellation_fee_pct REAL`, `free_cancel_hours REAL` to `intercity_routes`; a
  `cancellation_fee` column on `intercity_bookings`.
- **API contract** — cancel response gains `feeCharged` and `policyApplied`.
- **Effort** — M.
- **Risk** — a refund policy change is customer-visible; announce it and apply only to
  bookings created after the deploy (store the policy snapshot on the booking).
- **Acceptance criteria** — a cancel 30 minutes before departure refunds nothing and says
  why; the fee is visible before booking.
- **Tests** — boundary tests either side of each tier.

#### P1.4 — Captain assignment validation

- **Goal** — a schedule cannot be assigned to someone who cannot serve it.
- **Design** — in `POST /intercity/admin/schedules/:id/assign`, verify the target is
  `role='captain'`, is verified/approved, has no overlapping assigned schedule in
  `[depart_at, depart_at + duration_minutes]`, and drives a vehicle whose capacity is at
  least `seats_total`. Capacity requires a new column on `vehicle_types`, which delivery
  needs anyway (§6.3).
- **Files to change** — `apps/api/src/routes/intercity.ts`.
- **DB** — `migrations/0024_vehicle_capacity.sql`:
  ```sql
  ALTER TABLE vehicle_types ADD COLUMN seat_capacity INTEGER NOT NULL DEFAULT 4;
  ALTER TABLE vehicle_types ADD COLUMN max_weight_kg REAL;
  ALTER TABLE vehicle_types ADD COLUMN max_volume_l REAL;
  UPDATE vehicle_types SET seat_capacity = 4 WHERE id IN ('economy','comfort');
  UPDATE vehicle_types SET seat_capacity = 6 WHERE id = 'xl';
  ```
- **API contract** — assign returns 400 `CAPTAIN_INELIGIBLE` / `CAPACITY_EXCEEDED` /
  409 `CAPTAIN_DOUBLE_BOOKED`.
- **Effort** — M. **Risk** — low.
- **Acceptance criteria** — assigning a rider id fails; assigning a 4-seat car to a
  6-seat schedule fails.
- **Tests** — one per rejection reason.

#### P2.1 — Occupancy-based pricing

- **Goal** — move utilisation toward the ~90% that makes the vertical viable.
- **Design** — price a seat as
  `base_price × occupancy_multiplier(seats_booked / seats_total) × time_multiplier(hours_to_departure)`,
  with both curves stored in `system_config`. Early and empty is cheaper; late and full is
  dearer. Snapshot the computed fare onto the booking (already the behaviour) so a later
  curve change never alters a sold ticket.
- **Files to change** — new `apps/api/src/lib/intercityPricing.ts`,
  `apps/api/src/routes/intercity.ts`.
- **DB** — config rows only.
- **API contract** — `GET /intercity/schedules` gains `currentSeatPrice`.
- **Effort** — M.
- **Risk** — visible price movement; cap the multiplier band (e.g. 0.8×–1.4×) and log every
  quote for later analysis.
- **Acceptance criteria** — two riders quoted at different occupancies see different
  prices; a sold booking's fare never changes.
- **Tests** — curve unit tests; a snapshot-immutability test.

#### P2.2 — Money columns to integers

- **Goal** — intercity and company money stop being floats.
- **Design** — follow the pattern 0005 already established for the core ledger: add
  `*_piastres INTEGER` columns alongside, dual-write, backfill, then read from the integer
  column. Covers `intercity_routes.base_price`, `intercity_bookings.fare`,
  `companies.credit_limit`, `company_employees.spend_limit_month`,
  `company_invoices.total_amount`.
- **Files to change** — `apps/api/src/routes/intercity.ts`, `companies.ts`, `index.ts`.
- **DB** — `migrations/0025_intercity_b2b_integer_currency.sql`.
- **Effort** — M. **Risk** — dual-write drift; keep both columns for one release and
  reconcile.
- **Acceptance criteria** — no float arithmetic remains on these paths; a reconciliation
  query shows zero drift.
- **Tests** — round-trip tests on fractional piastre values.

### 6.2 B2B — make the corporate product sellable

#### P0.6 — Business/personal choice per trip

- **Goal** — an employee decides which trips their employer pays for. This is the single
  change that turns the corporate product from unsellable to demoable.
- **Design** — `POST /trips` accepts `billTo: "personal" | "company"`, defaulting to
  **personal**. `trips.ts:431–479` only sets `company_id`/`billed_to_company` when
  `billTo === "company"` *and* an active binding exists *and* the policy check passes
  (P0.7). The rider app shows a business/personal toggle when a binding exists, with the
  cost-centre picker beside it.
- **Files to change** — `apps/api/src/routes/trips.ts`, `apps/api/src/lib/schemas.ts`,
  `apps/rider/lib/screens/home/fare_estimate_sheet.dart`,
  `apps/rider/lib/services/app_state.dart`.
- **DB** — none.
- **API contract** — `POST /trips` gains `billTo?: "personal"|"company"` and
  `costCenter?: string`; the response echoes `billedToCompany` so the client can display
  it.
- **Effort** — M.
- **Risk** — defaulting to personal changes existing behaviour for any live corporate
  pilot. Given F-20-15, that change is the point; flag it in release notes.
- **Acceptance criteria** — an employee's default trip is personally paid; choosing
  business tags the trip and appears on the invoice.
- **Tests** — matrix over {binding, no binding} × {personal, company, omitted}.

#### P0.7 — Enforce the spend policy that already exists in the schema

- **Goal** — the four policy fields do what the admin set them to do.
- **Design** — one `assertCompanyPolicy(env, userId, ctx)` helper in
  `apps/api/src/lib/companyPolicy.ts`, called from `POST /trips` when
  `billTo === "company"`. It checks, in order: company `status = 'active'`; the trip hour
  against `allowed_hours`; `vehicleTypeId` against `allowed_vehicle_types`;
  **employee month-to-date spend plus this trip's estimate** against `spend_limit_month`;
  and **company month-to-date spend plus this estimate** against `credit_limit`. Each
  failure returns a distinct code so the client can explain it and offer personal payment
  instead of a dead end. Fix the cost-centre bypass by scoping the spend sum to
  `user_id`, not `cost_center` (`companies.ts:39–51` is the wrong shape and should be
  deleted along with the dead endpoint).
- **Files to change** — new `apps/api/src/lib/companyPolicy.ts`,
  `apps/api/src/routes/trips.ts`, `apps/api/src/routes/companies.ts` (delete
  `POST /companies/trip`).
- **DB** — `migrations/0026_company_policy_indexes.sql`: index
  `trips(company_id, billed_to_company, created_at)` to keep the month-to-date sums cheap.
- **API contract** — `POST /trips` may return 403 with
  `COMPANY_HOURS_BLOCKED | COMPANY_VEHICLE_BLOCKED | COMPANY_SPEND_LIMIT | COMPANY_CREDIT_LIMIT | COMPANY_SUSPENDED`.
- **Effort** — M.
- **Risk** — a wrongly configured policy blocks a customer's staff; ship with an
  `enforce | warn` mode per company so a pilot can run in warn mode first.
- **Acceptance criteria** — a trip at 02:00 under an 08:00–20:00 policy is refused with
  the right code and the rider is offered personal payment; the limit cannot be reset by
  changing cost centre.
- **Tests** — one per rejection code; an explicit regression test for the cost-centre
  bypass.

#### P0.8 — Fix invoicing: one path, real line items, correct dates

- **Goal** — an invoice that is reproducible, reconcilable and impossible to double-count.
- **Design** — three changes that stand together.
  1. **Stop using `billed_to_company` as billing state.** Add `invoice_id` to `trips`.
     Invoicing sets `invoice_id`; it never clears `billed_to_company`. "Not yet invoiced"
     becomes `billed_to_company = 1 AND invoice_id IS NULL`, which is durable, idempotent
     and queryable after the fact.
  2. **Normalise the dates.** Every comparison uses `datetime(created_at) >= datetime(?)`
     on both the SELECT and the UPDATE — the bug in F-20-16 is precisely that they
     differed. Better still, pass bounds as SQLite-shaped strings from a single helper.
  3. **One implementation.** Extract `generateCompanyInvoice(env, companyId, periodStart,
     periodEnd)` into `apps/api/src/lib/invoicing.ts` and call it from both the cron and
     the admin endpoint, so they cannot drift again. Write `company_invoice_lines`, one
     row per trip. Guard with a unique index on `(company_id, period_start)`.
- **Files to change** — new `apps/api/src/lib/invoicing.ts`,
  `apps/api/src/routes/companies.ts`, `apps/api/src/index.ts`.
- **DB** — `migrations/0027_company_invoice_lines.sql`:
  ```sql
  ALTER TABLE trips ADD COLUMN invoice_id TEXT REFERENCES company_invoices(id);
  CREATE INDEX IF NOT EXISTS idx_trips_invoice ON trips(company_id, invoice_id, created_at);

  CREATE TABLE IF NOT EXISTS company_invoice_lines (
    id TEXT PRIMARY KEY,
    invoice_id TEXT NOT NULL REFERENCES company_invoices(id) ON DELETE CASCADE,
    trip_id TEXT NOT NULL REFERENCES trips(id),
    employee_user_id TEXT NOT NULL REFERENCES users(id),
    cost_center TEXT,
    trip_date TEXT NOT NULL,
    pickup_address TEXT, dropoff_address TEXT,
    amount_piastres INTEGER NOT NULL,
    vat_piastres INTEGER NOT NULL DEFAULT 0
  );
  CREATE INDEX IF NOT EXISTS idx_inv_lines_invoice ON company_invoice_lines(invoice_id);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_inv_lines_trip ON company_invoice_lines(trip_id);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_invoice_period_unique ON company_invoices(company_id, period_start);
  ```
  The unique index on `trip_id` makes double-billing structurally impossible.
- **API contract** — `GET /companies/admin/:id/invoices/:invoiceId` returns the invoice
  with its lines. Generation returns `{ invoiceId, trips, subtotal, vat, total }`.
- **Effort** — L.
- **Risk** — the backfill must map historical trips whose flag was already zeroed; accept
  that pre-migration months are unreconstructable and record that in the migration notes.
- **Acceptance criteria** — the SQLite reproduction in F-20-16 returns identical row sets
  for both paths; re-running generation for a period is a no-op; every invoice total
  equals the sum of its lines.
- **Tests** — port the F-20-16 reproduction into the suite as a regression test with the
  same four boundary trips.

#### P0.9 — A company-admin role

- **Goal** — a junior employee cannot read the company's trip history.
- **Design** — add `role TEXT NOT NULL DEFAULT 'member'` to `company_employees`
  (`member | admin`). `/companies/portal/*` returns the caller's **own** trips and nothing
  else for `member`; the full company view and invoice history require `admin`. Split the
  route: `GET /companies/portal/me` for any employee, `GET /companies/portal/invoices`
  and `/portal/trips` for company admins only.
- **Files to change** — `apps/api/src/routes/companies.ts`,
  `apps/api/src/middleware/auth.ts` (a `requireCompanyAdmin` helper).
- **DB** — `migrations/0028_company_employee_role.sql`:
  ```sql
  ALTER TABLE company_employees ADD COLUMN role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('member','admin'));
  ```
  Promote the first employee of each existing company to `admin` in the same migration so
  no account is orphaned.
- **API contract** — `403 NOT_COMPANY_ADMIN` on the admin-only portal routes.
- **Effort** — S.
- **Risk** — an existing pilot loses visibility until someone is promoted; the migration's
  promotion step covers it.
- **Acceptance criteria** — a `member` calling `/portal/invoices` gets 403 and cannot see
  a colleague's trip.
- **Tests** — member/admin matrix over every portal route.

#### P1.5 — Employee invitation and consent

- **Goal** — nobody is enrolled into corporate billing without agreeing.
- **Design** — admin invites by phone or email; the platform creates a
  `company_invitations` row with a token and notifies the user; the employee accepts in
  the rider app, which creates the `company_employees` row. Invitations expire. Admin can
  revoke. `POST /companies/admin/employee` keeps working for bulk onboarding but must
  verify the user exists.
- **Files to change** — `apps/api/src/routes/companies.ts`, rider app settings screen.
- **DB** — `migrations/0029_company_invitations.sql` with
  `(id, company_id, phone, email, token, status, expires_at, created_at)`.
- **API contract** — `POST /companies/admin/invitations`,
  `POST /companies/invitations/:token/accept`, `GET /companies/invitations/mine`.
- **Effort** — M. **Risk** — low.
- **Acceptance criteria** — a binding only exists after acceptance; an expired token is
  refused.
- **Tests** — invite → accept → trip billed; invite → expire → refused.

#### P1.6 — VAT and ETA e-invoice readiness

- **Goal** — issue an invoice an Egyptian corporate customer's finance team can book.
- **Design** — two tracks in parallel. **Data:** add VAT at 14% per line and in totals,
  plus issuer/receiver tax registration numbers, activity code, invoice serial,
  issue/due dates and currency. **Integration:** an `eta_submissions` table and a
  submission step that posts the invoice to the ETA platform, stores the returned UUID
  and the signed payload, and retries on failure. Issuance becomes a state machine
  (`draft → submitted → cleared → delivered → paid`), not a single insert.
  **Start the eSeal certificate procurement now** — it has external lead time and blocks
  the integration regardless of engineering progress.
- **Files to change** — `apps/api/src/lib/invoicing.ts`, new
  `apps/api/src/lib/eta.ts`.
- **DB** — `migrations/0030_invoice_vat_and_eta.sql`: VAT and identity columns on
  `company_invoices`; `eta_uuid`, `eta_status`, `eta_submitted_at`; an `eta_submissions`
  audit table.
- **API contract** — `POST /companies/admin/invoices/:id/submit` →
  `{ etaUuid, status }`.
- **Effort** — L, and gated on the certificate.
- **Risk** — highest-uncertainty item in this plan. The field list is from the ETA SDK
  documentation and is confident; the phase dates are directional. **Get an Egyptian tax
  adviser to confirm the VAT treatment of transport services before building** — Law 157
  of 2025 restructured several service categories and I could not confirm transport's
  treatment with certainty (see §10 Q5).
- **Acceptance criteria** — a generated invoice validates against the ETA schema in their
  sandbox and returns a UUID.
- **Tests** — schema-validation tests against the published ETA JSON shape.

#### P1.7 — Invoice delivery, collection and dunning

- **Goal** — invoices reach the customer and become cash.
- **Design** — render a PDF from the invoice and its lines (bilingual AR/EN, VAT
  breakdown, ETA UUID and QR), store it in the existing `FILES` R2 bucket, email it to
  `contact_email`, and create a Paymob order so it can be paid — finally writing the
  `paymob_order_id` column that has existed unused since 0003. Add a daily job that ages
  `issued → overdue` past the due date and notifies. Enforce `credit_limit` against
  outstanding balance so an overdue company stops accruing.
  **Do not extend `scripts/generate_pdf.py`** — it is a Windows-bound pitch-deck script
  (F-20-25). Render server-side from a template instead.
- **Files to change** — `apps/api/src/lib/invoicing.ts`, new
  `apps/api/src/lib/invoicePdf.ts`, `apps/api/src/index.ts`.
- **DB** — `migrations/0031_invoice_delivery.sql`: `pdf_r2_key`, `sent_at`, `due_date`,
  `paid_at`, `payment_ref` on `company_invoices`.
- **API contract** — `GET /companies/portal/invoices/:id/pdf` (company admin only),
  `POST /companies/admin/invoices/:id/send`.
- **Effort** — L. **Risk** — PDF generation inside a Worker has CPU limits; if it does not
  fit, generate on demand behind a signed URL rather than at issue time.
- **Acceptance criteria** — the customer receives a PDF and can pay it; an unpaid invoice
  becomes `overdue` and blocks further corporate spend.
- **Tests** — ageing job tests; a payment-webhook test marking the invoice paid.

#### P2.3 — Reporting and exports

- **Goal** — the monthly conversation with a corporate customer is data, not email.
- **Design** — company-scoped CSV/XLSX export of trips and invoice lines filtered by
  period, cost centre and employee; a spend-by-cost-centre summary; a top-spenders view.
  Explicitly **not** building Concur/Expensify connectors — Careem does not appear to
  offer them regionally and a CSV export covers the first customers.
- **Files to change** — `apps/api/src/routes/companies.ts`, admin console.
- **DB** — none. **Effort** — M. **Risk** — none.
- **Acceptance criteria** — a company admin exports last month's trips grouped by cost
  centre.
- **Tests** — export shape and scoping tests.

### 6.3 Delivery / courier — full scoping (brief Q9)

This is a scoping, not a plan to start. §6.5 argues it should not be next.

**What changes in the data model.** A parcel is not a passenger: it has a sender and a
recipient who are different people, it can be refused at the door, it can be damaged, and
in Egypt it usually carries cash. The trip tables cannot absorb that.

```sql
-- migrations/00NN_delivery_vertical.sql (sketch)
CREATE TABLE deliveries (
  id TEXT PRIMARY KEY,
  sender_user_id   TEXT NOT NULL REFERENCES users(id),
  captain_id       TEXT REFERENCES users(id),
  company_id       TEXT REFERENCES companies(id),      -- merchant B2B from day one
  status TEXT NOT NULL DEFAULT 'created'
    CHECK (status IN ('created','searching','assigned','picked_up','in_transit',
                      'delivered','refused','returned','cancelled','lost')),
  size_class TEXT NOT NULL CHECK (size_class IN ('envelope','small','medium','large')),
  weight_kg REAL, declared_value_piastres INTEGER,
  vehicle_type_id TEXT REFERENCES vehicle_types(id),
  pickup_lat REAL NOT NULL, pickup_lng REAL NOT NULL, pickup_address TEXT,
  pickup_contact_name TEXT, pickup_contact_phone TEXT,
  fare_piastres INTEGER NOT NULL, commission_piastres INTEGER NOT NULL DEFAULT 0,
  cod_amount_piastres INTEGER NOT NULL DEFAULT 0,      -- 0 = no COD
  cod_status TEXT CHECK (cod_status IN ('pending','collected','remitted','waived')),
  batch_id TEXT REFERENCES delivery_batches(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE delivery_drops (            -- multi-drop: one row per recipient
  id TEXT PRIMARY KEY,
  delivery_id TEXT NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  recipient_name TEXT NOT NULL, recipient_phone TEXT NOT NULL,
  dropoff_lat REAL NOT NULL, dropoff_lng REAL NOT NULL, dropoff_address TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','delivered','refused','failed')),
  otp_code TEXT, otp_verified_at TEXT,
  cod_amount_piastres INTEGER NOT NULL DEFAULT 0,
  delivered_at TEXT, failure_reason TEXT
);

CREATE TABLE delivery_proofs (           -- POD: photo in R2, signature, OTP
  id TEXT PRIMARY KEY,
  drop_id TEXT NOT NULL REFERENCES delivery_drops(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('photo','signature','otp','recipient_id')),
  r2_key TEXT, captured_at TEXT NOT NULL, lat REAL, lng REAL
);

CREATE TABLE delivery_batches (          -- a captain's multi-drop run
  id TEXT PRIMARY KEY, captain_id TEXT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'open', drop_count INTEGER NOT NULL DEFAULT 0,
  started_at TEXT, completed_at TEXT
);

CREATE TABLE cod_settlements (           -- courier float reconciliation
  id TEXT PRIMARY KEY, captain_id TEXT NOT NULL REFERENCES users(id),
  period_start TEXT NOT NULL, period_end TEXT NOT NULL,
  collected_piastres INTEGER NOT NULL, remitted_piastres INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open', settled_at TEXT
);
```

Plus `vehicle_types.max_weight_kg` / `max_volume_l` from P1.4's migration, and new rows
for `motorcycle` and `van`.

**What changes in dispatch.** `GEO_CELL`, `CAPTAIN_INBOX` and `OFFER_SCHEDULER` handle
"find a nearby captain and offer them work" and that part transfers unchanged. What does
not transfer: filtering candidates by vehicle capacity against `size_class`/`weight_kg`;
batching several deliveries into one run and sequencing the drops (a routing problem the
current single-origin-single-destination engine does not model); and re-dispatch on
refusal, where a parcel must come back or go to a locker rather than simply ending. Treat
batching as its own project — it is the piece most likely to be underestimated.

**What changes in pricing.** Distance and time still apply, but the drivers are size and
weight class, per-drop pricing beyond the first, COD handling fee, waiting time at pickup
(merchant not ready is the normal case), return leg on refusal, and insurance against
`declared_value`. This does not fit `apps/api/src/lib/pricing.ts` as it stands.

**What changes in the captain app.** Pickup confirmation with a parcel photo; a batch view
with ordered drops; per-drop recipient contact; POD capture (photo to R2 via the existing
`FILES` binding, signature, and an OTP read from the recipient); COD collection with a
running float total and a remittance flow; and refusal/return handling. This is a second
app mode, not a screen.

**What changes in risk.** Damage and loss claims need an evidence chain (`delivery_proofs`
is the spine), a declared-value ceiling, a dispute state, and a policy on who absorbs
what. COD adds theft and float exposure: a captain holding several thousand EGP of other
people's money needs a cap, daily remittance, and a hold on payout when unremitted. That
belongs with T18 (fraud/risk) and T03 (ledger) — routed in §9.

**Honest effort.** Assuming the P0 work is done and the team is small:

| Component | Effort |
|---|---|
| Data model + migrations | L (~1 week) |
| Delivery CRUD, state machine, dispatch integration | L (2–3 weeks) |
| Pricing engine for parcels | L (~1 week) |
| Captain app delivery mode (POD, batch, COD) | L (3–4 weeks) |
| Sender/merchant app surface | L (2–3 weeks) |
| COD settlement + reconciliation + payout hold | L (2 weeks) |
| Admin console for delivery ops | L (2 weeks) |
| Merchant API for e-commerce integration | L (2 weeks) |
| **Total** | **~14–19 engineer-weeks before a first pilot**, excluding ops build-out |

That estimate assumes no COD at launch would remove roughly 4 weeks — and also removes
most of the addressable Egyptian market, which is the trap.

### 6.4 Admin consoles for both verticals (brief Q8 — coordinate with T11)

Two new pages in `apps/admin/src/pages/`, registered in `App.tsx:50–59` alongside the
existing ten, reusing whatever table/form primitives T11 settles on rather than inventing
new ones.

**`IntercityPage.tsx`** — three tabs.
- *Routes*: list with origin, destination, distance, base price, duration, active; create
  and edit inline (against the now-validated PATCH from P0.5); deactivate rather than
  delete.
- *Schedules*: a date-filtered board showing departure, route, captain, **seats sold /
  total with an occupancy bar**, and status. Bulk-create recurring departures — "Cairo→
  Alexandria, 08:00 and 20:00, daily for 30 days" is the single biggest manual-labour
  saver here. Assign or reassign a captain with the P1.4 validation surfaced as inline
  errors. Cancel a schedule, showing the refund count before confirming.
- *Bookings*: search by rider, phone or booking id; see payment and boarding status;
  admin-cancel with refund; export a manifest as CSV for a captain without the app.

Operator questions it must answer at a glance: which departures in the next 48 hours have
no captain; which are below 50% sold and need a price move; which have riders who paid by
card but never settled (P0.2's `payment_status`).

**`CompaniesPage.tsx`** — list plus detail.
- *List*: name, status, employee count, month-to-date spend, outstanding balance, next
  invoice date.
- *Detail → Employees*: bindings with role (P0.9), cost centre, spend limit, policy
  fields, MTD spend against limit; invite (P1.5), suspend, promote to company admin.
- *Detail → Policy*: hours, vehicle classes, credit limit, and the `enforce | warn` toggle
  from P0.7 — ops need to run a pilot in warn mode and see what *would* have been blocked.
- *Detail → Invoices*: history with status, totals, VAT, ETA UUID; drill into line items
  (P0.8); regenerate, download the PDF, resend, mark paid manually.
- *Detail → Trips*: the company's trips with employee, cost centre, fare and invoice link,
  filterable by period.

Both pages are gated on the existing admin auth and both should write `audit_log` entries
via `logAudit` for every mutation, matching what `intercity.ts` and `companies.ts` already
do for booking and company creation.

**Effort** — M each (3–5 days), and they unblock everything else operationally. I would
not ship P1 for either vertical without them.

### 6.5 Other verticals — assessment and sequence (brief Q10, Q11)

| Vertical | Market fit (Egypt) | Effort | Regulatory | Verdict |
|---|---|---|---|---|
| **B2B corporate** | High — recurring, contracted, low CAC, and the schema is already 70% there | M (~4–6 weeks incl. compliance) | ETA e-invoicing is mandatory and non-negotiable | **Do this next** |
| **Intercity (finish)** | High — Swvl proved the corridor demand; the backend exists | M–L (~4–5 weeks incl. client) | None beyond the existing licence | **Do this alongside** |
| **Airport fixed-price transfers** | High margin, high trust, simple | S–M (~2 weeks) | None new | **Quick win — do it** |
| **Delivery / courier** | Very large but crowded and operationally heavy; COD is the real barrier | L (~14–19 weeks) | Commercial logistics; motorcycle *delivery* is fine | Not next — 2027 H1 at the earliest |
| **Commuter subscriptions** | Strong fit with intercity/fixed routes; improves utilisation | M (~3 weeks *after* intercity ships) | None new | Follow-on to intercity |
| **Rentals with driver (hourly)** | Moderate; corporate and tourism overlap | M (~2–3 weeks) | Check the hire-with-driver category | Opportunistic, pairs with B2B |
| **Motorcycle passenger class** | High demand in Cairo traffic | M | **Outside Law 87 of 2018** — cars only | Blocked pending legal opinion |
| **Tuk-tuk passenger class** | Real in specific areas; already advertised in the UI | M | Separate 2024 licensing regime, still evolving | Not before the legal position is settled |

**Which vertical earns the next quarter (Q11).** **B2B corporate, with intercity finished
alongside it.** The argument is not enthusiasm, it is three things.

*Effort against a working base.* B2B needs enforcement, invoicing and a console on top of
a data model that already exists — roughly 4–6 weeks including the compliance track.
Delivery needs 14–19 weeks and an operational capability (COD float, returns, claims) the
company does not have. At the current stage the cheaper build wins on the risk-adjusted
comparison alone.

*Revenue quality.* Corporate accounts are contracted, recurring, invoiced monthly and have
materially lower acquisition cost than consumer delivery, which is a price war against
Talabat and Mrsool with entrenched courier supply. Swvl is the direct evidence: they burnt
through a SPAC and near-delisting on consumer scale and only reached profitability
(FY2025: $24.2M revenue, $1.3M net income) **after pivoting to enterprise and government
B2B**. That is the most relevant data point available for this market, and it points one
way.

*Compounding.* Corporate customers are the natural first buyers of intercity — staff
travelling Cairo→Alexandria on company account is exactly the Egyptian B2B use case, and
it is currently impossible because `intercity_bookings` has no `company_id` (F-20-28).
Finishing both together lets one sales conversation sell both, and airport transfers
(a two-week build) slot into the same corporate pitch. Delivery shares almost nothing with
that motion.

The honest counter-argument is that delivery is where the volume is, and every quarter of
delay lets Careem Express and Bosta entrench further. I would still not take it now:
entering a crowded, COD-heavy logistics market with an unfinished core, no admin tooling
and four live S1s is how a small team ends up doing three things badly. Revisit at the end
of the B2B quarter with real corporate revenue and a working operations console.

## 7. Phasing

**P0 — before any production traffic.** The S1 set plus the two guards that make the
latent intercity defects safe to leave in place. Note that P0.1 Stage A alone (three
lines) removes the live misrouting, so the intercity items can be sequenced with the
client work rather than blocking a launch that does not include intercity.

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Stage A — disable the "سفر" chip | P0 | S | Flutter |
| P0.6 — business/personal choice per trip | P0 | M | backend + Flutter |
| P0.7 — enforce company spend policy | P0 | M | backend |
| P0.8 — single invoicing path, line items, correct dates | P0 | L | backend |
| P0.9 — company-admin role | P0 | S | backend |
| P0.3 — guard the boarding transition | P0 | S | backend |
| P0.4 — atomic seat claim | P0 | S | backend |
| P0.5 — validate route PATCH and fare fallback | P0 | S | backend |
| P0.2 — close the card-payment hole | P0 (before intercity ships) | M | backend |

**P1 — first 30 days.**

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| §6.4 — `CompaniesPage.tsx` admin console | P1 | M | admin |
| §6.4 — `IntercityPage.tsx` admin console | P1 | M | admin |
| P1.5 — employee invitation and consent | P1 | M | backend + Flutter |
| P1.6 — VAT + ETA e-invoicing (certificate procurement starts P0) | P1 | L | backend + ops/legal |
| P1.7 — invoice PDF, delivery, collection, dunning | P1 | L | backend + ops |
| P0.1 Stage B — rider intercity client | P1 | L | Flutter |
| P1.1 — captain intercity surface | P1 | L | Flutter |
| P1.2 — schedule lifecycle cron | P1 | M | backend |
| P1.4 — captain assignment validation + vehicle capacity | P1 | M | backend |

**P2 — next 90 days.**

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P1.3 — tiered cancellation policy | P2 | M | backend + Flutter |
| P2.1 — occupancy-based intercity pricing | P2 | M | backend |
| P2.2 — intercity/B2B money columns to integers | P2 | backend | backend |
| P2.3 — corporate reporting and CSV export | P2 | M | backend + admin |
| Intercity billed to company (`company_id` on bookings, F-20-28) | P2 | S | backend |
| Airport fixed-price transfers | P2 | S–M | backend + Flutter |
| Commuter subscriptions on intercity routes | P2 | M | backend + Flutter |
| Delivery vertical (§6.3) | **not scheduled** — revisit after the B2B quarter | L | all |

## 8. Metrics

Nothing in either vertical is instrumented today, so every "current" below is either zero
or unmeasurable — which is itself the first thing to fix. Route these to T22 for
dashboarding.

**Intercity**

| Metric | Current | Target |
|---|---|---|
| Seat utilisation (`seats_booked / seats_total` at departure) | unmeasurable — schedules never reach a terminal state (F-20-07) | ≥ 70% by month 3, ≥ 85% by month 6 (Swvl reached 96%) |
| Bookings reaching `boarded` | 0 — no client, no captain app | ≥ 95% of non-cancelled |
| Card bookings settled vs seats held | unmeasured; currently 0% settled by construction (F-20-02) | 100%, alerting on any gap |
| Seat-hold drift (`seats_booked` vs live booking count) | unknown (F-20-05) | 0, checked daily |
| Cancellation rate, and share inside 1h of departure | unmeasured | < 10% total, < 2% late |
| No-show rate | unrecordable (F-20-30) | measured, then < 5% |
| Schedules departing with no captain assigned | unmeasured | 0 |

**B2B**

| Metric | Current | Target |
|---|---|---|
| Corporate trips billed correctly (invoice lines = tagged trips) | provably wrong (F-20-16) | 100% reconciled monthly |
| Revenue lost to boundary-day flag clearing | unmeasured, non-zero | 0 |
| Policy blocks by reason | 0 — nothing is enforced (F-20-17) | measured from day one of P0.7 |
| Personal trips wrongly billed to companies | unmeasured, currently 100% of employee personal trips (F-20-15) | 0 |
| Invoices issued → delivered → paid | delivered 0%, paid 0% (F-20-22) | ≥ 95% delivered within 24h; DSO < 30 days |
| ETA clearance success rate | n/a | ≥ 99%, with retry alerting |
| Days from corporate signup to first billed trip | unmeasurable (manual curl onboarding) | < 2 days once the console ships |

**Instrumentation to add alongside P0** — a daily reconciliation job emitting: seat drift
per schedule, trips with `billed_to_company = 1 AND invoice_id IS NULL` older than 40
days, invoices whose line sum ≠ total, and card bookings `pending` past their TTL. Four
queries; they would have caught every S1 in this document.

## 9. Cross-cutting notes

**→ T03 (Money integrity — wallet, ledger, commission)**
- Intercity and B2B money columns are `REAL` while migration 0005 moved core currency to
  integer piastres: `intercity_routes.base_price`, `intercity_bookings.fare`,
  `companies.credit_limit`, `company_employees.spend_limit_month`,
  `company_invoices.total_amount` (`0003:74,101,120,131,150`). My P2.2 fixes them locally
  but the piastre migration is your axis — you may want them folded into one sweep.
- Intercity wallet moves write `wallet_transactions` with `type='trip_payment'` and
  `trip_id = NULL`, encoding the booking id in the free-text `note` as
  `intercity:<bookingId>` (`intercity.ts:165–170`, refund at `:283–288`). The ledger has no
  typed link to intercity bookings, so intercity money is invisible to any trip-based
  reconciliation.
- Intercity cash bookings take **no commission** — nothing debits the captain, unlike the
  city-trip completion path (`trips.ts:985–990`). If intercity ships on cash, the platform
  earns nothing on it.

**→ T04 (Payments, PSP, payouts)**
- `POST /payments/paymob/intention` takes a client-supplied `amount` with no server-side
  check against the thing being paid for (`payments.ts:12–18`). For `intercity_booking`
  there is not even an id to check against. A rider can pay 1 EGP for a 350 EGP seat and
  the webhook records a settled transaction. This is your axis; my P0.2 fixes only the
  intercity half.
- `company_invoices.paymob_order_id` (`0003:152`) has existed since 0003 and is never
  written or read — corporate invoices cannot be collected through the PSP.

**→ T02 (Authorization, RBAC, IDOR)**
- `/companies/portal/*` authorises on "is an active employee of any company" and then
  returns the whole company's invoices and last 100 trips with addresses
  (`companies.ts:217–239`). There is no company-admin concept in the schema
  (`0003:126–136`). My P0.9 adds a role; the general pattern of "membership implies full
  tenant read" is yours.
- For the record, I tested and **disproved** a suspected wildcard-middleware bypass on
  `companies.ts:68` — Hono's `/admin/*` does cover the bare `/admin` routes at `:70`
  and `:99`. Don't re-raise it.

**→ T25 (Privacy, compliance, legal)**
- Every employee trip is auto-billed and therefore auto-disclosed to the employer with
  pickup and dropoff addresses (`trips.ts:431–479`, `companies.ts:231–238`) with no
  consent step and no opt-out. This is a consent and data-minimisation problem before it
  is a product problem.
- Egyptian ETA e-invoicing is mandatory for B2B and the platform cannot currently produce
  a compliant invoice (F-20-21). The eSeal certificate is a procurement lead-time item.
- **Open question for you:** the VAT treatment of transport services after Law 157 of 2025.
  I could not confirm it and have flagged it as needing counsel rather than assuming 14%.

**→ T08 (Data model, migrations, integrity)**
- `intercity_schedules.status` allows five values and only one is ever written
  (`0003:88`); `intercity_bookings.no_show` is defined and never set (`0003:103`). Dead
  enum states across the schema may be a pattern worth sweeping.
- `intercity_bookings` has no `payment_status` and no `company_id` (`0003:94–106`).
- No unique constraint on `company_invoices(company_id, period_start)` permits duplicate
  invoices (`0003:144–156`).

**→ T06 (Dispatch & matching)**
- Because "سفر" mode submits an ordinary `POST /trips` (F-20-01), long-distance
  intercity-intent requests are already entering your dispatch path as city trips. If you
  see 200 km trips in the matching data, that is where they come from.

**→ T11 (Admin console & operations tooling)**
- Two whole verticals have no admin surface (F-20-27). I have specified both consoles in
  §6.4 deliberately in terms of *what an operator needs to answer*, not components — please
  own the shared table/form/detail primitives so these two pages do not invent their own.

**→ T05 (Pricing, surge, bidding)**
- Intercity pricing is flat `base_price × seats` and never touches the bidding engine
  (`intercity.ts:99–102`). If bidding is the product's core differentiator, someone has to
  decide whether intercity is exempt from it — see §10 Q1.

**→ T18 (Fraud, abuse, risk)**
- If delivery ever ships, COD float is the largest new fraud surface in the product:
  captains holding cash, doorstep refusals, and claims of loss or damage. §6.3 sketches
  `cod_settlements` and a payout hold; the risk policy is yours.

**→ T27 (Cross-app parity)** — the parity items I hit while working this track:
- The clearest parity gap on my axis is structural: intercity has **rider-side UI intent
  with no captain-side anything**, and B2B has **backend policy with no UI on either
  side**. Any parity programme should treat "one app knows about a feature and the other
  does not" as a first-class defect class, not just divergent screens.
- Observed while reading: `trip_chat_screen.dart` has diverged hard — rider 150 lines,
  REST-poll only; captain 421 lines with WebSocket, typing indicators and a poll fallback.
  The WS services differ too (`TripWebSocketService` 117 L vs
  `CaptainTripWebSocketService` 132 L, different names, different surfaces —
  the captain one exposes a broadcast stream, the rider one a single `onStatus` callback).
  Wallet (captain 810 L vs rider 497 L) and SOS (11.2 KB vs 6.3 KB) diverge by size;
  I did not read those two in full, so treat that as `likely` rather than confirmed.
- `apps/rider/lib/screens/ride/schedule_screen.dart` is defined and never imported —
  dead code that looks like a feature.
- Vocabulary: the UI says **سفر** for the category, the code says `intercity`, and the
  bottom bar's own doc-comment describes it as arranging "a long-distance seat, a car, or
  a parcel" — three different products in one label. Worth settling in the glossary.

**→ T09 / T10 (Rider and captain journeys)**
- T09: selecting "سفر" produces an ordinary city trip (F-20-01). If you are mapping the
  rider journey, that branch is a dead end that does not look like one.
- T09/T10: `الشحن` (freight) and `تروسيكل` are rendered as "قريباً" chips
  (`vehicle_selector.dart:33–54`) — the product is signalling services with no backend at
  all. Worth a shared decision on how long "coming soon" can stay in a shipped app.

## 10. Open questions

**Q1 — Is intercity a timetable or a marketplace?** *(the biggest one)*
The backend implements the Swvl model: fixed routes, scheduled departures, seat counters,
assigned captains, fixed prices. The product thesis is the inDrive model: riders name a
price, captains bid. The two are architecturally different products and intercity
currently touches none of the bidding code.
- **Option A — keep scheduled seats.** Finish as specified in §6.1. Predictable for
  riders, needs supply planning and yield management, and is what Swvl proved works on
  Egyptian corridors.
- **Option B — intercity as bidding.** Rider posts Cairo→Alexandria for a date; captains
  already making the trip bid; no inventory, no schedules, no assignment. Reuses the
  bidding engine, discards most of `intercity.ts`, and is far lighter operationally.
- **Option C — both**, with scheduled seats on dense corridors and bidding elsewhere.
- **Recommendation: A now, C later.** The scheduled code exists and is mostly sound; the
  fastest path to a working vertical is to finish it. Revisit B for thin corridors once
  there is demand data. But this is a product decision and it should be made explicitly
  rather than by default — right now the code has made it silently.

**Q2 — Do we ship intercity before or after B2B?**
§6.5 recommends both in the same quarter, B2B leading. If the team can only do one, B2B
is the answer: less work, contracted revenue, and it makes intercity more sellable later.
Confirm the sequencing before P0.1 Stage B starts, because that is the expensive half.

**Q3 — What is the corporate default: personal or business?**
P0.6 defaults to **personal** and requires an explicit business choice. The alternative —
default business with an opt-out — is friendlier for a customer whose staff only ever
travel on business, and could be a per-company setting. **Recommendation: default personal
globally, with an optional per-company "default to business" flag** once P0.7's policy
enforcement is live to bound the damage.

**Q4 — Warn or enforce for the first corporate pilot?**
P0.7 ships with both modes. **Recommendation: warn mode for the first customer's first
month**, then switch. Blocking a CFO's staff on day three over a misconfigured hours
policy is a worse outcome than a month of over-permissive rides.

**Q5 — VAT treatment of transport services after Law 157 of 2025.** *(needs counsel, not
engineering)*
Egypt's standard rate is 14% and I am confident that applies to services generally, but
Law 157 of 2025 restructured several service categories and I could not confirm transport's
specific treatment. This changes invoice arithmetic, so it must be settled before P1.6
builds. **Recommendation: get a written opinion from an Egyptian tax adviser now** — it is
cheap, it is on the critical path, and guessing it wrong means reissuing invoices.

**Q6 — Who owns intercity supply?**
Nothing in the code answers whether an intercity captain is an ordinary city captain who
opts in, a dedicated subset, or a third-party bus/van vendor (Swvl runs 240 vendors). It
determines whether P1.4's assignment validation is enough or whether a whole vendor model
is needed. **Recommendation: start with opted-in existing captains** — the schema supports
it today and it needs no new onboarding.

**Q7 — Can intercity be billed to a company?**
`intercity_bookings` has no `company_id` (F-20-28), so corporate staff travel between
governorates — the most natural Egyptian B2B use case — is unsupported. It is a small
change (P2, S) but it needs a decision on whether corporate policy limits apply per seat
or per booking. **Recommendation: per booking, checked at booking time with the same
`assertCompanyPolicy` helper.**

**Q8 — How long may "قريباً" stay in a shipped app?**
`الشحن` and `تروسيكل` are advertised with no backend (F-20-29), and per §6.5 tuk-tuk is
regulatorily blocked and delivery is at least a year out. **Recommendation: remove both
chips.** Advertising a service that is a year away, and one that may never be legal in the
current form, costs trust and generates support load for nothing.

**Q9 — Motorcycle passenger class: get a legal opinion or drop it?**
Law 87 of 2018 covers passenger cars only; motorbikes were deliberately excluded. Halan
operates outside that framework. Demand in Cairo traffic is obvious and the compliance
path is not. **Recommendation: commission a legal opinion but do not schedule engineering
against it.** Motorcycle *delivery* is unaffected by this and stays available whenever
delivery is picked up.
