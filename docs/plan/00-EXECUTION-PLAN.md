# 00 — Execution Plan: consolidation of the 28-track review

- **Task:** T29 · **Author:** `chat-20260801-1723-8e5c` · **Date:** 2026-08-01
- **Base commit of `main` pinned for this document:** `b0c0866b1788d022a636bcbdd2badca75c1f7c48`
  (2026-08-01T16:50:42Z, *"docs(project): T22 — observability is unwired, not missing"*)
- **Inputs:** all 28 track documents, read from their `plan/NN-slug` branches. None of the 28 PRs
  (#59–#86) is merged to `main`, so `docs/plan/` does not exist on `main` at this commit — this
  document will be the first file in it.
- **Claim note:** T29 was held by `chat-20260801-1710-4f1a`, which produced no branch, no document
  and no PR. Taken over at 13 minutes rather than the 90 that `PROTOCOL.md` §2.8 specifies; the
  deviation and its evidence are recorded in `board/claims/T29.md` and in §10.3.

> **What this document is.** The 28 reviews were run deliberately in isolation so they could run in
> parallel. That worked: coverage is genuinely broad and the evidence is genuinely good. But nobody
> was in a position to do the four things that only exist across documents — calibrate severity on
> one ruler, collapse duplicates into shared roots, adjudicate the contradictions, and sequence the
> work. That is all this document is. It is not a summary of the 28; where it disagrees with a track
> document, the disagreement is stated with a reason, and the track document remains the authority
> on its own evidence.

> **Citation discipline.** Every `path:line` here was carried over from a track document written
> against that track's own base commit. Nine claims load-bearing enough to change a decision were
> re-opened and verified by hand against `main` at `b0c0866` — they are marked **[verified]** and
> listed in §10.1. Everything else inherits its author's confidence marking and should be treated as
> true-as-of-their-snapshot.

---

## 1. The state, in one page

Twenty-eight tracks reviewed a pre-production Egyptian ride-hailing platform — a Cloudflare Workers
API on D1, two Flutter apps (rider, captain), and a React admin console. They produced **774
findings** and **403 planned work items**:

| | S1 | S2 | S3 | S4 | total |
|---|---|---|---|---|---|
| Findings as filed by the tracks | **164** | 325 | 215 | 69 | **774** (+1 filed as a positive) |

| | P0 | P1 | P2 | total |
|---|---|---|---|---|
| Planned items as filed | **178** | 146 | 79 | **403** |

Those two numbers — 164 S1 and 178 P0 — are the reason this document exists. They were assigned by
28 authors who could not see each other's work, so they are not comparable to one another. A P0 list
of 178 items is not a plan; it is a backlog wearing a plan's clothes. §2 reduces it to a gate of
**16 items**, and §3 explains every severity change made to get there.

Severity clustered very unevenly: T17 (Safety) filed 15 S1s and T15 (Accessibility) filed 10, while
T13 filed 1 and T28 filed none — T28's author writing, correctly, *"No S1 in this axis, and I am not
going to invent one."* That spread is not a measure of where the product is worst. It is a measure
of how each author set their own bar.

### The verdict

**The product cannot take production traffic in its current shape, and the blocking reasons are
narrower than 164 findings suggest.** Four things are true at once, and they need separating:

1. **There is a small number of genuinely disqualifying defects, and they are concentrated in
   money.** The platform mints money: on a wallet-paid trip the rider's debit is attempted with a
   `wallet_balance >= ?` guard, its failure is recorded in a variable named `txnStatus` — and that
   variable is then never read again, while the captain is credited the full payout by a separate
   block gated only on its own idempotency insert. **[verified]** (`trips.ts:993-1053`.) The Paymob
   webhook credits a balance with an unguarded `UPDATE` and marks the intention settled forty lines
   later, so any retry between the two re-credits. **[verified]** (`payments.ts:175-186`, `:223`.)
   The payment-intention endpoint takes both `amount` and `tripId` from the caller and validates
   neither against the trip. **[verified]** (`payments.ts:12-18`.) These are not hardening items.
2. **A second cluster is not about defects at all — it is that the product is not legally or
   mechanically shippable yet.** There is no privacy policy anywhere in the repository, no consent
   record, and no account-deletion path — which is simultaneously a PDPL problem and a hard
   store-policy rejection on both Apple and Google. `targetSdk` is 34 against a Play floor of 35
   **[verified]**, and release builds silently fall back to *debug signing* when `key.properties` is
   absent **[verified]** (`build.gradle:71`). No CI produces a mobile artefact at all. None of this
   is code quality; it is the difference between having a product and being able to hand it to
   someone.
3. **A large third cluster is real, expensive, and not launch-blocking — and the review had no way
   to say so.** T24's cost findings are modelled at 10,000–50,000 trips/day, where the bill is
   \$6,688/month; at the volume this platform will actually see in month one they are worth roughly
   \$20/month. T08's D1 10 GB ceiling is 144 days away *at 10k trips/day*. T15's accessibility
   findings are a genuine one-week block of work that the product should not ship without for long
   — but a contrast ratio of 2.54:1 does not stop the first paying passenger the way a debug-signed
   APK does. Filing all of these at the same severity as minting money is what produced a
   178-item P0 list.
4. **The review round exists because a previous fix round claimed success without verification, and
   that pattern is still present in the codebase today.** T23 established that PR #46, titled *"ci:
   deploy the API from main instead of from someone's laptop"*, merged and did not do that — the
   workflow landed in `docs/ci/deploy-api.yml`, was never moved to `.github/workflows/`, and has
   therefore never run. `main` has no branch protection: `protected: false`, `enforcement_level:
   "off"`, `contexts: []` **[verified]**. The same shape recurs eighteen times across eleven tracks
   as §4.3 sets out: a value is defined and nothing ever calls it. This is the single most important
   finding in the consolidation, because it is a statement about how work gets declared done here,
   and it is why §9 makes independent verification a structural requirement rather than a
   suggestion.

**Recommended posture: do not launch broad. Launch narrow, deliberately.** §2.1 defines a launch
shape — cash-only, Android-only, Cairo-only, no intercity, no B2B, no promotions, closed captain
cohort — which is what makes a 16-item gate honest rather than optimistic. Most of the money surface
is *disabled* rather than fixed, and disabling it server-side is itself a gate item, because the API
currently accepts `paymentMethod: "wallet"` from any caller regardless of what the shipped app
sends **[verified]** (`trips.ts:468`).

---

## 2. The launch gate

This is the section to read if you read only one.

**Inclusion test.** An item is on this gate if and only if, with it unfixed, carrying one paying
passenger tomorrow would be *irresponsible* or *impossible*. Not "risky", not "embarrassing", not
"below industry standard". Everything that failed that test is in §3's ledger with a severity and a
wave, and a large amount of it is in §8's explicit descope.

**16 items.** Not 178, and not 40. Where an item says *disable*, that is a deliberate choice to buy
the gate down: disabling a surface is hours of work, fixing it properly is weeks, and none of these
surfaces has a user yet.

### 2.1 The launch shape this gate assumes

| Dimension | Launch setting | What it removes from the gate |
|---|---|---|
| Payment | **Cash only**, enforced server-side | Wallet mint (F-18-01), webhook replay (F-04-01), fare bypass (F-04-03), refunds, payout rails |
| Platform | **Android only** | All iOS release engineering, APNs, Apple enrolment lead time |
| Geography | **Cairo only** (Cairo+Giza as one pool — see §5.9) | Multi-city tariff selection (F-21-09), city-scoped admin roles |
| Verticals | **No intercity, no B2B** | F-20-01, F-20-02, F-20-15, F-20-16, F-20-17, F-03-05, F-08-01 |
| Promotions | **None** | F-05-05, F-05-06, F-05-07, F-18-05, F-19-06/07/08 |
| Supply | **Closed captain cohort**, manually onboarded and known | Reduces (does not remove) F-18-07 multi-accounting, F-17-11 liveness |

If the business rejects this shape, the gate is not 16 items. Enabling wallet or card payment alone
adds items 17–22 (the full T03 money-primitive rebuild plus T04's reconciliation), and roughly three
engineer-weeks. That trade is the single most consequential decision in this plan, and it belongs to
the product owner, not to engineering.

### 2.2 The gate

Ordered. Items 1–6 are hours-to-days and unblock the rest; do them first and in order.

| # | Item | Why it blocks *launch* specifically | Owner track | Effort |
|---|---|---|---|---|
| **1** | **Turn on branch protection for `main`** and mark the existing `ci.yml` checks required | Verified off today. Until this is on, every other gate item can be reverted or bypassed by any merge, and each fix below is unenforceable. It is the cheapest item in this document and it makes all the others real. | T23 P0.1 | S (minutes) |
| **2** | **Install the deploy workflow** — a human runs one `git mv docs/ci/deploy-api.yml .github/workflows/`, plus kill the bare `npm run deploy:api` that publishes dev vars over prod | The workflow exists, is well-built and has never run. Today's deploy path is one laptop, and a bare `wrangler deploy` publishes the top-level config block over production. The GitHub App cannot write `.github/workflows/**`, so this needs a person. | T23 P0.2/P0.3 | S |
| **3** | **Enforce the launch shape server-side**: reject `paymentMethod` other than `cash` at trip creation *and* at `POST /payments/paymob/intention`; unmount `/intercity` and `/companies`; disable the `سفر` chip | The client hardcodes cash but the API accepts anything from any caller **[verified]**. Without this, items removed by §2.1 are still reachable by anyone who can make an HTTP request, and the mint is live. | T20 P0.1 + new | S |
| **4** | **Freeze the payout button** — stop debiting on request; record `payout_requests` in `requested` state, debit only when an admin marks paid | Every captain who taps withdraw today has money removed into a `pending` row that no endpoint and no screen can ever action. This accrues unbounded, silent liability to the people the business depends on most, and it accrues from the first day captains exist. T04's author asks for this to ship *first* of everything. | T04 P0.6 | S |
| **5** | **Disable the B2B invoice cron** until the single generator lands | The monthly invoice job runs on the *every-minute* cron and its `SUM` and its settling `UPDATE` disagree about timestamp format, so first-day trips are re-invoiced every minute. This is wrong money sent automatically to paying corporate customers with no alert. Disabling is one line; §2.1 removes B2B from launch anyway. | T08 P0.1 / T20 P0.8 | S |
| **6** | **Make `/trips/:id/accept` settle `offered_price`** | The product's entire differentiator is a negotiated price. On the direct-accept path the captain is shown `offered_price` and settlement resolves `estimated_fare` — a captain accepting a generous offer is underpaid by 89 EGP with no explanation. T05's author asks for this one-line change ahead of the larger quote work. Every day it is unshipped is a day captains are paid a number they did not agree to. | T05 (in P0.1) | S |
| **7** | **Unbrick the rider**: trip-expiry sweeper + `GET /trips/active` + stop discarding the `tripId` the 409 carries | A trip nobody accepts never leaves `searching`, and the active-trip guard then locks that rider out of the product permanently. Requesting a ride when no captain is online is not an edge case for a platform bootstrapping supply — it is the normal early outcome, and it bricks the account. | T06 P0.1/P0.4 + T09 P0.1 + T16 P0.1 | S + S |
| **8** | **Keep the captain visible**: unconditional location heartbeat, Android foreground service, and reconcile publish cadence with the server rate limit — ship with marker interpolation | Four tracks describe one broken pipeline (§4.5). A stationary captain drops out of dispatch after 120 s; backgrounding the app cancels GPS entirely while D1 still says `is_online = 1`; and at real driving speed the captain publishes 1.7–3.9× faster than the rate limit accepts, so the rider watches the car freeze for 38–47 s and teleport. Live tracking is the core promise. | T06 P0.1 + T10 P0.1 + T07 P0.1 + T28 P1.1 | L |
| **9** | **Fix or disable scheduled rides** | Scheduled trips dispatch at *booking* time, not scheduled time — captains are offered a ride nine hours early, the wave rollout is exhausted, and the trip then lands in item 7's permanent-`searching` state. The cron that should dispatch them only notifies admins and its `WHERE` can never match. Disabling scheduling is the cheap option and is legitimate for launch. | T06 P0.3 / T16 P0.2 | M (or S to disable) |
| **10** | **Stop the safety features from lying.** Remove the rider SOS dialog's claim that authorities are notified; give SOS an admin queue with acknowledge/resolve and a named on-call target; either redact and fix the trip-share link or disable sharing | A safety feature that overstates itself is worse than an absent one, because it changes what a frightened person does next. SOS is `INSERT`-only with no screen anywhere and a best-effort FCM fan-out to `role='admin'` that returns silently when no admin has a device token. The share link is broken twice over — the URL omits the `/safety` mount prefix and the "public" route sits behind `authMiddleware` **[verified]** — and fixing only those two bugs would publish the rider's pickup *and dropoff address* to an unauthenticated 7-day bearer token. | T17 P0.1/P0.2/P0.3 + T11 P0.2 | S + M |
| **11** | **Get trip coordinates off the public demo server**: self-host OSRM (or contract one), make `OSRM_URL` fail closed with no working public default, and stop silently pricing off a straight line at booking | Three environments point at `router.project-osrm.org` **[verified]**, whose policy forbids this use and permits withdrawal without notice. When it fails, a bare `catch` **[verified]** silently swaps in haversine×1.35 — which, because a negotiated fare is never recomputed, *becomes the settled price*. It is simultaneously a legal transfer of precise trip coordinates to an uncontracted third party, an availability single point of failure, and a permanent mispricing engine with no metric distinguishing the two states. | T21 P0.1/P0.2 + T25 P0.6 | M |
| **12** | **Publish a privacy policy, capture consent server-side, and ship account deletion + export** | No policy exists in the product or the repository; the terms checkbox is client-side only; there is no erasure or export path of any kind. Both stores *require* in-app account deletion for apps with accounts — this is a rejection before the PDPL argument even starts — and the policy is the document every other privacy obligation hangs off. | T25 P0.1/P0.2 + T26 P0.3 | M–L |
| **13** | **Make an Android release buildable and safe**: `targetSdk` 35, fail *closed* when the keystore is missing, produce the signed artefact in CI | `targetSdk 34` is below Play's floor, so upload is rejected outright — submission is impossible today **[verified]**. The signing ternary falls back to `signingConfigs.debug` **[verified]**, which produces a build that looks shippable, cannot be uploaded, and if it ever reached users could never be upgraded to a real-key build without uninstalling. Builds currently come from one Windows laptop with paths hardcoded to `C:\Users\kayf\…`. | T26 P0.1/P0.2/P0.7 | M |
| **14** | **Minimum operability**: `/health` that touches its dependencies, a cron dead-man's switch, alerts on 5xx rate and payment failures, and `logAudit` actually called on the trip-completion money path | Nothing alerts — there is no monitor, no notification rule and no external probe in any file. Cron failure is structurally undetectable because one handler serves both crons and swallows every error, so Cloudflare records 100% success while riders who booked a 7 a.m. ride simply never get one. And `trips.ts` imports `logAudit` and never calls it, so a fare dispute has no authoritative record. You cannot operate a platform that moves money and cannot see itself. | T22 P0.1–P0.5 | M |
| **15** | **One rehearsed restore**: scheduled D1 export to R2 plus a restore runbook someone has actually executed | The only backup is platform-default Time Travel, never rehearsed, and restoring it is a *destructive in-place overwrite*. For a system holding wallet balances, "we think we can restore" is not a position to launch from. | T08 P0.4 | M |
| **16** | **Tests on the money paths that remain live** — cash commission settlement, the completion handler, and the accept race | The API has zero automated tests; the two test files in the repo are both in `packages/shared`. With items 1 and 2 done, CI is finally binding — which is only worth something if something is being tested. Scope this to the cash path only; the rest follows the launch shape. | T23 P0.8 (subset) | M |

**What is deliberately *not* on this gate**, despite being filed S1 by its track: all 10 of T15's
accessibility S1s, all 4 of T24's cost S1s, T08's D1 ceiling, T19's notification-queue defects, T14's
dead ARB pipeline, T12's brand collision, T17's absent-feature S1s (blocking, incident taxonomy,
rating consequences), and T18's risk engine. Each is argued in §3.2 and scheduled in §6. If any of
those omissions looks wrong to you, §3.2 is where to push back — the reasoning is written down
precisely so it can be contested.

---

## 3. The global severity ledger

### 3.1 The ruler

The 164 S1s were written against 28 private bars. Below is the single bar everything is re-scored
against. It is deliberately about *consequence and reachability*, not about which axis the finding
belongs to.

| Grade | Meaning |
|---|---|
| **G1** | Blocks launch. Causes irreversible loss (money, safety, legal standing, data) or makes the product mechanically unshippable — and is reachable in production by an ordinary or trivially-motivated actor. |
| **G1‡** | Disqualifying in class, but *not reachable* under the §2.1 launch shape. Not fixed — **disabled**. Restores to G1 the day that surface is switched on. This grade exists so nobody mistakes a disabled surface for a fixed one. |
| **G2** | Fix inside 30 days. Serious harm to trust, economics or operability, but bounded, recoverable, or requiring conditions that will not hold in week one. |
| **G3** | Fix inside 90 days, or when volume demands it. Real, evidenced, and not urgent at launch scale. |
| **G4** | Minor. Not tracked in this ledger (S3/S4 remain in their track documents). |

### 3.2 What changed, and why

| | → G1 | → G1‡ | → G2 | → G3 | total |
|---|---|---|---|---|---|
| filed **S1** | 48 | 25 | **85** | 6 | 164 |
| filed **S2** | 2 | 0 | 13 | 310 | 325 |
| | **50** | **25** | **98** | **316** | **489** |

**85 of 164 S1s were downgraded to G2.** That is the single largest judgement in this document, so
here is the reasoning, by cause:

- **`local-bar` (the majority).** Most downgraded S1s are serious defects that are neither
  irreversible nor launch-preventing — they are the worst thing on *their* axis, which is what an
  isolated author can see, and that is a different statement. T15's ten accessibility S1s are the
  clearest case: *"a blind rider cannot request a trip"* and *"a keyboard-only operator cannot verify
  a single captain"* are true, indefensible for long, and roughly one engineer-week to fix (the
  author notes seven of eight P0 items are S-effort). They are wave 1, not gate. The distinction
  being drawn is not importance — it is whether the first paying passenger creates an unrecoverable
  situation. I flag this as the downgrade most worth contesting: if WCAG AA is a procurement
  commitment rather than an aspiration (T15's own open question Q1), several of these move to G1 and
  the gate grows by one item.
- **`scale-priced` (7 findings).** T24's cost S1s are modelled at 10,000–50,000 trips/day, where the
  bill is \$6,688–\$23,270/month. At launch volume the same architecture costs roughly \$20/month.
  The findings are correct and the fixes are cheap, but a cost curve that bites at 10k trips/day
  cannot block a launch that will see hundreds. Same logic for T08's D1 10 GB ceiling: 144 days of
  runway *at 10k trips/day* is years at launch volume. These are the clearest example of severity
  assigned against a hypothetical future rather than the actual first month.
- **`absent-not-lying` (T17, mostly).** T17 filed 15 S1s, the most of any track, and its author is
  right about the axis: safety is where this product is weakest. But the 15 divide sharply. A safety
  feature that *lies* — SOS whose dialog says authorities are notified when nothing can dial 122, a
  share link that reports `ok: true` and delivers a 404 — changes what a frightened person does, and
  is G1. A safety feature that is *absent* — no blocking, no incident taxonomy, no consequence
  attached to `rating_avg` — is a serious gap that an operator can compensate for manually at launch
  scale with a closed captain cohort. Six of T17's S1s moved to G2 on that distinction.
- **`growth, not launch`.** F-19-03 (the referral loop is dead schema; every user shares the literal
  code `GODRIVE`) is described by its author as *"the most expensive gap in the document for a
  pre-launch Egyptian product"*. On acquisition economics, that is probably true. It still does not
  block carrying a passenger.

**Two S2s were promoted to G1**, both for the same reason: the §2.1 launch shape makes cash the only
live payment path, which moves the cash commission debit from a secondary concern to *the* money
path. F-03-11 / F-04-12 — the cash commission debit at `trips.ts:1029-1033` is the only balance
debit in the codebase with no `WHERE wallet_balance >= ?` floor — was reasonably S2 when it was one
of four payment paths. Under cash-only it is the one that runs on every completed trip.

**A further 13 S2s were promoted to G2**, almost all because they participate in a §4 shared root: a
defect that three tracks each filed as "moderate, on my axis" is usually not moderate once the
instances are added up.

### 3.3 The ledger

All 489 S1 and S2 findings, on one ruler, renumbered globally as `S-001…S-489`, sorted by grade then
track. `Orig` preserves the track's own ID and severity so every row is traceable back to its source
document. `Root` links to §4 where the finding is one instance of a shared cause.

| GID | Global | Track | Orig | Calibration | Root | Finding | Evidence |
|---|---|---|---|---|---|---|---|
| S-001 | **G1** | T02 | F-02-02 (S1) | gate: item 3 | — | Payment intention accepts a caller-chosen `amount` and an unvalidated `tripId`; the webhook then marks that trip paid | `routes/payments.ts:13`, `:17`, `:46`, `:71`, `:74`; … |
| S-002 | **G1** | T02 | F-02-03 (S1) | gate: item 10 | R2 | The public trip-tracking link requires a JWT and points at a path that does not exist, so trip sharing is non-functio… | `routes/safety.ts:11` (guard) covering `:90` (route);… |
| S-003 | **G1** | T03 | F-03-08 (S1) | gate: item 4 | R1 | Payout debits the balance, then writes the ledger row non-atomically, with no idempotency key, and nothing ever settl… | `apps/api/src/routes/wallet.ts:113-130` |
| S-004 | **G1** | T03 | F-03-11 (S2) | promoted — cash is the only live path | R1 | Cash commission debit has no balance floor, no ceiling, no collection mechanism | `apps/api/src/routes/trips.ts:1029-1033` |
| S-005 | **G1** | T04 | F-04-03 (S1) | gate: item 3 | — | Trip fare bypass: `amount` and `tripId` are both client-supplied and neither is checked against the trip's fare or ow… | `apps/api/src/routes/payments.ts:12-18`, `:200-206` |
| S-006 | **G1** | T04 | F-04-06 (S1) | gate: item 4 | — | Payout debits the captain's balance into a `status='pending'` row that no code path can ever action. No disbursement … | `apps/api/src/routes/wallet.ts:113-130`; 0 hits for `… |
| S-007 | **G1** | T04 | F-04-12 (S2) | promoted — cash is the only live path | R1 | Cash-commission debit has no balance floor, unlike the rider debit 30 lines above it; nothing blocks a captain in deb… | `apps/api/src/routes/trips.ts:1029-1033` vs `:997-100… |
| S-008 | **G1** | T05 | F-05-01 (S1) | gate: item 6 | — | The rider's `offeredPrice` never reaches settlement on the direct-accept path; the captain is shown a price they will… | `apps/api/src/routes/trips.ts:438,466`, `:861-866`, `… |
| S-009 | **G1** | T06 | F-06-01 (S1) | gate: item 9 | R6 | Scheduled trips are dispatched at **booking** time, not at the scheduled time; the cron only notifies admins and its … | `apps/api/src/routes/trips.ts:483-491`, `518-586`; `a… |
| S-010 | **G1** | T06 | F-06-02 (S1) | gate: item 8 | R5 | A stationary online captain stops being a dispatch candidate after 120 s — location is pushed only on 50 m of movemen… | `apps/captain/lib/services/captain_state.dart:619-626… |
| S-011 | **G1** | T06 | F-06-03 (S1) | gate: item 8 | R5 | Backgrounding the captain app cancels the GPS stream and the offers poll entirely, while D1 keeps `is_online = 1` | `apps/captain/lib/services/captain_state.dart:1083-10… |
| S-012 | **G1** | T06 | F-06-04 (S1) | gate: item 7 | R6 | An unmatched trip never leaves `searching`/`offered`. No timeout, no unfulfilled state, no rider notification — and i… | `apps/api/src/durable-objects/OfferScheduler.ts:102-1… |
| S-013 | **G1** | T07 | F-07-01 (S1) | gate: item 8 | R5 | Captain publishes location 1.7–3.9× faster than the server's own rate limit accepts; excess is 429'd and silently dis… | `apps/captain/lib/services/captain_state.dart:625`, `… |
| S-014 | **G1** | T08 | F-08-01 (S1) | gate: item 5 | R7 | Monthly B2B invoice job runs on the every-minute cron **and** its SUM and its settling UPDATE disagree about timestam… | `apps/api/src/index.ts:267,336,344-346,361` |
| S-015 | **G1** | T08 | F-08-04 (S1) | gate: item 15 | — | No backup or restore capability beyond platform-default Time Travel. No export, no runbook, never rehearsed; restore … | absence across `wrangler.toml`, `package.json`, `apps… |
| S-016 | **G1** | T08 | F-08-20 (S1) | gate: item 5 | R7 | A **second** invoice generator exists at `companies.ts:167` with the mirror defect: it compares raw on both sides, so… | `routes/companies.ts:170-171,176,193` |
| S-017 | **G1** | T09 | F-09-01 (S1) | gate: item 7 | R6 | No active-trip recovery. Force-quit mid-trip and the rider can never get back to the live trip; the 409 that carries … | `app_state.dart:133-175`, `main.dart:116-118`, `fare_… |
| S-018 | **G1** | T10 | F-10-01 (S1) | gate: item 8 | R5 | No Android foreground service: GPS and offer polling stop whenever the app is not in front | `apps/captain/android/app/src/main/AndroidManifest.xm… |
| S-019 | **G1** | T11 | F-11-02 (S1) | gate: item 10 | — | An SOS alert has no admin surface of any kind: no page, and no endpoint to list, view or close one | `apps/api/src/routes/safety.ts:15-51` writes `sos_ale… |
| S-020 | **G1** | T11 | F-11-04 (S1) | gate: item 4 | — | Captain payout requests are unactionable: money leaves the balance into a `pending` row with no endpoint and no scree… | `apps/api/src/routes/wallet.ts:98-135`; no payout han… |
| S-021 | **G1** | T16 | F-16-01 (S1) | gate: item 7 | R6 | A trip that no captain accepts is never expired, and the active-trip guard then locks the rider out of the product pe… | `trips.ts:362-376`, `cleanup.ts:29-75`, `OfferSchedul… |
| S-022 | **G1** | T16 | F-16-02 (S1) | gate: item 9 | R6 | Scheduled rides dispatch at booking time, not at the scheduled time; the cron only notifies admins | `trips.ts:484-490` vs `:518-521`, `index.ts:283-330`,… |
| S-023 | **G1** | T17 | F-17-01 (S1) | gate: item 10 | R2 | The public trip-tracking link is unreachable twice over: the URL handed to the sharer omits the `/safety` mount prefi… | `safety.ts:83`, `index.ts:120`, `safety.ts:11,90` |
| S-024 | **G1** | T17 | F-17-02 (S1) | gate: item 10 | — | The tracking response returns `pickup_address` and `dropoff_address` to an unauthenticated bearer, under a comment cl… | `safety.ts:89,104,119-120` |
| S-025 | **G1** | T17 | F-17-03 (S1) | gate: item 10 | — | Share tokens are never revoked when the trip ends, live up to 7 days, and no cron ever purges them. | `trips.ts:709-737,951-984`; `cleanup.ts:36,49`; `sche… |
| S-026 | **G1** | T17 | F-17-04 (S1) | gate: item 10 | — | `sos_alerts` is INSERT-only: no admin endpoint, no admin screen, no nav entry, and `status`/`resolved_at`/`shared_wit… | `sos_alerts` appears only at `safety.ts:14,22-26`; ze… |
| S-027 | **G1** | T17 | F-17-05 (S1) | gate: item 10 | — | SOS delivery is a best-effort FCM fan-out to every `role='admin'` user; `pushToUser` returns silently when the admin … | `safety.ts:29-39`; `notifications.ts:388-393` |
| S-028 | **G1** | T17 | F-17-06 (S1) | gate: item 10 | — | Neither app can dial 122/123/180, while the rider's confirm dialog states the location will be sent to the authoritie… | `apps/rider/lib/screens/safety/sos_screen.dart:33`; z… |
| S-029 | **G1** | T18 | F-18-08 (S1) | gate: item 3 | — | `payment_method: "wallet"` is accepted at trip creation with no balance check | `apps/api/src/routes/trips.ts:468` |
| S-030 | **G1** | T20 | F-20-01 (S1) | gate: item 3 | — | The entire intercity backend is unreachable from any client; "سفر" mode books an ordinary city ride | `vehicle_selector.dart:33–54`, `home_screen.dart:85,4… |
| S-031 | **G1** | T20 | F-20-16 (S1) | gate: item 5 | R7 | Invoice period predicates are string-based; manual and cron bill different trip sets, and the flag-clearing UPDATE cl… | `companies.ts:174–196`, `index.ts:343–364` — reproduc… |
| S-032 | **G1** | T21 | F-21-01 (S1) | gate: item 11 | — | Production routing points at the OSRM public demo server, whose policy forbids exactly this use and permits withdrawa… | `apps/api/wrangler.toml:148` (prod), `:88`, `:176`; d… |
| S-033 | **G1** | T21 | F-21-02 (S1) | gate: item 11 | — | When OSRM fails, the silent haversine×1.35 fallback becomes the **settled price**, because a negotiated fare is never… | `routing.ts:61-63`, `routing.ts:71`, `trips.ts:969` |
| S-034 | **G1** | T21 | F-21-03 (S1) | gate: item 11 | — | Public Nominatim is used for end-user place search — a use the OSMF policy names as forbidden, and ride-hailing is ca… | `geocode.ts:86-129`, `routes/geocode.ts:26-36`, UA at… |
| S-035 | **G1** | T22 | F-22-01 (S1) | gate: item 14 | R8 | Nothing alerts. No monitor, no notification rule, no external probe exists in any file in the repository. | absence across `wrangler.toml`, `.github/workflows/ci… |
| S-036 | **G1** | T22 | F-22-02 (S1) | gate: item 14 | R8 | `/health` is a static literal that touches no binding, and it is the only gate in the deploy smoke test. | `apps/api/src/index.ts:99-106`; `docs/ci/deploy-api.y… |
| S-037 | **G1** | T22 | F-22-03 (S1) | gate: item 14 | R8 | Cron failure is structurally undetectable: one handler serves both crons, ignores `event.cron`, and swallows every er… | `apps/api/src/index.ts:267`, `279-281`, `329-331`, `3… |
| S-038 | **G1** | T22 | F-22-05 (S1) | gate: item 14 | R8 | The trip lifecycle and fare settlement produce **zero** audit rows. `trips.ts` imports `logAudit` and never calls it. | `apps/api/src/routes/trips.ts:20` (import); 0 call si… |
| S-039 | **G1** | T23 | F-23-01 (S1) | gate: item 1 | R8 | CI is advisory. `main` has no branch protection and no required status checks, so a red run merges | GitHub branch API: `protected:false`, `enforcement_le… |
| S-040 | **G1** | T23 | F-23-02 (S1) | gate: item 2 | R8 | The API deploy pipeline does not exist. PR #46 merged a workflow into `docs/`, not `.github/workflows/` | `docs/ci/deploy-api.yml` exists; `.github/` contains … |
| S-041 | **G1** | T23 | F-23-03 (S1) | gate: item 2 | R8 | The documented deploy command publishes dev config over production | `apps/api/package.json:8` (`wrangler deploy`, no `--e… |
| S-042 | **G1** | T23 | F-23-04 (S1) | gate: item 16 | — | The API has zero automated tests. Two test files exist repo-wide, both in `packages/shared` | 442-blob inventory; `packages/shared/src/{index,fileT… |
| S-043 | **G1** | T25 | F-25-01 (S1) | gate: item 12 | — | No privacy policy exists in the product or the repository | repo-wide search: 3 hits, none a policy; `apps/captai… |
| S-044 | **G1** | T25 | F-25-02 (S1) | gate: item 12 | — | Consent is never recorded: the terms checkbox is client-side only | `apps/rider/lib/screens/login_screen.dart:542`, `apps… |
| S-045 | **G1** | T25 | F-25-03 (S1) | gate: item 12 | — | No data-subject rights mechanism at all — no access, export, correction or erasure | `grep "DELETE FROM users"` → none; no export endpoint… |
| S-046 | **G1** | T25 | F-25-08 (S1) | gate: item 11 | — | Precise trip coordinates are sent to a public demo server with no contract | `routing.ts:28`, `:121`; `wrangler.toml:88` (prod def… |
| S-047 | **G1** | T26 | F-26-01 (S1) | gate: item 13 | — | `targetSdk 34` is below Google Play's current minimum (API 35); API 36 becomes mandatory 31 Aug 2026 | `apps/rider/android/app/build.gradle:51`, `apps/capta… |
| S-048 | **G1** | T26 | F-26-02 (S1) | gate: item 13 | — | Release builds silently fall back to **debug signing** when `key.properties` is missing | `apps/rider/android/app/build.gradle:71`; `key.proper… |
| S-049 | **G1** | T26 | F-26-03 (S1) | gate: item 12 | — | No account-deletion endpoint or UI on either app | `apps/api/src/routes/user.ts` (no `DELETE /user`); ri… |
| S-050 | **G1** | T26 | F-26-07 (S1) | gate: item 13 | — | No CI produces a mobile artefact; builds come from one Windows laptop via stale scripts | `.github/workflows/ci.yml:100-192`, `:22-23`; `script… |
| S-051 | **G1‡** | T03 | F-03-01 (S1) | neutralised by §2.1 shape | R1 | Captain is credited the full payout even when the rider's wallet debit failed for insufficient funds | `apps/api/src/routes/trips.ts:1003` + `:1012` |
| S-052 | **G1‡** | T03 | F-03-02 (S1) | neutralised by §2.1 shape | R1 | Paymob top-up credits `wallet_balance` on every webhook delivery; the `INSERT OR IGNORE` result is discarded | `apps/api/src/routes/payments.ts:175-186` |
| S-053 | **G1‡** | T03 | F-03-03 (S1) | neutralised by §2.1 shape | R1 | The `payment_intentions` settle guard is read-then-write with an unconditional UPDATE | `apps/api/src/routes/payments.ts:166` vs `:223-227` |
| S-054 | **G1‡** | T03 | F-03-04 (S1) | neutralised by §2.1 shape | — | `type='intercity_booking'` violates the `wallet_transactions` CHECK; the handler has no try/catch | `apps/api/src/routes/payments.ts:215-220` vs `migrati… |
| S-055 | **G1‡** | T03 | F-03-05 (S1) | neutralised by §2.1 shape | — | Card-paid intercity bookings are never charged — seat, QR and booking are issued for free | `apps/api/src/routes/intercity.ts:105`, `:149` |
| S-056 | **G1‡** | T03 | F-03-06 (S1) | neutralised by §2.1 shape | — | No refund path exists for city trips; a card-prepaid rider who cancels loses 100% | `apps/api/src/routes/trips.ts:709-827`, esp. `:728` |
| S-057 | **G1‡** | T04 | F-04-01 (S1) | neutralised by §2.1 shape | R1 | Webhook credits the wallet with an unguarded `UPDATE`, then marks the intention settled 40 lines later. A retry after… | `apps/api/src/routes/payments.ts:175-186`, `:223` |
| S-058 | **G1‡** | T04 | F-04-02 (S1) | neutralised by §2.1 shape | — | `purpose='intercity_booking'` inserts a `wallet_transactions.type` value the CHECK constraint forbids. Handler throws… | `apps/api/src/routes/payments.ts:213-220` vs `migrati… |
| S-059 | **G1‡** | T04 | F-04-04 (S1) | neutralised by §2.1 shape | — | No refund, reversal or chargeback handling exists. A refund callback is swallowed by the settled-status dedupe; the w… | `apps/api/src/routes/payments.ts:166-168`; 0 hits rep… |
| S-060 | **G1‡** | T04 | F-04-05 (S1) | neutralised by §2.1 shape | — | No reconciliation whatsoever: no Paymob transaction-inquiry call, no stale-intention sweep, no cron, no admin view. | 0 hits for `inquiry`/`reconcil`(financial); `apps/api… |
| S-061 | **G1‡** | T05 | F-05-02 (S1) | neutralised by §2.1 shape | — | Rider offer has absolute bounds only — no relation to the estimate | `apps/api/src/lib/schemas.ts:59` |
| S-062 | **G1‡** | T05 | F-05-03 (S1) | neutralised by §2.1 shape | — | Captain counter-offer has absolute bounds only, and the counter **is** the settled price | `apps/api/src/lib/schemas.ts:77`; `apps/api/src/route… |
| S-063 | **G1‡** | T05 | F-05-04 (S1) | neutralised by §2.1 shape | — | Accepting a bid silently voids the rider's promo discount | `apps/api/src/routes/trips.ts:428-429` vs `:1299-1310… |
| S-064 | **G1‡** | T05 | F-05-05 (S1) | neutralised by §2.1 shape | — | `promo_codes.uses_count` is read then incremented with no atomic guard | `apps/api/src/routes/trips.ts:418` and `:500` |
| S-065 | **G1‡** | T05 | F-05-06 (S1) | neutralised by §2.1 shape | — | Promo uses are never released on cancellation, and cancelling is free | `apps/api/src/routes/trips.ts:493-504`, `:709-827` |
| S-066 | **G1‡** | T05 | F-05-07 (S1) | neutralised by §2.1 shape | — | The promo discount is funded ~85% by the captain, not the platform | `apps/api/src/routes/trips.ts:428-429`, `:969-971` |
| S-067 | **G1‡** | T05 | F-05-08 (S1) | neutralised by §2.1 shape | — | Unlimited bid spam: no dedup, no rate limit, no expiry on `trip_bids` | `apps/api/src/routes/trips.ts:1144-1175`; `migrations… |
| S-068 | **G1‡** | T05 | F-05-12 (S1) | neutralised by §2.1 shape | R1 | A wallet trip completes even when the rider's debit fails | `apps/api/src/routes/trips.ts:997-1010` |
| S-069 | **G1‡** | T18 | F-18-01 (S1) | neutralised by §2.1 shape | R1 | Wallet trip credits the captain even when the rider debit fails — the platform mints money | `apps/api/src/routes/trips.ts:993-1011` vs `:1036-105… |
| S-070 | **G1‡** | T18 | F-18-04 (S1) | neutralised by §2.1 shape | — | Self-service payout is instant: no hold period, no admin approval, no minimum account age, no clawback path | `apps/api/src/routes/wallet.ts:98-142` |
| S-071 | **G1‡** | T18 | F-18-05 (S1) | neutralised by §2.1 shape | — | Promo redemption has no per-user cap, no first-trip rule, is consumed at creation and never returned on cancel | `apps/api/src/routes/trips.ts:399-426`, `:493-503`; `… |
| S-072 | **G1‡** | T18 | F-18-09 (S1) | neutralised by §2.1 shape | R1 | PSP webhook replay double-credits the wallet: `INSERT OR IGNORE` on the transaction, then an unconditional balance up… | `apps/api/src/routes/payments.ts:175-182` |
| S-073 | **G1‡** | T20 | F-20-02 (S1) | neutralised by §2.1 shape | — | `paymentMethod:"card"` creates a paid-status booking that is never charged | `schemas.ts:122`, `intercity.ts:105–171`, `payments.t… |
| S-074 | **G1‡** | T20 | F-20-15 (S1) | neutralised by §2.1 shape | — | Every employee trip is auto-billed to the employer with no opt-in and no policy check | `trips.ts:431–436,477–479,993` |
| S-075 | **G1‡** | T20 | F-20-17 (S1) | neutralised by §2.1 shape | R3 | `spend_limit_month`, `allowed_vehicle_types`, `allowed_hours`, `credit_limit` are never enforced anywhere | grep across `apps/api/`; only `companies.ts:27–28,76,… |
| S-076 | G2 | T01 | F-01-01 (S1) | local-bar | — | Refresh rotation is non-atomic and has no reuse detection | `apps/api/src/routes/auth.ts:279-295` |
| S-077 | G2 | T01 | F-01-02 (S1) | local-bar | — | Logout is client-only; no app ever calls `POST /auth/logout` | `apps/rider/lib/services/app_state.dart:452-455`; `ap… |
| S-078 | G2 | T01 | F-01-03 (S1) | local-bar | — | Bot defence protects only the suspended OTP route; `/login` and `/register` have none, and Turnstile fails open | `apps/api/src/routes/auth.ts:71`; `apps/api/src/lib/t… |
| S-079 | G2 | T02 | F-02-01 (S1) | local-bar | R2 | `POST /trips/estimate` is registered above the auth middleware and runs unauthenticated, returning live captain ident… | `apps/api/src/routes/trips.ts:315`, guard at `:346`, … |
| S-080 | G2 | T03 | F-03-07 (S1) | local-bar | — | The ledger is not double-entry and has no platform account, so it cannot balance | `migrations/0003_global_transport.sql:27-39` |
| S-081 | G2 | T03 | F-03-09 (S1) | local-bar | R1 | Three endpoints return three different balances; the captain's displayed balance is not the one that gates their payo… | `apps/api/src/routes/wallet.ts:24`, `:58-72`, `:104-1… |
| S-082 | G2 | T05 | F-05-09 (S1) | local-bar | — | OSRM failure silently reprices the trip ~+28% with no log, metric or signal | `apps/api/src/lib/routing.ts:61-62`, `:66-82` |
| S-083 | G2 | T05 | F-05-10 (S1) | local-bar | — | The vehicle-class multiplier is never applied server-side — XL is priced as economy | `migrations/0002_enhancements.sql:83-93`; `apps/api/s… |
| S-084 | G2 | T05 | F-05-11 (S1) | local-bar | R3 | No cancellation or no-show fee exists; the admin settings for it are dead | `migrations/0016_system_config.sql:36`; `apps/api/src… |
| S-085 | G2 | T06 | F-06-05 (S1) | local-bar | — | A captain cancelling after accepting kills the trip outright — no re-dispatch, no return to the queue | `apps/api/src/routes/trips.ts:709-737`, `753` |
| S-086 | G2 | T06 | F-06-06 (S2) | promoted | — | The staged wave rollout is defeated by two parallel channels: FCM blasts all 10 candidates at t=0, and `GET /captain/… | `apps/api/src/routes/trips.ts:574-585`; `apps/api/src… |
| S-087 | G2 | T07 | F-07-02 (S1) | local-bar | — | Per-connection session state lives only in an in-memory `Map` while sockets are accepted through the Hibernation API;… | `apps/api/src/durable-objects/TripRoom.ts:30-31`, `:1… |
| S-088 | G2 | T07 | F-07-03 (S1) | local-bar | — | The `CaptainInbox` relay is an in-memory field; when the shared object is evicted the proxy dies while the client's s… | `apps/api/src/durable-objects/CaptainInbox.ts:9`, `:9… |
| S-089 | G2 | T07 | F-07-04 (S1) | local-bar | — | Every captain offer socket in the fleet enters through a single shared Durable Object named `"pending-auth"` | `apps/api/src/index.ts:226-229`; `apps/captain/lib/se… |
| S-090 | G2 | T07 | F-07-05 (S1) | local-bar | R4 | The rider can never receive a chat message in real time — no `chat.message` handler exists anywhere in the rider app,… | `apps/rider/lib/screens/trip/trip_chat_screen.dart:19… |
| S-091 | G2 | T07 | F-07-06 (S1) | local-bar | — | No role check on the inbound `location` frame: any authenticated participant can inject the captain's position | `apps/api/src/durable-objects/TripRoom.ts:167-178` |
| S-092 | G2 | T07 | F-07-07 (S2) | promoted | — | The staged offer rollout is defeated by an immediate FCM blast to all ten captains and by an unscoped REST offers end… | `apps/api/src/routes/trips.ts:572-585`; `apps/api/src… |
| S-093 | G2 | T08 | F-08-02 (S1) | local-bar | R7 | Two timestamp producers write two formats into the same TEXT columns; 5 sites compare them raw, 8 normalise | `lib/utils.ts:5`; `routes/trips.ts:442-450`; raw at `… |
| S-094 | G2 | T09 | F-09-02 (S1) | local-bar | — | The live trip shows the **system estimate**, not the price the rider negotiated. `accepted_price` is never read anywh… | `trip_screen.dart:503`, `:531`, `:737`, vs `trips.ts:… |
| S-095 | G2 | T09 | F-09-03 (S1) | local-bar | R4 | Rider chat only fetches on open and after the rider sends. A captain's reply is invisible until the rider happens to … | `trip_chat_screen.dart:22`, `:64` (no `Timer`, no WS)… |
| S-096 | G2 | T10 | F-10-02 (S1) | local-bar | — | The rotated refresh token is discarded, forcing a logout roughly every 30 minutes | `apps/captain/lib/services/captain_state.dart:266-267… |
| S-097 | G2 | T10 | F-10-03 (S1) | local-bar | — | "Turn-by-turn navigation" has no turns and no voice | `apps/captain/lib/services/captain_state.dart:178-186… |
| S-098 | G2 | T10 | F-10-04 (S1) | local-bar | R1 | Wallet balance omits cash-trip commission debt and disagrees with the payout guard | `apps/api/src/routes/wallet.ts:57-72` vs `:101-108`, … |
| S-099 | G2 | T10 | F-10-05 (S1) | local-bar | — | No rider-presented code at trip start | `apps/api/src/routes/trips.ts:891-948` |
| S-100 | G2 | T10 | F-10-06 (S1) | local-bar | — | Offer arrival is completely silent | `apps/captain/pubspec.yaml:10-42`; `packages/flutter_… |
| S-101 | G2 | T10 | F-10-22 (S2) | promoted | R5 | Location pushes are silently dropped above roughly 20 km/h | `apps/api/src/routes/captain.ts:190-197`; `apps/capta… |
| S-102 | G2 | T11 | F-11-01 (S1) | local-bar | — | There is no trip detail view. Investigation is a table row and two raw UUIDs — no timeline, bids, GPS path, chat, or … | `apps/admin/src/pages/TripsPage.tsx:275-284` (no `onR… |
| S-103 | G2 | T11 | F-11-03 (S1) | local-bar | — | Trip and user lists silently truncate to the 200 most recent rows while presenting a search box that only filters tho… | `apps/api/src/routes/admin.ts:320`, `:328-330`; `apps… |
| S-104 | G2 | T11 | F-11-05 (S1) | local-bar | — | The entire B2B line has no console. Companies cannot be created, credit limits cannot be set, and the monthly invoice… | `apps/api/src/routes/companies.ts:68` (9 admin endpoi… |
| S-105 | G2 | T11 | F-11-06 (S1) | local-bar | — | One undifferentiated `admin` role. A junior verification agent can change national pricing and commission | `apps/api/src/middleware/auth.ts:67-74`; `apps/api/sr… |
| S-106 | G2 | T12 | F-12-01 (S1) | local-bar | — | The product ships under two different names. Every user-visible surface says "GoDrive"; every push notification says … | `packages/flutter_shared/lib/services/fcm_service.dar… |
| S-107 | G2 | T12 | F-12-02 (S1) | local-bar | — | The dark-mode primary action colour is `lime #C1F11D` — the signature colour of inDrive, the direct competitor whose … | `app_theme.dart:137`, bound as `action` at `:404` |
| S-108 | G2 | T12 | F-12-03 (S1) | local-bar | R4 | The rider SOS screen hardcodes light-mode tokens and renders a white panel in dark mode. | `apps/rider/lib/screens/safety/sos_screen.dart:31,116… |
| S-109 | G2 | T12 | F-12-04 (S1) | local-bar | — | Admin and mobile ship different brand greens. Mobile is `#4E842D`; the admin console renders `#6BB522`. | `app_theme.dart:36` vs `apps/admin/src/design/globals… |
| S-110 | G2 | T12 | F-12-10 (S2) | promoted | R4 | Rider chat bubbles use physical `Alignment`, inverting them in RTL. Own messages appear on the left in Arabic. | `apps/rider/lib/screens/trip/trip_chat_screen.dart:97… |
| S-111 | G2 | T13 | F-13-01 (S1) | local-bar | — | Rider bid list is replaced wholesale every 5 s with no insertion animation, no stable keys and no confirmation on acc… | `captain_bids_sheet.dart:75`, `:104`, `:219`, `:282`,… |
| S-112 | G2 | T13 | F-13-08 (S2) | promoted | R4 | Zero reduce-motion gating anywhere in the captain app; five looping animations run unconditionally | `apps/captain/lib` grep → 0; `splash_screen.dart:45`,… |
| S-113 | G2 | T14 | F-14-01 (S1) | local-bar | R3 | The ARB / `gen-l10n` pipeline is dead code: `AppLocalizations.delegate` is registered in neither app, so all 208 ARB … | `apps/rider/lib/main.dart:59-63`; `apps/captain/lib/m… |
| S-114 | G2 | T14 | F-14-02 (S1) | local-bar | — | Selecting English leaves most of the rider UI in Arabic — 359 inline Arabic literals and 201 orphaned catalogue membe… | `apps/rider/lib/screens/profile/settings_screen.dart:… |
| S-115 | G2 | T14 | F-14-03 (S1) | local-bar | — | English API error text reaches Arabic users on every failure path; ~62 of ~71 codes carry English messages and the cl… | `packages/flutter_shared/lib/services/api_client.dart… |
| S-116 | G2 | T14 | F-14-11 (S2) | promoted | R4 | Rider chat bubbles use physical `Alignment`; the captain app already uses `AlignmentDirectional` | `apps/rider/lib/screens/trip/trip_chat_screen.dart:97… |
| S-117 | G2 | T15 | F-15-01 (S1) | local-bar | R3 | Admin's AA-compliant palette is dead code; the failing palette renders. White label on primary button = 2.54:1 | `main.tsx:8`, `tokens.ts:32/57/63/69/75`, `tailwind.c… |
| S-118 | G2 | T15 | F-15-02 (S1) | local-bar | — | Keyboard-only ops user cannot open any captain's document group — the accordion header is a bare `<div onClick>` | `CaptainVerificationPage.tsx:752–754` |
| S-119 | G2 | T15 | F-15-03 (S1) | local-bar | — | Flutter night theme fails AA on every semantic colour (3.29–3.99:1); night badges measure 1.49–1.98:1 | `app_theme.dart:36,49,59–63,89–96` vs `:127–128` |
| S-120 | G2 | T15 | F-15-04 (S1) | local-bar | — | A blind rider cannot request a trip. Vehicle selection exposes no role and no selected state | `vehicle_selector.dart:344`, `:93` |
| S-121 | G2 | T15 | F-15-05 (S1) | local-bar | — | Zero live-region announcements anywhere. Every realtime transition is silent — including *captain cancelled* | no `liveRegion`/`SemanticsService.announce` in repo; … |
| S-122 | G2 | T15 | F-15-06 (S1) | local-bar | — | Rider's in-trip back and SOS buttons are unlabelled `GestureDetector`s at 44dp | `trip_screen.dart:282,286` → def at `:396–409` |
| S-123 | G2 | T15 | F-15-07 (S1) | local-bar | — | `RejectionReasonModal` has no dialog role, no Escape, no focus management, no live error | `RejectionReasonModal.tsx:92–97,125–128,183–191` (no … |
| S-124 | G2 | T15 | F-15-08 (S1) | local-bar | — | Captain app caps text scale at 1.3×; a captain who set 200% gets 130% | `apps/captain/lib/main.dart:70–73` |
| S-125 | G2 | T15 | F-15-09 (S1) | local-bar | R4 | Captain splash runs five simultaneous looping animations with no reduced-motion guard | `captain/splash_screen.dart:43–47,231,371–411,417–445… |
| S-126 | G2 | T15 | F-15-10 (S1) | local-bar | — | The map is a total screen-reader dead zone in both apps | `trip_screen.dart:254–274,327–393`; `home_screen.dart… |
| S-127 | G2 | T15 | F-15-11 (S2) | promoted | — | Admin focus ring `#6bb522` = 2.54:1, below the 3:1 UI floor; `Button.tsx` then suppresses it and specifies no ring co… | `styles.css:135–138`; `Button.tsx:34` |
| S-128 | G2 | T16 | F-16-03 (S1) | local-bar | — | The cancellation policy is configured, admin-editable, and never enforced | `migrations/0016:36-37`, `admin.ts:429-430`, `trips.t… |
| S-129 | G2 | T17 | F-17-07 (S1) | local-bar | — | No blocking exists — no table, endpoint, UI or filter — and the dispatch signature cannot express one: `findNearbyCap… | `nearby.ts:62-68`; `GeoCell.ts` `/nearby` contract; z… |
| S-130 | G2 | T17 | F-17-08 (S1) | local-bar | — | Ratings are one-way in practice: only a captain gets an aggregate, `users` has no rating columns, and no captain-side… | `trips.ts:1121`; `migrations/0001_init.sql:3-13`; `ap… |
| S-131 | G2 | T17 | F-17-09 (S1) | local-bar | R3 | `rating_avg` has no consequence anywhere — not in dispatch, not in bid ordering, not in any threshold or review trigg… | `nearby.ts` and `GeoCell.ts` never read it; `trips.ts… |
| S-132 | G2 | T17 | F-17-10 (S1) | local-bar | — | Document expiry is never enforced: no `expired` status exists, the online gate checks only `approval_status`, and no … | `migrations/0002_enhancements.sql:31-32`; `captain.ts… |
| S-133 | G2 | T17 | F-17-11 (S1) | local-bar | — | No liveness, selfie or face-match check exists; identity is an admin eyeballing an uploaded photo against self-typed … | zero matches for `selfie\ |
| S-134 | G2 | T17 | F-17-12 (S1) | local-bar | — | A captain can change plate/make/model after approval with no re-review, and no insurance or inspection document type … | `captain.ts:26-78`; `captains` DDL `migrations/0001_i… |
| S-135 | G2 | T17 | F-17-13 (S1) | local-bar | — | Suspension does not revoke live sessions; `authMiddleware` never re-checks `users.status`. | `admin.ts:289-310`; `middleware/auth.ts:29-65`; `jwt.… |
| S-136 | G2 | T17 | F-17-14 (S1) | local-bar | — | Riders cannot be banned at all — no suspend endpoint and a read-only admin users page. | `admin.ts:326`; `apps/admin/src/pages/UsersPage.tsx` … |
| S-137 | G2 | T17 | F-17-15 (S1) | local-bar | — | There is no incident/report concept: no table, no report endpoint, no category taxonomy, no ops queue, no SLA, no law… | no incident/report table in any of the 19 migrations;… |
| S-138 | G2 | T18 | F-18-02 (S1) | local-bar | — | No proximity, duration or distance check on any trip state transition — a complete fake trip is three API calls | `apps/api/src/routes/trips.ts:891-941`, `:951-981`; `… |
| S-139 | G2 | T18 | F-18-03 (S1) | local-bar | — | Captain position is accepted verbatim: no speed, teleport, accuracy, timestamp or mock-location check, and the presen… | `apps/api/src/routes/captain.ts:205-221`; `apps/api/s… |
| S-140 | G2 | T18 | F-18-06 (S1) | local-bar | — | A ban does not stop the next request: `authMiddleware` never reads the database, so a suspended captain keeps full ac… | `apps/api/src/middleware/auth.ts:29-65`; `apps/api/sr… |
| S-141 | G2 | T18 | F-18-07 (S1) | local-bar | — | Nothing durable identifies a person or a handset: phone is not unique, `/register` has no captcha, and an FCM token r… | `apps/api/src/routes/auth.ts:347-384`; `apps/api/src/… |
| S-142 | G2 | T18 | F-18-10 (S1) | local-bar | — | There is no risk subsystem at all: no fraud tables in 19 migrations, no score, no velocity rule, no review queue, no … | repo-wide search for `fraud`/`risk`/`velocity`/`flag`… |
| S-143 | G2 | T19 | F-19-01 (S1) | local-bar | R3 | The `NOTIFICATIONS` queue has **no producer**. Nothing anywhere calls `env.NOTIFICATIONS.send`. Every notification is… | `wrangler.toml:46-55`; recursive grep of `apps/api/sr… |
| S-144 | G2 | T19 | F-19-02 (S1) | local-bar | — | The queue **consumer would crash on its first message**: it types the batch as `Message[]` and iterates it directly, … | `index.ts:244-245`, `try` at `:247` |
| S-145 | G2 | T19 | F-19-04 (S1) | local-bar | — | **No deep linking, and every notification tap is discarded.** `onTap` is never passed to `FcmService.init`; no URL sc… | `fcm_service.dart:25,43,49,100`; `app_state.dart:154,… |
| S-146 | G2 | T19 | F-19-05 (S1) | local-bar | — | **No notification preferences, no transactional/promotional split, no quiet hours.** `pushToUser` sends to every toke… | `notifications.ts:380-409`; migrations grep |
| S-147 | G2 | T21 | F-21-04 (S1) | local-bar | R2 | No route cache exists at all, and the endpoint that calls OSRM is unauthenticated and IP-keyed | `trips.ts:315` vs `trips.ts:346`; `index.ts:112`; `ra… |
| S-148 | G2 | T21 | F-21-05 (S2) | promoted | R3 | Tile attribution is defined, documented as legally required, and never rendered in either Flutter app | `app_theme.dart:495` (defined); zero usages in `apps/… |
| S-149 | G2 | T22 | F-22-04 (S1) | local-bar | R8 | No correlation id anywhere in the stack — client, Worker, or Durable Objects. | `packages/flutter_shared/lib/services/api_client.dart… |
| S-150 | G2 | T22 | F-22-11 (S2) | promoted | — | `deploy.sh` applies one hardcoded migration, runs D1 against the **local** database, and deploys **without** `--env p… | `deploy.sh:30` (migration 0009 of 19), `deploy.sh:40`… |
| S-151 | G2 | T23 | F-23-05 (S1) | local-bar | — | Migration/deploy ordering is unenforced, and two migrations post-date the last audit and deploy | `docs/DEPLOYMENT.md:74-79` says 17 recorded, "Nothing… |
| S-152 | G2 | T23 | F-23-06 (S1) | local-bar | — | `check_migrations_apply.py` asserts nothing about the resulting schema | `scripts/check_migrations_apply.py:77-80` computes a … |
| S-153 | G2 | T23 | F-23-07 (S1) | local-bar | — | Staging is a stub: placeholder D1 id, no KV/R2/DO/queues/crons | `wrangler.toml:167` `"staging-d1-database-id-placehol… |
| S-154 | G2 | T23 | F-23-08 (S1) | local-bar | — | No rollback procedure for either a bad deploy or a bad migration | No rollback step in `docs/ci/deploy-api.yml`; no proc… |
| S-155 | G2 | T23 | F-23-09 (S1) | local-bar | — | No feature-flag mechanism, so nothing can ship dark | Only runtime toggle is `DEV_OTP` via `c.env`; `system… |
| S-156 | G2 | T23 | F-23-17 (S2) | promoted | — | `apps/api/deploy.sh` is a hazardous relic pinned to migration 0009 | `deploy.sh:30` hard-codes `0009`; `:40` uses `d1 exec… |
| S-157 | G2 | T25 | F-25-04 (S1) | local-bar | — | Identity-document images are never deleted from R2 | `FILES.delete` exists only at `user.ts:186,235` (avat… |
| S-158 | G2 | T25 | F-25-05 (S1) | local-bar | — | Superseded documents are orphaned: the DB row is deleted, the R2 object is not | `captain.ts:567` deletes the row holding `r2_key`; no… |
| S-159 | G2 | T25 | F-25-06 (S1) | local-bar | — | Staff access to national IDs is entirely unaudited | `admin.ts:894-922`, `:620-679`, `:229-258` — no `logA… |
| S-160 | G2 | T25 | F-25-07 (S1) | local-bar | R2 | `trip_path_points` retains a 30-second-resolution movement trace forever | `0002_enhancements.sql:14-22`; written `captain.ts:24… |
| S-161 | G2 | T25 | F-25-09 (S1) | local-bar | — | National ID numbers stored and returned in plaintext, in bulk | `0015:15`, `0012:11`; `SELECT c.*` at `admin.ts:229-2… |
| S-162 | G2 | T25 | F-25-10 (S1) | local-bar | — | No breach-detection or breach-notification capability exists | no alerting, no access log, no runbook in repo |
| S-163 | G2 | T26 | F-26-04 (S1) | local-bar | — | No force-upgrade / minimum-version gate anywhere | `apps/api/src/index.ts:99-105`; `migrations/0003_glob… |
| S-164 | G2 | T26 | F-26-05 (S1) | local-bar | — | Background location declared on iOS, removed on Android, implemented on neither | `apps/rider/ios/Runner/Info.plist:56-60`, `apps/capta… |
| S-165 | G2 | T26 | F-26-06 (S1) | local-bar | — | Firebase config files absent and the Firebase project may not exist, while the google-services plugin is applied and … | `build.gradle:7`, `main.dart:20`, `.gitignore:75-76`,… |
| S-166 | G2 | T26 | F-26-08 (S1) | local-bar | — | Every build defaults to the production API; tester and debug builds write to production D1 | `apps/rider/lib/services/app_state.dart:69-71`, `apps… |
| S-167 | G2 | T26 | F-26-18 (S2) | promoted | R3 | Push platform is hardcoded to `'android'` | `apps/captain/lib/services/captain_state.dart:1113`, … |
| S-168 | G2 | T27 | F-27-01 (S1) | local-bar | R4 | Rider renders chat history in reverse chronological order; captain renders it correctly | API `ORDER BY created_at DESC` `apps/api/src/routes/s… |
| S-169 | G2 | T27 | F-27-02 (S1) | local-bar | R4 | Rider chat has no realtime path and no poll — captain messages never arrive while the screen is open | rider `initState` fetches once `apps/rider/lib/screen… |
| S-170 | G2 | T27 | F-27-03 (S1) | local-bar | — | SOS notifies administrators only; the other occupant of the vehicle is never told | `apps/api/src/routes/safety.ts:29-39` — fanout is `WH… |
| S-171 | G2 | T27 | F-27-04 (S1) | local-bar | R1 | "Available balance" is two different computations behind one label | rider = `users.wallet_balance` `apps/api/src/routes/w… |
| S-172 | G2 | T27 | F-27-06 (S2) | promoted | R6 | A trip with no captain never resolves — no timeout, no status, no notification | no expiry logic in `apps/api/src/routes/trips.ts`; ri… |
| S-173 | G2 | T27 | F-27-14 (S2) | promoted | R4 | The canonical state machine is TypeScript-only; both Flutter apps re-declare it by hand | `packages/shared/src/index.ts:40-48`; rider re-declar… |
| S-174 | G3 | T01 | F-01-04 (S2) | — | — | No password policy; `/register` bypasses Zod entirely | `apps/api/src/routes/auth.ts:348-357` |
| S-175 | G3 | T01 | F-01-04b (S2) | — | — | No password-change and no account-recovery flow exists anywhere | `apps/api/src/routes/user.ts` (whole file) |
| S-176 | G3 | T01 | F-01-05 (S2) | — | — | Rate limiter is fail-open, racy, and per-IP only; no per-account lockout | `apps/api/src/middleware/rateLimit.ts:27-53` |
| S-177 | G3 | T01 | F-01-06 (S2) | — | — | Access tokens are not revocable; ban and logout leave a ≤15-min live window | `apps/api/src/routes/admin.ts:289-309`; `apps/api/src… |
| S-178 | G3 | T01 | F-01-07 (S2) | — | — | Admin bearer + 30-day refresh token in `localStorage` | `apps/admin/src/lib/auth.tsx:46-48` |
| S-179 | G3 | T01 | F-01-08 (S2) | — | — | CORS trusts every `*.synapticstudio.tech` subdomain | `apps/api/src/index.ts:46-47` |
| S-180 | G3 | T01 | F-01-09 (S2) | — | — | No device binding on sessions at all | `apps/api/src/routes/devices.ts:1-42` |
| S-181 | G3 | T01 | F-01-10 (S2) | — | — | Legacy unsalted SHA-256 password hashes still authenticate | `apps/api/src/lib/utils.ts:93-98` |
| S-182 | G3 | T01 | F-01-11 (S2) | — | — | Captain app discards rotated refresh tokens (rider does not) | `apps/captain/lib/services/captain_state.dart:262-268… |
| S-183 | G3 | T01 | F-01-12 (S2) | — | — | No single-flight guard on client refresh | `apps/rider/lib/services/app_state.dart:294-306`; `ap… |
| S-184 | G3 | T01 | F-01-13 (S2) | — | — | Suspended OTP surface still mounted; still mints users and 30-day sessions | `apps/api/src/routes/auth.ts:52`, `:131`, `:191-219` |
| S-185 | G3 | T02 | F-02-04 (S2) | — | — | `role` is trusted from the JWT for the life of the access token and `users.status` is never checked on protected requ… | `middleware/auth.ts:55-60`; role claim `lib/jwt.ts:19… |
| S-186 | G3 | T02 | F-02-05 (S2) | — | — | There is no admin sub-role. Every admin is omnipotent | `middleware/auth.ts:67`; `requireRole("admin")` `rout… |
| S-187 | G3 | T02 | F-02-06 (S2) | — | — | Audit writes fail silently — the insert is wrapped in a swallow-all catch and no call site checks a result | `lib/audit.ts:33-36`; all nine call sites e.g. `route… |
| S-188 | G3 | T02 | F-02-07 (S2) | — | — | Admin document images may authenticate via `?token=`, and the token accepted is a full admin JWT, not a scoped one | allowlist `middleware/auth.ts:21-27`, entry at `:25`;… |
| S-189 | G3 | T02 | F-02-08 (S2) | — | — | Any online captain can bid on any open trip; there is no check that they were dispatched or offered it | `routes/trips.ts:1144`; status check `:1157`; online … |
| S-190 | G3 | T02 | F-02-09 (S2) | — | — | The captain trip list returns `SELECT *` for every open trip in the city, not only dispatched ones | `routes/trips.ts:634-637` |
| S-191 | G3 | T02 | F-02-10 (S2) | — | — | `POST /safety/sos` accepts an arbitrary `tripId` with no participant check | `routes/safety.ts:15`, insert at `:22-25`; admin fan-… |
| S-192 | G3 | T03 | F-03-10 (S2) | — | — | No money path is atomic anywhere; `DB.batch` is never used in a financial path | `trips.ts:997-1053`, `intercity.ts:150-170`, `:283-29… |
| S-193 | G3 | T03 | F-03-12 (S2) | — | R3 | The integer-piastre layer is inert: written 5×, read 0×, skipped by 3 writers; `trips.*_piastres` written 0× | `migrations/0005_integer_currency_and_idempotency.sql… |
| S-194 | G3 | T03 | F-03-13 (S2) | — | — | All revenue reporting reads `trips`, never the ledger | `admin.ts:28-29`, `:88-89`, `:115-116`, `:162-163`, `… |
| S-195 | G3 | T03 | F-03-14 (S2) | — | — | `promo_codes.max_uses` is enforced by a TOCTOU read-then-write with an unguarded increment; no per-user cap exists at… | `apps/api/src/routes/trips.ts:402-418` then `:500` |
| S-196 | G3 | T03 | F-03-15 (S2) | — | — | Accepting a captain's bid silently discards the rider's promo discount | `apps/api/src/routes/trips.ts:1299-1310` |
| S-197 | G3 | T03 | F-03-16 (S2) | — | — | `pricing?.commission_rate \ | \ |
| S-198 | G3 | T03 | F-03-17 (S2) | — | — | Failed payments are written as `direction='credit'` rows with NULL `amount_piastres` | `apps/api/src/routes/payments.ts:234-239`, `:288-293` |
| S-199 | G3 | T03 | F-03-18 (S2) | — | — | Refunds, voids and chargebacks are entirely unhandled; `is_refunded`/`is_voided` arrive signed and are never read | `apps/api/src/lib/paymob.ts:173`, `:175`; `payments.t… |
| S-200 | G3 | T03 | F-03-19 (S2) | — | — | The webhook accepts the HMAC from the query string and never checks `created_at` freshness | `apps/api/src/routes/payments.ts:103`; `paymob.ts:164` |
| S-201 | G3 | T03 | F-03-20 (S2) | — | — | The captain's only commission figure is rounded to whole pounds | `apps/captain/lib/screens/earnings/wallet_screen.dart… |
| S-202 | G3 | T03 | F-03-21 (S2) | — | — | Top-up asserts success from a liveness probe, and Arabic-Indic digit entry is a silent dead button | `apps/rider/lib/screens/wallet/topup_screen.dart:91-9… |
| S-203 | G3 | T03 | F-03-22 (S2) | — | — | Admin analytics: GMV and leaderboard use different time buckets, and the finance CSV contains a fabricated `cancelled… | `apps/admin/src/pages/AnalyticsPage.tsx:147`, `:197`,… |
| S-204 | G3 | T03 | F-03-23 (S2) | — | — | Webhook audit rows are silently discarded by an FK violation on `actor_id='paymob'` | `apps/api/src/routes/payments.ts:107`, `:150`; `migra… |
| S-205 | G3 | T03 | F-03-24 (S2) | — | — | The captain involuntarily funds ~80% of every promo discount, unlabelled and unreported | `apps/api/src/routes/trips.ts:428-429`, `:971` |
| S-206 | G3 | T04 | F-04-07 (S2) | — | R1 | Two contradictory captain balances: the app displays a computed net that ignores cash-commission debits; the payout e… | `apps/api/src/routes/wallet.ts:58-72` vs `:104-111`; … |
| S-207 | G3 | T04 | F-04-08 (S2) | — | — | Currency is client-supplied, unvalidated, and never compared at settlement — the webhook's SELECT does not even read … | `apps/api/src/routes/payments.ts:14`, `:131-143`, `:1… |
| S-208 | G3 | T04 | F-04-09 (S2) | — | — | Stub mode is reachable in production. No environment declares the Paymob vars, no deploy-time assertion, and the clie… | `apps/api/src/lib/paymob.ts:117-127`; `apps/api/wrang… |
| S-209 | G3 | T04 | F-04-10 (S2) | — | — | The rider's payment-method choice never reaches the server — `createTrip` hardcodes `'cash'`. | `apps/rider/lib/services/app_state.dart:504`; UI at `… |
| S-210 | G3 | T04 | F-04-11 (S2) | — | R3 | Payout debits `wallet_balance` but not `wallet_balance_piastres`; the integer ledger drifts on every withdrawal. | `apps/api/src/routes/wallet.ts:113-117` (compare `app… |
| S-211 | G3 | T04 | F-04-13 (S2) | — | — | Webhook has no IP allow-list; only a global 120/min soft limit that fails **open** on KV error. | `apps/api/src/index.ts:59-66`; `apps/api/src/middlewa… |
| S-212 | G3 | T04 | F-04-14 (S2) | — | — | Intentions never expire: no `expires_at`, no status CHECK, no sweep. A stale intention can settle after its trip ende… | `migrations/0011_payment_intentions.sql:8-19`; no cle… |
| S-213 | G3 | T04 | F-04-15 (S2) | — | — | No operational surface for payments: no `payment_intentions` view, no manual credit, no refund, no payout queue in ad… | `payment_intention` has 0 hits outside `payments.ts` … |
| S-214 | G3 | T04 | F-04-16 (S2) | — | — | Failed payments insert a `direction='credit'` row with no idempotency key — a credit for money never received, duplic… | `apps/api/src/routes/payments.ts:234-239`, `:288-293` |
| S-215 | G3 | T04 | F-04-17 (S2) | — | — | No recovery for an interrupted payment: nothing checks for pending intentions on app launch in either app. | `apps/rider/lib/screens/wallet/topup_screen.dart:44-1… |
| S-216 | G3 | T05 | F-05-13 (S2) | — | — | Surge is dead code — it reads a column that does not exist on `pricing_rules` | `apps/api/src/routes/trips.ts:390-392`; `migrations/0… |
| S-217 | G3 | T05 | F-05-14 (S2) | — | — | `/estimate` omits the surge that create applies | `apps/api/src/routes/trips.ts:315-344` vs `:387-397` |
| S-218 | G3 | T05 | F-05-15 (S2) | — | — | `/estimate` is unauthenticated and returns nearby captain coordinates | `apps/api/src/routes/trips.ts:315-346`, `:336-342` |
| S-219 | G3 | T05 | F-05-16 (S2) | — | — | Per-user promo caps are not expressible in the current schema | `migrations/0002_enhancements.sql:54-70` |
| S-220 | G3 | T05 | F-05-17 (S2) | — | — | Bids from unapproved captains reach the rider's chooser | `apps/api/src/routes/trips.ts:1144-1167` and `:1236-1… |
| S-221 | G3 | T05 | F-05-18 (S2) | — | — | Any online captain may bid on any open trip regardless of distance or dispatch | `apps/api/src/routes/trips.ts:1157-1167` |
| S-222 | G3 | T05 | F-05-19 (S2) | — | — | Client-supplied `city` selects the pricing table, unvalidated against coordinates | `apps/api/src/routes/trips.ts:322,378`, `:24-32`; `mi… |
| S-223 | G3 | T05 | F-05-20 (S2) | — | — | Money is float throughout the fare engine; the bidding columns were never migrated to piastres | `packages/shared/src/index.ts:17-38`; `migrations/000… |
| S-224 | G3 | T05 | F-05-21 (S2) | — | — | The captain decides on a gross fare; commission is never disclosed at decision time | `apps/captain/lib/screens/home/offer_card.dart:239-24… |
| S-225 | G3 | T05 | F-05-22 (S2) | — | — | `minFare` is enforced before the discount, so a promo can push a fare under the floor | `packages/shared/src/index.ts:104-105`; `packages/sha… |
| S-226 | G3 | T05 | F-05-23 (S2) | — | — | Intercity bookings appear to bypass commission accounting entirely | `apps/api/src/routes/intercity.ts:99-102`; `migration… |
| S-227 | G3 | T05 | F-05-24 (S2) | — | — | The rider sees no bid expiry while the captain sees a 15-second countdown | `apps/captain/lib/screens/home/offer_card.dart:69,964… |
| S-228 | G3 | T05 | F-05-25 (S2) | — | — | The default OSRM endpoint is the free public demo server | `apps/api/src/lib/routing.ts:15`; `apps/api/src/route… |
| S-229 | G3 | T06 | F-06-07 (S2) | — | — | Losing captains are never told the trip was taken; accept fans out nothing | `apps/api/src/routes/trips.ts:861-889` |
| S-230 | G3 | T06 | F-06-08 (S2) | — | — | Ranking is straight-line haversine only — no ETA, rating, acceptance rate, idle time, or vehicle-type match | `apps/api/src/durable-objects/GeoCell.ts:57,61`; `app… |
| S-231 | G3 | T06 | F-06-09 (S2) | — | — | Decline is client-local only; the server never learns a captain rejected | `apps/captain/lib/services/captain_state.dart:1041-10… |
| S-232 | G3 | T06 | F-06-10 (S2) | — | — | No fairness mechanism anywhere: no cooldown after decline, no round-robin, no idle-time weighting, no cherry-picking … | absence across `GeoCell.ts`, `nearby.ts`, `OfferSched… |
| S-233 | G3 | T06 | F-06-11 (S2) | — | — | `GET /captain/offers` applies `LIMIT 20` **before** the radius filter is applied in JS | `apps/api/src/routes/captain.ts:462-467`, `483-491` |
| S-234 | G3 | T06 | F-06-12 (S2) | — | — | Accept never verifies candidacy, distance, or city — any approved, online captain can take any open trip | `apps/api/src/routes/trips.ts:829-870` |
| S-235 | G3 | T06 | F-06-13 (S2) | — | — | The FCM fanout to 10 captains is `await`ed inside the request path | `apps/api/src/routes/trips.ts:574-585` |
| S-236 | G3 | T06 | F-06-14 (S2) | — | — | `CaptainInbox` has no persistence or replay — an offer pushed while the socket is down is gone | `apps/api/src/durable-objects/CaptainInbox.ts:35-39`,… |
| S-237 | G3 | T07 | F-07-08 (S2) | — | — | `broadcastTrip()` has no error handling and makes two sequential DO round-trips inside the request | `apps/api/src/routes/trips.ts:160-174`, called at `:5… |
| S-238 | G3 | T07 | F-07-09 (S2) | — | — | No message envelope: no version, no sequence number, no message id | catalogue in §3.4; `TripRoom.ts:117-131`, `:168-175`;… |
| S-239 | G3 | T07 | F-07-10 (S2) | — | — | The rider's backstop poll re-downloads the entire trip, every `trip_events` row, and the full route geometry every 10… | `apps/api/src/routes/trips.ts:662-679`; `apps/rider/l… |
| S-240 | G3 | T07 | F-07-11 (S2) | — | — | The rider socket never resyncs after reconnect | `apps/rider/lib/services/trip_ws.dart:49-84`; `apps/r… |
| S-241 | G3 | T07 | F-07-12 (S2) | — | — | Close code 4401 and `auth.failed` are unhandled on all three clients; both reconnect forever | `apps/rider/lib/services/trip_ws.dart:71`; `apps/capt… |
| S-242 | G3 | T07 | F-07-13 (S2) | — | — | Application-level 25 s JSON pings wake the Durable Object and are billable; `setWebSocketAutoResponse` exists for exa… | `apps/api/src/durable-objects/TripRoom.ts:162-165`; `… |
| S-243 | G3 | T07 | F-07-14 (S2) | — | — | No backpressure anywhere: `broadcast()` never inspects `bufferedAmount` | `apps/api/src/durable-objects/TripRoom.ts:268-288`; `… |
| S-244 | G3 | T07 | F-07-15 (S2) | — | — | The location hot path costs 5 D1 statements + 2 awaited DO round-trips per ping | `apps/api/src/routes/captain.ts:198-270` |
| S-245 | G3 | T07 | F-07-16 (S2) | — | — | The rider has no connection indicator of any kind; `onStatus` is emitted but never wired up | `apps/rider/lib/services/trip_ws.dart:51`, `:62`, `:8… |
| S-246 | G3 | T08 | F-08-03 (S1) | scale-priced | — | Four highest-volume tables have no retention mechanism, against D1's **hard 10 GB ceiling that cannot be raised**; at… | `lib/cleanup.ts` (whole file); `routes/captain.ts:245… |
| S-247 | G3 | T08 | F-08-05 (S2) | — | — | `trips.status` — the core state machine — and 13 other enum columns have no CHECK constraint; arbitrary strings are a… | `/tmp` reproduction; `migrations/0001_init.sql` (trip… |
| S-248 | G3 | T08 | F-08-06 (S2) | — | — | `payment_intentions`, the server-side source of truth for PSP crediting, declares **zero** foreign keys | `migrations/0011_payment_intentions.sql:8-19` |
| S-249 | G3 | T08 | F-08-07 (S2) | — | — | The 0005 integer-currency migration was never finished: 3 piastres columns are dead, 1 is write-only, and 3 of 8 wall… | `migrations/0005:15-19`; `intercity.ts:151,290`; `wal… |
| S-250 | G3 | T08 | F-08-08 (S2) | — | — | 12 of 19 migrations are non-idempotent and there is no rollback path of any kind | every bare `ALTER TABLE ADD COLUMN`, e.g. `0003:45`, … |
| S-251 | G3 | T08 | F-08-09 (S2) | — | — | `cleanup.ts` skips `turnstile_verifications` on a false premise — the table has existed since 0003 | `lib/cleanup.ts:11-13` vs `migrations/0003_global_tra… |
| S-252 | G3 | T08 | F-08-10 (S2) | — | — | `ratings` has no index on `to_user_id`; `driver_documents` has none on `status`. Both are full scans on live paths | `routes/trips.ts:1122`; `routes/admin.ts:633,646` |
| S-253 | G3 | T08 | F-08-11 (S2) | — | — | Cron fan-out issues unbounded per-iteration queries against D1's per-invocation query cap | `index.ts:316` (no LIMIT), `index.ts:337-364` (3 quer… |
| S-254 | G3 | T08 | F-08-12 (S2) | — | — | `wallet_transactions.user_id` and `user_credits.user_id` are `ON DELETE CASCADE` to `users` — deleting a user destroy… | FK dump from applied schema |
| S-255 | G3 | T09 | F-09-04 (S2) | — | — | The WS token is captured once at construction and never refreshed. After a mid-trip token rotation the socket retries… | `trip_screen.dart:137`, `trip_ws.dart:57`, `:70-71`, … |
| S-256 | G3 | T09 | F-09-05 (S2) | — | — | Permanently-denied location dead-ends. Three call sites bare-`return`; `openAppSettings` appears nowhere in the app | `home_screen.dart:141`, `saved_places_screen.dart:399… |
| S-257 | G3 | T09 | F-09-06 (S2) | — | — | `CaptainBidsSheet` bypasses the auth interceptor with raw `http` calls and sets no timeout | `captain_bids_sheet.dart:96-99`, `:129-133` vs `app_s… |
| S-258 | G3 | T09 | F-09-07 (S2) | — | — | Payment method is hardcoded `'cash'` on every trip. `PaymentMethodsScreen` cannot affect what is sent | `app_state.dart:504`, `payment_methods_screen.dart:84… |
| S-259 | G3 | T09 | F-09-08 (S2) | — | — | The notifications screen is static mock data — zero network calls in the file | `notifications_screen.dart:20-26` (no `initState` fet… |
| S-260 | G3 | T09 | F-09-09 (S2) | — | — | Notification taps do nothing. `FcmService.init` is called four times and `onTap` is never supplied | `app_state.dart:154`, `:396`, `:410`, `:440` vs `fcm_… |
| S-261 | G3 | T09 | F-09-10 (S2) | — | — | Six screens convert a network error into an *empty* state, so an outage reads as "you have nothing" | `history_screen.dart:35-37`, `promo_screen.dart:31`, … |
| S-262 | G3 | T09 | F-09-11 (S2) | — | — | The rider app has no offline awareness at all. `OfflineGate` and `OfflineGuardBanner` are used by zero rider screens | `packages/flutter_shared/lib/widgets/offline_gate.dar… |
| S-263 | G3 | T09 | F-09-12 (S2) | — | — | `GET /promos` is admin-only; the rider's promo list is always empty and the 403 is swallowed | `promo.ts:53` (`requireRole("admin")`) vs `promo_scre… |
| S-264 | G3 | T09 | F-09-13 (S2) | — | — | `InviteScreen` reads `referral_code` and `invited_count`, which `GET /user/profile` does not return; it shows the lit… | `invite_screen.dart:34`, `:93` vs `user.ts:72-91` |
| S-265 | G3 | T09 | F-09-14 (S2) | — | — | The ARB/gen-l10n pipeline is unreachable: `AppLocalizations.delegate` is not registered, and `AppLocalizations` is re… | `main.dart:59-63`, 0 hits for `AppLocalizations` unde… |
| S-266 | G3 | T09 | F-09-15 (S2) | — | — | The language choice is not persisted; theme is. Every cold start reverts to Arabic | `app_state.dart:532-544` (no `prefs.setString`) vs `:… |
| S-267 | G3 | T09 | F-09-16 (S2) | — | — | `ScheduleScreen` is orphaned — it is never imported or pushed from anywhere, though the API field and the dispatch cr… | `schedule_screen.dart:5` is the only reference in `ap… |
| S-268 | G3 | T09 | F-09-17 (S2) | — | — | No receipt. `TripDetailScreen` shows a total and a discount; base/distance/time/surge are never displayed and the com… | `trip_detail_screen.dart:128-146`, `trips.ts:675` |
| S-269 | G3 | T09 | F-09-18 (S2) | — | — | Rating drops the rider's words. The comment field and the tag chips are rendered but `rateTrip` posts only `{score}` | `rating_sheet.dart:26`, `:109-115`, `:34` vs `app_sta… |
| S-270 | G3 | T09 | F-09-19 (S2) | — | — | `AppState` is a 16-notify god-object with 5 whole-object listeners and no selectors; a wallet fetch rebuilds the 1509… | 16 `notifyListeners()` in `app_state.dart`; `main.dar… |
| S-271 | G3 | T09 | F-09-20 (S2) | — | — | Three `TextEditingController`s are leaked on every profile-edit open; `profile_screen.dart` has no `dispose` at all | `profile_screen.dart:191-193`; 0 hits for `dispose` i… |
| S-272 | G3 | T09 | F-09-21 (S2) | — | — | 5.47 MB of rider assets, including a 876 KB `splash.mp4` that nothing plays and a 627 KB iOS app icon shipped as a Fl… | git tree at `f3e0419`: `assets/videos/splash.mp4` 875… |
| S-273 | G3 | T09 | F-09-22 (S2) | — | — | Cold start is a 2400 ms fixed hold plus up to three sequential network calls, each with a 15 s timeout | `splash_screen.dart:97`, `main.dart:102`, `app_state.… |
| S-274 | G3 | T09 | F-09-23 (S2) | — | — | `google_fonts` with no bundled font files — the Arabic typeface is fetched from the network at runtime | `pubspec.yaml` dependency; `GoogleFonts.ibmPlexSansAr… |
| S-275 | G3 | T09 | F-09-24 (S2) | — | — | No ABI splits in the release build | `apps/rider/android/app/build.gradle` has no `splits`… |
| S-276 | G3 | T10 | F-10-07 (S2) | — | — | Offer countdown is anchored to widget mount, not to the server's issue time | `apps/captain/lib/screens/home/offer_card.dart:102`; … |
| S-277 | G3 | T10 | F-10-08 (S2) | — | — | Decline is client-only; no server decline endpoint exists | `apps/captain/lib/services/captain_state.dart:1041-10… |
| S-278 | G3 | T10 | F-10-09 (S2) | — | — | Offer card tap targets are 46/42/42 dp, below the app's own 48/56 dp tokens | `apps/captain/lib/screens/home/offer_card.dart:609,65… |
| S-279 | G3 | T10 | F-10-10 (S2) | — | — | Net-after-commission is never shown before the captain commits | `apps/captain/lib/screens/home/offer_card.dart` (no `… |
| S-280 | G3 | T10 | F-10-11 (S2) | — | — | Trip history shows fare only — no commission, no net, no detail view | `apps/captain/lib/screens/home/trips_tab.dart:241-243` |
| S-281 | G3 | T10 | F-10-12 (S2) | — | — | No proximity check before `arrived` | `apps/api/src/routes/trips.ts:891-944` |
| S-282 | G3 | T10 | F-10-13 (S2) | — | — | No waiting timer and no waiting charge | repo-wide grep: no `wait_fee`/`waiting_fee`/`wait_cha… |
| S-283 | G3 | T10 | F-10-14 (S2) | — | — | Rider rating is never shown before accepting | `apps/captain/lib/models/ride_request_model.dart:1-57… |
| S-284 | G3 | T10 | F-10-15 (S2) | — | — | Hot-path type sizes of 10–12.5 sp on driving screens | `apps/captain/lib/screens/home/active_trip_panel.dart… |
| S-285 | G3 | T10 | F-10-16 (S2) | — | — | Brand and muted colours fail WCAG AA on the app's own off-white surfaces | `packages/flutter_shared/lib/theme/app_theme.dart:36,… |
| S-286 | G3 | T10 | F-10-17 (S2) | — | — | No client-side upload size check and no byte progress | `apps/captain/lib/screens/documents/documents_onboard… |
| S-287 | G3 | T10 | F-10-18 (S2) | — | — | No push notification when documents are approved or rejected | `apps/api/src/routes/admin.ts:820-858`; `apps/captain… |
| S-288 | G3 | T10 | F-10-19 (S2) | — | — | No offline queue for `arrived` / `start` / `complete` | `apps/captain/lib/services/captain_state.dart:1047-10… |
| S-289 | G3 | T10 | F-10-20 (S2) | — | — | Multi-stop is unsupported although waypoints exist in the schema | `apps/api/src/routes/trips.ts:476`; no waypoint UI in… |
| S-290 | G3 | T10 | F-10-21 (S2) | — | — | SOS is only reachable from the map tab | `apps/captain/lib/screens/home/main_shell.dart:739-75… |
| S-291 | G3 | T10 | F-10-23 (S2) | — | — | Stale `is_online` is cleaned only when an admin opens the dashboard | `apps/api/src/routes/admin.ts:237`; `apps/api/src/ind… |
| S-292 | G3 | T10 | F-10-24 (S2) | — | — | Approval and other failures are surfaced as GPS errors | `apps/captain/lib/services/captain_state.dart:600-607… |
| S-293 | G3 | T10 | F-10-25 (S2) | — | — | Earnings use a rolling UTC 7-day window and there is no daily total | `apps/api/src/routes/captain.ts:275`; `apps/api/src/r… |
| S-294 | G3 | T10 | F-10-26 (S2) | — | — | No debt gate and no debt visibility for cash commission owed | `apps/api/src/routes/captain.ts:131-155`; `migrations… |
| S-295 | G3 | T11 | F-11-07 (S2) | — | — | Rider accounts cannot be banned, deleted, merged, or have a phone corrected — no endpoint exists, only captains have … | `apps/api/src/routes/admin.ts:326-331` (users is `SEL… |
| S-296 | G3 | T11 | F-11-08 (S2) | — | — | Audit entries record the new value only — no before-value is captured, on any change | `apps/api/src/routes/admin.ts:402-409` (`payload: bod… |
| S-297 | G3 | T11 | F-11-09 (S2) | — | — | Audit writes fail silently — the helper swallows every error and the request succeeds anyway | `apps/api/src/lib/audit.ts:33-36` |
| S-298 | G3 | T11 | F-11-10 (S2) | — | — | Pricing has no guardrails against catastrophic-but-in-range values: `base_fare = 0` and `commission_rate = 1.0` (100%… | `apps/api/src/lib/schemas.ts:224` (`min(0)`), `:229` … |
| S-299 | G3 | T11 | F-11-11 (S2) | — | — | Pricing writes are last-write-wins with no optimistic locking | `apps/api/src/routes/admin.ts:355` (read), `:376` (`U… |
| S-300 | G3 | T11 | F-11-12 (S2) | — | — | Switching cities on the pricing page silently discards unsaved edits with no warning | `apps/admin/src/pages/PricingPage.tsx:356`; no `befor… |
| S-301 | G3 | T11 | F-11-13 (S2) | — | — | The live map is capped at 200 captains and 200 trips with no indication, so beyond 200 online it shows a silent subset | `apps/api/src/routes/admin.ts:934`, `:53-61`; `apps/a… |
| S-302 | G3 | T11 | F-11-14 (S2) | — | — | Suspending a captain — an income-ending action — captures no reason, while rejecting a single document requires one | `apps/admin/src/pages/CaptainsPage.tsx:288` (POST wit… |
| S-303 | G3 | T11 | F-11-15 (S2) | — | — | Column sorting sorts only the fetched page, presenting itself as sorting the table | `apps/admin/src/components/ui/DataTable.tsx:87-98`, `… |
| S-304 | G3 | T11 | F-11-16 (S2) | — | — | The audit log cannot be filtered by date, and actor is a raw UUID | `apps/admin/src/pages/AuditLogPage.tsx:57-75` (action… |
| S-305 | G3 | T11 | F-11-17 (S2) | — | — | The `payload` column — the only place a change's content is recorded — is fetched but never rendered | `apps/admin/src/pages/AuditLogPage.tsx:139-141` (in C… |
| S-306 | G3 | T11 | F-11-18 (S2) | — | — | Bulk approve runs serially and aborts on the first failure without reporting which documents succeeded | `apps/admin/src/pages/CaptainVerificationPage.tsx:541… |
| S-307 | G3 | T11 | F-11-19 (S2) | — | — | The document-type catalogue has full CRUD and no UI | `apps/api/src/routes/admin.ts:691`, `:698`, `:749`, `… |
| S-308 | G3 | T12 | F-12-05 (S2) | — | R3 | `apps/admin/src/design/tokens.ts` is 248 lines of authoritative-looking dead code. It is imported by nothing. | `apps/admin/src/design/tokens.ts` (whole file); zero … |
| S-309 | G3 | T12 | F-12-06 (S2) | — | — | The admin collapses four distinct semantic roles onto one hex: brand primary, success, info and focus-ring are all `#… | `globals.css:26` (primary), `:45` (success), `:60` (i… |
| S-310 | G3 | T12 | F-12-07 (S2) | — | — | No typeface is bundled. Both apps fetch Cairo over the network at runtime via `google_fonts`. | `apps/rider/pubspec.yaml:50`, `apps/captain/pubspec.y… |
| S-311 | G3 | T12 | F-12-08 (S2) | — | — | The design system has no shared Button, no shared Card, no shared TextField and no shared Toast. | `packages/flutter_shared/lib/widgets/` — 15 widgets, … |
| S-312 | G3 | T12 | F-12-09 (S2) | — | — | The typeface is split three ways across one product. | Cairo system-wide (`app_theme.dart:265`); IBM Plex Sa… |
| S-313 | G3 | T12 | F-12-11 (S2) | — | — | Captain document tiles use `Colors.black54`/`Colors.black87` chrome that disappears against the dark-mode tile backgr… | `documents_onboarding_screen.dart:531,576`; duplicate… |
| S-314 | G3 | T12 | F-12-12 (S2) | — | — | A complete 15-role type scale exists and is bypassed. 199 raw `fontSize:` call sites across 23 distinct values in the… | Scale at `app_theme.dart:1029-1052`; call sites throu… |
| S-315 | G3 | T12 | F-12-13 (S2) | — | — | The rider login screen forces `Colors.white` as its action foreground and `AppTokens.primary` as its action fill, ign… | `apps/rider/lib/screens/login_screen.dart:68` (`_onAc… |
| S-316 | G3 | T12 | F-12-14 (S2) | — | — | Presentational code is copy-pasted between the two apps at scale. | `login_screen.dart` 57.1% identical (rider 1044 / cap… |
| S-317 | G3 | T12 | F-12-15 (S2) | — | — | Every named radius tier disagrees between admin and mobile. | `app_theme.dart:161-166` (6/10/14/18/26) vs `tokens.t… |
| S-318 | G3 | T12 | F-12-16 (S2) | — | — | `Badge.tsx` hardcodes all four status palettes as arbitrary Tailwind hex values, bypassing tokens entirely. | `apps/admin/src/components/ui/Badge.tsx:13-16` — 8 li… |
| S-319 | G3 | T12 | F-12-17 (S2) | — | — | Roughly seven directional icons are not mirrored for RTL. | `trip_screen.dart:282` (`Icons.arrow_back`), `schedul… |
| S-320 | G3 | T12 | F-12-18 (S2) | — | — | Non-adaptive brand gradients on rider help and invite cards. | `apps/rider/lib/screens/profile/help_screen.dart:36-5… |
| S-321 | G3 | T13 | F-13-02 (S2) | — | R3 | No duration or curve tokens exist; 30 distinct ad-hoc duration literals and 5 inconsistently applied curves | `app_theme.dart` (1055 lines, zero matches); scales a… |
| S-322 | G3 | T13 | F-13-03 (S2) | — | — | Captain marker teleports between GPS fixes on the rider's trip screen; no interpolation | `trip_screen.dart:145`–`150`; poll `:172` |
| S-323 | G3 | T13 | F-13-04 (S2) | — | — | The rider's captain marker is built without `heading`, so the car always points north | `trip_screen.dart:383`–`391`; `vehicle_map_marker.dar… |
| S-324 | G3 | T13 | F-13-05 (S2) | — | — | 855 KB `splash.mp4` is bundled into both app binaries (and a third copy sits at repo root) with zero code references … | `apps/rider/pubspec.yaml:63`; `apps/captain/pubspec.y… |
| S-325 | G3 | T13 | F-13-06 (S2) | — | — | Zero `HapticFeedback` calls in the entire rider app | grep `apps/rider/lib` → 0; captain+shared → 11 |
| S-326 | G3 | T13 | F-13-07 (S2) | — | — | A new offer arriving in the captain app fires no haptic and no sound; the first feedback is the driver's own tap | `offer_card_entrance.dart` (none); first haptic at `o… |
| S-327 | G3 | T13 | F-13-09 (S2) | — | — | The offer card rebuilds a `BackdropFilter` blur every frame for 15 s; `AnimatedBuilder.child` unused | `offer_card.dart:286`–`302`, controller `:71` |
| S-328 | G3 | T14 | F-14-04 (S2) | — | — | The parity guard checks only `app_strings.dart`, where drift is a compile error anyway; the ARB files have no guard | `scripts/check_l10n_parity.py:42`; script output `exi… |
| S-329 | G3 | T14 | F-14-05 (S2) | — | — | Locale is never persisted — theme and search radius are | `apps/rider/lib/services/app_state.dart:532-535` vs `… |
| S-330 | G3 | T14 | F-14-06 (S2) | — | — | No server-side locale storage anywhere; all 23 notification types are hardcoded Arabic and the WhatsApp OTP language … | `migrations/0001_init.sql:3-13`; `apps/api/src/lib/no… |
| S-331 | G3 | T14 | F-14-07 (S2) | — | — | `goOnline` is mistranslated as an internet-connectivity instruction in the shared catalogue | `app_strings.dart:3554` (`'اتصل بالإنترنت لعرض الرحلا… |
| S-332 | G3 | T14 | F-14-08 (S2) | — | — | Six competing Arabic terms for the pickup point, one of which means the opposite | `apps/rider/lib/l10n/app_ar.arb:19` (`'موقف النزول'` … |
| S-333 | G3 | T14 | F-14-09 (S2) | — | — | Arabic pluralisation is broken in 9 count-interpolating methods; the migration to `AppStrings` *regressed* two that w… | `app_strings.dart:1832`, `:1978`, `:2119-2120`, `:231… |
| S-334 | G3 | T14 | F-14-10 (S2) | — | R3 | Mock data shipped as production copy in notifications | `app_strings.dart:2071`, `:2083`, `:2089`, `:2092`, `… |
| S-335 | G3 | T14 | F-14-12 (S2) | — | — | The rider bids sheet hardcodes `Directionality.rtl` for its whole subtree | `apps/rider/lib/screens/ride/captain_bids_sheet.dart:… |
| S-336 | G3 | T14 | F-14-13 (S2) | — | — | 18 directional icons render unmirrored in Arabic | `rider/trip/trip_chat_screen.dart:140`; `rider/trip/t… |
| S-337 | G3 | T14 | F-14-14 (S2) | — | — | Captain onboarding Next/Back chevrons are assigned inverted icons | `captain/documents/documents_onboarding_screen.dart:6… |
| S-338 | G3 | T14 | F-14-15 (S2) | — | — | Cairo is fetched at runtime from the Google Fonts CDN; no font is bundled | `packages/flutter_shared/lib/theme/app_theme.dart:265… |
| S-339 | G3 | T14 | F-14-16 (S2) | — | — | All gendered copy is masculine and gender is not stored anywhere | `app_strings.dart:1866`, `:1884`, `:2499`, `:2588`, `… |
| S-340 | G3 | T14 | F-14-17 (S2) | — | R4 | The rider SOS screen bypasses the catalogue entirely with hardcoded Arabic, while equivalent keys exist unused | `apps/rider/lib/screens/safety/sos_screen.dart:32`, `… |
| S-341 | G3 | T15 | F-15-12 (S2) | — | — | Captain's three decision buttons are all sub-48dp: accept 46dp, counter 42dp, decline 42dp | `offer_card.dart:609,656,705,790,830` |
| S-342 | G3 | T15 | F-15-13 (S2) | — | — | Meaning-critical addresses are `maxLines: 1` inside fixed-height boxes; they truncate at 1× and worsen with scale | `home_screen.dart:1343`; `fare_estimate_sheet.dart:49… |
| S-343 | G3 | T15 | F-15-14 (S2) | — | — | `IndexedStack` keeps four inactive screens in the semantics tree with no `ExcludeSemantics` | `home_screen.dart:503–506` |
| S-344 | G3 | T15 | F-15-15 (S2) | — | — | `QuickSearchModal` puts `role="dialog"`/`aria-modal`/`aria-label` on the backdrop, not the panel; no focus trap; no f… | `QuickSearchModal.tsx:63–68,79–86` |
| S-345 | G3 | T15 | F-15-16 (S2) | — | — | Admin search results are non-interactive `<div>`s — no `tabIndex`, no `role`, no key handler | `QuickSearchModal.tsx:108,130,145` |
| S-346 | G3 | T15 | F-15-17 (S2) | — | — | `LoginPage` uses raw inputs with unassociated labels and a silent error region | `LoginPage.tsx:47–52,57,60,73,76` |
| S-347 | G3 | T15 | F-15-18 (S2) | — | — | Rider home's location dot pulses continuously with no reduced-motion guard | `home_screen.dart:97–101,844–882` |
| S-348 | G3 | T15 | F-15-19 (S2) | — | — | No skip link anywhere; every page load requires tabbing past 10+ nav items | grep across `apps/admin/src` returns nothing |
| S-349 | G3 | T15 | F-15-20 (S2) | — | — | Rider-side 44dp glass buttons and 46dp default map buttons | `home_screen.dart:1010–1032,1050–1083`; `map_controls… |
| S-350 | G3 | T15 | F-15-21 (S2) | — | — | `star` `#F5B301` = 1.85:1 and `lightFaint` `#9CA3AF` = 2.54:1 on white | `app_theme.dart:50,107` |
| S-351 | G3 | T15 | F-15-22 (S2) | — | — | Captain's "call rider" control is an unlabelled `InkWell` + icon | `active_trip_panel.dart:384–392` |
| S-352 | G3 | T16 | F-16-04 (S2) | — | — | Multi-stop is accepted and stored but never routed, priced, or displayed | `schemas.ts:64-73`, `trips.ts:475`, `routing.ts:21-30` |
| S-353 | G3 | T16 | F-16-05 (S2) | — | — | Nominatim is the sole geo provider, with no rate limit, no fallback, and no local POI table | `geocode.ts:39-40`, `:48`, `:100-102`, `:108`; no `pl… |
| S-354 | G3 | T16 | F-16-06 (S2) | — | — | Fare components are never persisted and `pricing_rules` has no history, so itemised receipts cannot be produced retro… | `trips.ts:441-481`, `lib/pricing.ts:10-21`, no pricin… |
| S-355 | G3 | T16 | F-16-07 (S2) | — | — | No receipt exists in any form for a rider; B2B invoices are database rows with no document | searched `receipt`/`invoice`/`pdf`; `companies.ts:166… |
| S-356 | G3 | T16 | F-16-08 (S2) | — | — | Two-sided accountability is half-wired: captain→rider ratings are accepted and discarded, and no rating threshold doe… | `trips.ts:1103-1107`, `:1121`; no rider aggregate col… |
| S-357 | G3 | T16 | F-16-09 (S2) | — | — | Waiting time and no-show are unhandled although the timestamps to compute them are already stored | `arrived_at`/`started_at` in `0001_init.sql`; `trips.… |
| S-358 | G3 | T16 | F-16-10 (S2) | — | — | The rating comment is collected from the rider and never sent; the five feedback chips are decoration | `rating_sheet.dart:119-130`, `:108-116` vs `schemas.t… |
| S-359 | G3 | T17 | F-17-16 (S2) | — | — | Chat body validation is length-only, so the "no phone numbers exchanged" design intent is unenforced. | `safety.ts:138` (intent), `:144-153` (validator) |
| S-360 | G3 | T17 | F-17-17 (S2) | — | — | `sender_role` is a two-way ternary; an admin's message is stored and rendered as `captain`, though the schema reserve… | `safety.ts:163,272`; `migrations/0003_global_transpor… |
| S-361 | G3 | T17 | F-17-18 (S2) | — | — | Both parties' real mobile numbers are exposed with no masking; `rider_phone` is disclosed to captains before acceptan… | `trips.ts:136,160-174`; `captain.ts:372,412`; `active… |
| S-362 | G3 | T17 | F-17-19 (S2) | — | — | No trip-anomaly detection exists, and `trip_path_points.speed` is structurally unfillable — the client schema has no … | `migrations/0002_enhancements.sql:20`; `captain.ts:24… |
| S-363 | G3 | T17 | F-17-20 (S2) | — | — | Chat is retained forever with no purge and no admin viewer. | no `trip_chat_messages` DELETE anywhere; `cleanup.ts`… |
| S-364 | G3 | T17 | F-17-21 (S2) | — | — | No women's-safety surface at all: no gender field, no female-captain preference, no trusted contacts, no discreet SOS… | `migrations/0001_init.sql:3-13`; zero `gender\ |
| S-365 | G3 | T17 | F-17-22 (S2) | — | — | `/safety/sos` has no per-user rate limit; only the global 120 req/min-per-IP limiter applies, and no trip is required. | `safety.ts:1-9` (never imports `rateLimit`); `index.t… |
| S-366 | G3 | T17 | F-17-23 (S2) | — | — | `users.phone` has no UNIQUE constraint in any migration, so one person can hold unlimited accounts. | `migrations/0001_init.sql:8`; `migrations/0011_paymen… |
| S-367 | G3 | T17 | F-17-24 (S2) | — | — | The share-link revoke endpoint exists but no UI in either app calls it, and no rider can list their active links. | `safety.ts:126-136`; no call site in either app |
| S-368 | G3 | T18 | F-18-11 (S2) | — | — | Anti-fraud ops tooling is missing: no rider suspension, no payout hold, no manual refund/credit, no unified entity vi… | `apps/api/src/routes/admin.ts` (937 lines; full inven… |
| S-369 | G3 | T18 | F-18-12 (S2) | — | — | Rate limiter fails open on KV error, does not await its own increment, and defaults to IP identity | `apps/api/src/middleware/rateLimit.ts:28-34`, `:49-53… |
| S-370 | G3 | T18 | F-18-13 (S2) | — | — | Turnstile silently disables itself when the secret is unset, and records the skip as `verified = 1` | `apps/api/src/lib/turnstile.ts:16-27` |
| S-371 | G3 | T18 | F-18-14 (S2) | — | — | Card testing: the payment-intention endpoint has no per-user limit and forwards the PSP's error text verbatim | `apps/api/src/routes/payments.ts:23`, `:91` |
| S-372 | G3 | T18 | F-18-15 (S2) | — | — | Cash commission is debited with no floor and no collection mechanism | `apps/api/src/routes/trips.ts:1029-1033` |
| S-373 | G3 | T18 | F-18-16 (S2) | — | — | Client-supplied `offeredPrice`/`counterPrice` accept 1 EGP, below the configured minimum fare | `apps/api/src/lib/schemas.ts:59`, `:77`; `apps/api/sr… |
| S-374 | G3 | T18 | F-18-17 (S2) | — | — | The WebSocket location channel bypasses the HTTP limiter and the zod schema entirely | `apps/api/src/durable-objects/TripRoom.ts:167-177` |
| S-375 | G3 | T18 | F-18-18 (S2) | — | — | Fraud-relevant events are not in the audit log: promo use, login failure, OTP request, location, device registration,… | `apps/api/src/lib/audit.ts:3-37`; `apps/api/src/route… |
| S-376 | G3 | T18 | F-18-19 (S2) | — | — | The scheduled cleanup deletes OTP rows ~24 h after expiry — the record of how a fraudulent account authenticated | `apps/api/src/lib/cleanup.ts:35-41` |
| S-377 | G3 | T18 | F-18-20 (S2) | — | — | `DEV_OTP` returns the OTP in the HTTP response | `apps/api/src/routes/auth.ts:122-126` |
| S-378 | G3 | T18 | F-18-21 (S2) | — | — | `national_id_number` has no uniqueness constraint on either table that stores it | `migrations/0015_captain_onboarding_fields.sql:15`; `… |
| S-379 | G3 | T19 | F-19-03 (S1) | growth, not launch | — | **The referral loop does not exist.** `referrals` and `user_credits` are dead schema; there is no `referral_code` col… | `0002:107-122`; `user.ts:80-88` (only read); `invite_… |
| S-380 | G3 | T19 | F-19-06 (S2) | — | — | Promo codes have **no per-user redemption cap**. Validity is checked without reference to the rider. | `trips.ts:415-419` |
| S-381 | G3 | T19 | F-19-07 (S2) | — | — | **TOCTOU on `uses_count`** — the cap check and the increment are separate, untransacted statements. | read `trips.ts:418`; write `trips.ts:499-503` |
| S-382 | G3 | T19 | F-19-08 (S2) | — | — | A fixed-value promo can produce a **zero-fare trip with zero commission**; the discount is clamped to the fare rather… | `trips.ts:424`, `:428`, `:429` |
| S-383 | G3 | T19 | F-19-09 (S2) | — | — | **Stale FCM tokens are never pruned.** `sendFcm` never inspects the error for `UNREGISTERED`/`NOT_FOUND` and never de… | `notifications.ts:349-357`; `devices.ts` has delete-b… |
| S-384 | G3 | T19 | F-19-10 (S2) | — | — | `app_role` is stored but **ignored on fan-out**; `platform` is hardcoded `'android'` by both clients. | `notifications.ts:388-392`; `0003:17`; `app_state.dar… |
| S-385 | G3 | T19 | F-19-11 (S2) | — | — | **Delivery is unobservable past FCM's front door.** `status` allows only `queued/sent/failed/dropped`; there is no `d… | `0003:214-229`; `notifications.ts:35-65` |
| S-386 | G3 | T19 | F-19-12 (S2) | — | — | **WhatsApp is OTP-only** despite being the dominant channel in Egypt; the topic is hardcoded `auth.otp` and there is … | `notifications.ts:71-150`, topic literal at `:85,127,… |
| S-387 | G3 | T19 | F-19-13 (S2) | — | — | The two notification **tap payload contracts are incompatible**: background delivers a `Map`, foreground delivers `{'… | `fcm_service.dart:43` vs `:96,101-104` |
| S-388 | G3 | T19 | F-19-14 (S2) | — | — | **iOS notification setup is incomplete**: no `DarwinInitializationSettings`, no APNS token handling. | `fcm_service.dart:30-32` |
| S-389 | G3 | T19 | F-19-15 (S2) | — | — | The rider **re-initialises `FcmService` on every login path with no callbacks**, stacking duplicate `onMessage`/`onMe… | `app_state.dart:396,410,440` vs `captain_state.dart:2… |
| S-390 | G3 | T19 | F-19-16 (S2) | — | — | The rider's **promo screen calls an admin-only endpoint**; the 403 is swallowed and the offers list is permanently em… | `promo_screen.dart:29,31`; `promo.ts:53` |
| S-391 | G3 | T19 | F-19-17 (S2) | — | — | **No captain growth programme of any kind** — no referral, onboarding incentive, quest, streak or earnings guarantee … | `captain.ts` (full read); all 19 migrations |
| S-392 | G3 | T19 | F-19-18 (S2) | — | — | **No install attribution and no activation instrumentation.** No SDK in either `pubspec.yaml`; no funnel events emitt… | both `pubspec.yaml`; grep for analytics/attribution |
| S-393 | G3 | T20 | F-20-03 (S2) | — | — | A cancelled and refunded booking can be flipped to `boarded` | `intercity.ts:386–389` vs `:260–277` |
| S-394 | G3 | T20 | F-20-04 (S2) | — | — | QR verification is optional in the API and impossible in the apps | `intercity.ts:383–385`; no QR package in any `pubspec… |
| S-395 | G3 | T20 | F-20-05 (S2) | — | — | Seat claim and booking insert are not atomic and have no compensation | `intercity.ts:116–145` |
| S-396 | G3 | T20 | F-20-06 (S2) | — | — | No captain intercity surface exists; three endpoints have no consumer | `intercity.ts:326,340,367`; zero hits in `apps/captai… |
| S-397 | G3 | T20 | F-20-07 (S2) | — | — | Schedules are never closed out — no code sets `departed`/`completed`/`cancelled` | `0003:88` vs whole of `intercity.ts`; `:332` |
| S-398 | G3 | T20 | F-20-18 (S2) | — | — | The one spend check that exists is bypassable by changing cost centre and ignores the pending fare | `companies.ts:39–51` |
| S-399 | G3 | T20 | F-20-19 (S2) | — | — | Any employee can read all company invoices and the last 100 company trips with addresses | `companies.ts:217–239`; `0003:126–136` has no role co… |
| S-400 | G3 | T20 | F-20-20 (S2) | — | — | Invoices have no line items and no trip→invoice link; the only marker is then zeroed | `0003:144–154`, `companies.ts:193`, `index.ts:361` |
| S-401 | G3 | T20 | F-20-21 (S2) | — | — | No VAT, no ETA e-invoice fields, no signature; `tax_id` captured but unused | `0003:113–124,144–154` |
| S-402 | G3 | T20 | F-20-22 (S2) | — | — | Invoices are not collectible; `paymob_order_id` never written or read, no status transitions | `0003:152`; grep across `apps/api/` |
| S-403 | G3 | T20 | F-20-23 (S2) | — | — | Employee binding takes a raw user id with no existence check, invitation or consent | `companies.ts:122–142` |
| S-404 | G3 | T20 | F-20-27 (S2) | — | — | No admin console for either vertical | `App.tsx:50–59`; zero `intercity`/`compan` in `admin.… |
| S-405 | G3 | T21 | F-21-06 (S2) | — | — | Nominatim returns **zero results** for the landmark-relative phrasing Egyptians actually use | Measured, 2026-08-01 (§4 F-21-06 table); code path `g… |
| S-406 | G3 | T21 | F-21-07 (S2) | — | — | Search sends no `viewbox`/`bounded` bias, so top hits land in the wrong governorate — up to ~700 km away | `geocode.ts:99-102` (only `countrycodes=eg`) |
| S-407 | G3 | T21 | F-21-08 (S2) | — | — | No traffic model anywhere: OSRM default profile is free-flow, the fallback is a flat 22 km/h constant | `routing.ts:72`, `routing.ts:161`, `packages/shared/s… |
| S-408 | G3 | T21 | F-21-09 (S2) | — | — | `city` is unvalidated client-supplied free text that selects the pricing row and filters dispatch | `schemas.ts:45,58,186`; `trips.ts:322-323`, `captain.… |
| S-409 | G3 | T21 | F-21-10 (S2) | — | R5 | Captain GPS push cadence during a trip can exceed the server's own rate limit by ~2× | `captain_state.dart:623-626` (10 m filter, no time fl… |
| S-410 | G3 | T21 | F-21-11 (S2) | — | R5 | No background location: GPS and pushes stop when the captain's screen sleeps | `captain_state.dart:1082-1089` |
| S-411 | G3 | T21 | F-21-12 (S2) | — | — | Route geometry is fetched once at trip load and never refreshed | `trip_screen.dart:46-54` |
| S-412 | G3 | T21 | F-21-13 (S2) | — | R3 | The 2-point fallback geometry renders as a normal polyline — a straight line across the Nile — flagged only by a smal… | `home_screen.dart:586-607`, `location_service.dart:49… |
| S-413 | G3 | T22 | F-22-06 (S2) | — | — | The rate limiter fails **open** on any KV error, silently. | `apps/api/src/middleware/rateLimit.ts:31-34` |
| S-414 | G3 | T22 | F-22-07 (S2) | — | — | `logAudit` swallows every write failure. | `apps/api/src/lib/audit.ts:33-36` |
| S-415 | G3 | T22 | F-22-08 (S2) | — | — | All 22 log statements in the API are unstructured strings, and the five highest-value route files emit none at all. | census, §3.1; zero in `payments.ts`, `auth.ts`, `admi… |
| S-416 | G3 | T22 | F-22-09 (S2) | — | — | The notification DLQ has no consumer. | `wrangler.toml:50-55` declares `dead_letter_queue`; n… |
| S-417 | G3 | T22 | F-22-10 (S2) | — | — | No crash reporting in either Flutter app or the admin console; no error hooks installed. | `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml… |
| S-418 | G3 | T22 | F-22-12 (S2) | — | — | The automated deploy pipeline is not installed. | file exists at `docs/ci/deploy-api.yml`, not `.github… |
| S-419 | G3 | T23 | F-23-10 (S2) | — | — | `flutter test` never runs in CI; only `analyze` | `.github/workflows/ci.yml:140,154,166` — analyze only |
| S-420 | G3 | T23 | F-23-11 (S2) | — | — | `apps/admin` has no test infrastructure whatsoever | `apps/admin/package.json:6-11` — no `test` script, no… |
| S-421 | G3 | T23 | F-23-12 (S2) | — | — | No dependency vulnerability scanning and no update automation | No `npm audit` in `ci.yml`; no `.github/dependabot.ym… |
| S-422 | G3 | T23 | F-23-13 (S2) | — | — | No secret scanning, and hygiene only catches secrets in files literally named `.env*` | `scripts/check_repo_hygiene.py:77,127-130` matches `^… |
| S-423 | G3 | T23 | F-23-14 (S2) | — | — | No linter of any kind for TypeScript | No `.eslintrc`/`eslint.config`/`biome.json` in the 44… |
| S-424 | G3 | T23 | F-23-15 (S2) | — | — | The parked deploy workflow exits **green** when its credential is missing | `docs/ci/deploy-api.yml:92-106` |
| S-425 | G3 | T23 | F-23-16 (S2) | — | — | The Worker is never bundled in CI — only type-checked | `ci.yml:54` runs `tsc --noEmit`; no `wrangler deploy … |
| S-426 | G3 | T23 | F-23-18 (S2) | — | — | The system has never been load tested | No k6/Artillery/JMeter artifact in inventory; no targ… |
| S-427 | G3 | T23 | F-23-19 (S2) | — | — | No one-command local environment; ~9 third-party secrets required to boot | `.dev.vars.example` (10+ keys); no `seed.sql` in inve… |
| S-428 | G3 | T23 | F-23-20 (S2) | — | — | No release versioning: no tags, no changelog, no approval gate | `APP_VERSION` is a static string in `wrangler.toml:76… |
| S-429 | G3 | T24 | F-24-01 (S1) | scale-priced | — | Admin polling scans the whole `trips` table ~4× every 8 s; ~300–470 B D1 rows read/month for two operators | `DashboardPage.tsx:49`, `LiveMapPage.tsx:156`, `admin… |
| S-430 | G3 | T24 | F-24-02 (S1) | scale-priced | — | D1 10 GB ceiling is reached in ~144 days at 10k trips/day, ~29 days at 50k. No retention or archival exists | `trips.ts:447`+`:472`, `routing.ts:30`, `captain.ts:2… |
| S-431 | G3 | T24 | F-24-03 (S1) | scale-priced | — | The KV rate limiter writes on every limited request; KV writes are $5/M | `rateLimit.ts:29`, `rateLimit.ts:50-51` |
| S-432 | G3 | T24 | F-24-04 (S1) | scale-priced | R5 | Location ping writes 2 D1 rows unconditionally, with no trip gate, at up to 30/min/captain | `captain.ts:205-209`, `captain.ts:231-235`, `captain.… |
| S-433 | G3 | T24 | F-24-05 (S2) | scale-priced | — | `TripRoom` registers sockets for hibernation but tracks them in an in-memory `Map`; after eviction the handler drops … | `TripRoom.ts:105` vs `:110`, `:123`, `:151` |
| S-434 | G3 | T24 | F-24-06 (S2) | — | — | `CaptainInbox` relay uses legacy `upstream.accept()`, defeating hibernation for that instance | `CaptainInbox.ts:175`, `:178` |
| S-435 | G3 | T24 | F-24-07 (S2) | — | — | `datetime()` wrappers on indexed columns make 5 hot queries non-sargable | `admin.ts:30`, `:91`, `:117`, `:165`, `:237` |
| S-436 | G3 | T24 | F-24-08 (S2) | — | — | Missing indexes on `captains(is_online, approval_status)`, `trips(completed_at)`, `trips(company_id)`, `users(role)` | `admin.ts:36`, `:40`, `:99-107`; `index.ts:344`; `saf… |
| S-437 | G3 | T24 | F-24-09 (S2) | — | — | `SELECT *` ships the full OSRM polyline to list views that never render it | `admin.ts:314`+`:320` (200 rows), `captain.ts:463` (2… |
| S-438 | G3 | T24 | F-24-10 (S2) | — | — | `DB.batch()` is used once in the whole API; every other handler pays one round-trip per statement | `admin.ts:506` is the only call site |
| S-439 | G3 | T24 | F-24-11 (S2) | — | — | `GET /admin/captains` performs an `UPDATE` — a write on a read path, polled every 10 s | `admin.ts:237`, `CaptainsPage.tsx:235` |
| S-440 | G3 | T24 | F-24-12 (S2) | — | — | Per-minute cron re-runs a full `users` scan *inside* its loop; SOS fanout awaits serially | `index.ts:316` inside loop at `:295`; `safety.ts:29-3… |
| S-441 | G3 | T24 | F-24-20 (S2) | scale-priced | — | `docs/COST.md` is wrong on both mechanism and magnitude | `COST.md:9` vs model; `COST.md:23` vs `captain.ts:205` |
| S-442 | G3 | T25 | F-25-11 (S2) | — | — | `audit_log` grows forever, carrying IP + user-agent on every row | `0002:39-49`; `cleanup.ts:29-57` never touches it |
| S-443 | G3 | T25 | F-25-12 (S2) | — | — | Bank / mobile-money account numbers written to two permanent stores | `wallet.ts:129` (ledger `note`), `wallet.ts:139` (aud… |
| S-444 | G3 | T25 | F-25-13 (S2) | — | — | Public `/track/:token` returns pickup and dropoff addresses despite claiming not to | comment `safety.ts:88-89` says "no PII"; body returns… |
| S-445 | G3 | T25 | F-25-14 (S2) | — | — | Expired share tokens are never purged | `0003:177-184`; no cleanup |
| S-446 | G3 | T25 | F-25-15 (S2) | — | — | Single `admin` role — no least privilege over identity documents | `middleware/auth.ts:67-74`; `admin.ts:11` |
| S-447 | G3 | T25 | F-25-16 (S2) | — | — | JWTs accepted in query strings for WS and document images | `middleware/auth.ts:23-25`; `index.ts:144`, `:199` |
| S-448 | G3 | T25 | F-25-17 (S2) | — | — | Error messages returned verbatim to callers | `index.ts:235`; `payments.ts:91` with PSP `data.detai… |
| S-449 | G3 | T25 | F-25-18 (S2) | — | — | User coordinates and typed search text sent to Nominatim in the query string | `geocode.ts:39-40`, `:100-102` |
| S-450 | G3 | T25 | F-25-19 (S2) | — | — | Phone numbers to Meta and emails to Resend with no visible transfer mechanism | `notifications.ts:114`, `:175` |
| S-451 | G3 | T25 | F-25-20 (S2) | — | — | `notification_log` stores FCM device tokens indefinitely | `0003:214-227`; `notifications.ts:351,359,367` |
| S-452 | G3 | T25 | F-25-21 (S2) | — | — | Raw phone/email embedded in a KV key | `auth.ts:98` (`otp-name:<identKey>`) |
| S-453 | G3 | T25 | F-25-22 (S2) | — | — | `turnstile_verifications` retains IPs forever behind a stale exemption comment | `0003:201-209`; `cleanup.ts:11-13` claims the table d… |
| S-454 | G3 | T25 | F-25-23 (S2) | — | — | No data-residency configuration; no DPO; no processing register | `wrangler.toml` has no `jurisdiction` key; nothing in… |
| S-455 | G3 | T25 | F-25-24 (S2) | — | — | Rider app declares always-on location on iOS with no implemented use | `apps/rider/ios/Runner/Info.plist:51`, `:57-59` vs An… |
| S-456 | G3 | T26 | F-26-09 (S2) | — | — | Version numbers are unmanaged and mutually inconsistent: both apps `1.0.0+1`, API `APP_VERSION 0.4.0` | `apps/rider/pubspec.yaml:4`, `apps/captain/pubspec.ya… |
| S-457 | G3 | T26 | F-26-10 (S2) | — | — | No crash reporting and no global Dart error handler in either app | `apps/rider/lib/main.dart:18-31`, `apps/captain/lib/m… |
| S-458 | G3 | T26 | F-26-11 (S2) | — | — | iOS has no signing identity, no entitlements file and no Podfile | `project.pbxproj` (no `DEVELOPMENT_TEAM`), `:335`, `R… |
| S-459 | G3 | T26 | F-26-12 (S2) | — | — | No prominent-disclosure screen before the location prompt | `apps/captain/lib/screens/onboarding/onboarding_scree… |
| S-460 | G3 | T26 | F-26-13 (S2) | — | — | No obfuscation (`--obfuscate --split-debug-info`) and no integrity checks on the captain app | Build commands in `scripts/*.bat`; no `--obfuscate` a… |
| S-461 | G3 | T26 | F-26-14 (S2) | — | R3 | 856 KB of dead splash video shipped in both APKs, plus store graphics inside the app bundle | `apps/rider/pubspec.yaml:63`, `apps/captain/pubspec.y… |
| S-462 | G3 | T26 | F-26-15 (S2) | — | — | Fonts are fetched at runtime; no bundled fallback | all three pubspecs (`google_fonts: ^6.2.1`, no `fonts… |
| S-463 | G3 | T26 | F-26-16 (S2) | — | — | Neither store account exists yet; Apple organisational enrolment needs a D-U-N-S number | `docs/CHECKLIST.md:25-26` |
| S-464 | G3 | T26 | F-26-17 (S2) | — | R3 | No staged rollout, kill switch, or client-side remote config; `system_config` exists but no client reads it | `migrations/0016_system_config.sql:20`, `apps/api/src… |
| S-465 | G3 | T27 | F-27-05 (S2) | — | — | Captain cannot cancel a trip from the app at all | only `apps/rider/lib/services/app_state.dart:513` cal… |
| S-466 | G3 | T27 | F-27-07 (S2) | — | — | Typing indicator is a half-built loop: captain sends and renders, rider does neither | endpoint `safety.ts:256`, broadcast `:278`; captain `… |
| S-467 | G3 | T27 | F-27-08 (S2) | — | — | Rider is never told how long the captain has been waiting; the captain watches a clock | captain 1 s tick from `arrived_at` `active_trip_panel… |
| S-468 | G3 | T27 | F-27-09 (S2) | — | — | Captain gets no in-app trip-completion summary; rider gets a full screen | rider `trip_screen.dart:550-564`; captain nulls `acti… |
| S-469 | G3 | T27 | F-27-10 (S2) | — | — | Cancellation is explicit for the rider and silent for the captain | rider `trip_screen.dart:567`; captain's card simply d… |
| S-470 | G3 | T27 | F-27-11 (S2) | — | — | SOS confirmation is asymmetric: rider must confirm, captain fires on one tap | rider dialog `sos_screen.dart:28-39`; captain has none |
| S-471 | G3 | T27 | F-27-12 (S2) | — | — | Captain SOS cannot share a tracking link; rider's can | rider `sos_screen.dart:94-104,:150`; no equivalent in… |
| S-472 | G3 | T27 | F-27-13 (S2) | — | — | No SOS can be cancelled by either party | no cancel/close route in `apps/api/src/routes/safety.… |
| S-473 | G3 | T27 | F-27-15 (S2) | — | — | Admin ships a different brand green from both apps | `apps/admin/src/design/tokens.ts:32` = `#4e842d`; `ap… |
| S-474 | G3 | T27 | F-27-16 (S2) | — | — | Admin dark mode is a switch wired to nothing | `ThemeContext.tsx` adds a `dark` class; `globals.css`… |
| S-475 | G3 | T27 | F-27-17 (S2) | — | — | 302 hardcoded Arabic lines in rider screens vs 30 in captain | worst: `profile_screen.dart` (40), `trip_screen.dart`… |
| S-476 | G3 | T27 | F-27-18 (S2) | — | — | Pickup point has four Arabic names across the two apps | «نقطة الانطلاق» (rider UI), «نقطة الالتقاط» (`app_str… |
| S-477 | G3 | T27 | F-27-19 (S2) | — | — | «سائق» appears where every other string says «كابتن» — in the rider's captain-chooser | `app_strings.dart:2706,:2710`; hardcoded twins at `ca… |
| S-478 | G3 | T27 | F-27-20 (S2) | — | — | «عميل» leaks into captain-facing copy where the rest of the product says «راكب» | `app_strings.dart:1820,:1851,:1855`; `counter_offer_s… |
| S-479 | G3 | T27 | F-27-21 (S2) | — | — | Admin typography diverges: IBM Plex Sans Arabic vs Cairo in both apps | `apps/admin/src/design/tokens.ts` font stack vs `AppT… |
| S-480 | G3 | T28 | F-28-01 (S2) | — | — | Map markers teleport. Zero interpolation; the car hops ~10 m roughly once per second for the whole trip. | `trip_screen.dart:145-151,379-393`; `vehicle_map_mark… |
| S-481 | G3 | T28 | F-28-02 (S2) | — | R4 | `flutter_shared` declares no animation dependency, so the shared animation library the product needs cannot live in t… | `packages/flutter_shared/pubspec.yaml:10-24` vs `ride… |
| S-482 | G3 | T28 | F-28-03 (S2) | — | — | The rider never receives or renders the captain's heading — the car points north for the entire trip. | `trip_screen.dart:387-390` (no `heading:` arg); cf. `… |
| S-483 | G3 | T28 | F-28-04 (S2) | — | — | Zero motion tokens. 24 hardcoded durations and 6 curves scattered across call sites, six of them duplicating one anot… | `app_theme.dart` (no `Duration`/`Curve` in 800+ lines… |
| S-484 | G3 | T28 | F-28-05 (S2) | — | — | Reduce-motion honoured in only 6 files. The captain splash runs an unbounded full-screen loop with no still fallback. | `skeleton_loader.dart:120-121` (the good pattern); `c… |
| S-485 | G3 | T28 | F-28-06 (S2) | — | — | Bid arrival is a wholesale list replacement with no keys and no insertion animation. | `captain_bids_sheet.dart:75-78,104-108,282-290` |
| S-486 | G3 | T28 | F-28-07 (S2) | — | — | Position updates rebuild the whole screen; the only `RepaintBoundary` is on the one map that barely changes. | `trip_screen.dart:220-315`; `main_shell.dart:399-492`… |
| S-487 | G3 | T28 | F-28-08 (S2) | — | R3 | 1.67 MB of dead `splash.mp4` shipped in both bundles; no `video_player` dependency exists to play it. | `apps/rider/assets/videos/splash.mp4` + `apps/captain… |
| S-488 | G3 | T28 | F-28-09 (S2) | — | — | The status chip — the most-watched element in the trip — swaps text and colour instantly. | `trip_screen.dart:412-426,741-751`; `status_chip.dart… |
| S-489 | G3 | T28 | F-28-10 (S2) | — | — | Captain splash hard-cuts to the next screen; the rider has a designed 560 ms handoff. | `captain/main.dart:82-86` vs `rider/main.dart:143-172` |


---

## 4. Shared roots

The same defect is described in up to five documents from five angles, each time as a local problem.
Collapsed, they are eight causes. **This is where the plan gets cheaper than the sum of its parts**:
fixing a root retires findings in tracks that never spoke to each other.

### R1 — There is no money-movement primitive, so six call sites hand-roll one and three get it wrong

*15 findings across T03, T04, T05, T10, T18, T27.*

The codebase has a correct idiom for moving money: insert the ledger row with `INSERT OR IGNORE` on
an `idempotency_key`, check `meta.changes === 1`, and only then move the balance. It is used
correctly at `trips.ts:1029-1053` for the cash-commission and captain-payout branches. It is *not*
used at the rider-debit branch twenty lines above, where the balance moves first and the result is
written into a `txnStatus` variable that nothing subsequently reads **[verified]**. It is not used in
the Paymob webhook, where an unguarded `UPDATE` follows the `INSERT OR IGNORE` and the intention is
marked settled forty lines later **[verified]** — the correct pattern exists four hundred lines lower
in the same file. It is not used in the payout path, which has no idempotency key at all despite
migration `0005` adding the column.

T03 found it as a ledger problem, T04 as a webhook problem, T05 as a settlement problem, T18 as a
fraud problem, T27 as a "two balances behind one label" problem. It is one missing function. T03's
P0.5 (`postEntryGroup`) is the right shape for it; **the consolidation insight is that P0.5 is not
just T03's ledger rebuild — it is the fix for findings filed in five other tracks**, and every one of
those tracks should be a reviewer on it.

### R2 — Authorization is expressed as route-registration order, and two routes are on the wrong side

*5 findings across T02, T17, T21, T25.*

There is no policy layer; `index.ts` applies no global `authMiddleware`, and whether a route is
authenticated depends entirely on whether it was registered before or after
`tripRoutes.use("*", authMiddleware)`. Two routes are on the wrong side of that line, in opposite
directions, and neither is a typo anyone would catch by reading the route handler:

- `POST /trips/estimate` is registered at `trips.ts:315`, the guard at `:346` **[verified]** — so it
  runs unauthenticated, returning live captain identities and positions to anyone.
- `GET /safety/track/:token`, the *public* share endpoint, sits under `safetyRoutes.use("*",
  authMiddleware)` at `safety.ts:11` **[verified]** — so the one route that must be public is the one
  that demands a JWT. Compounded by the URL handed to the sharer omitting the `/safety` mount prefix
  entirely (`safety.ts:83` vs `index.ts:120`) **[verified]**.

The fix for both is one line each; the fix for the *class* is T02's P2.1 policy layer. Until that
exists, a test asserting the auth posture of every route is the cheapest guard, and it is the one
test T17's author says they would not ship without.

### R3 — Work is declared done at the point of definition, not the point of effect

*18+ instances across T03, T05, T12, T14, T15, T17, T19, T20, T21, T22, T26, T27, T28.*

**This is the most important root in the document**, and it is the one the user of this plan should
take most seriously, because it is not a bug — it is a habit.

| Defined | Never called | Track |
|---|---|---|
| `apps/admin/src/design/tokens.ts` — 248 lines, correct AA brand green at `:32` | imported by zero files; the failing `#6bb522` renders instead | T12, T15 |
| ARB / `gen-l10n` pipeline, 208 entries | `AppLocalizations.delegate` registered in neither `main.dart` | T14, T27 |
| `MapTiles.attribution`, commented as legally required | rendered nowhere in either app | T21 |
| `hasRealGeometry` (`location_service.dart:49`) | zero call sites — so a 2-point straight line renders as a normal route | T21 |
| `estimateTripFare` (`pricing.ts:23-34`) | zero call sites in `apps/api/src` | T21 |
| `logAudit` imported at `trips.ts:20` | zero call sites in 1,371 lines — the money path writes no audit rows | T22 |
| `NOTIFICATIONS` queue + DLQ, fully configured | no producer anywhere calls `env.NOTIFICATIONS.send` | T19 |
| `splash.mp4`, 856 KB, declared in both pubspecs | no `video_player` dependency; 1.67 MB of dead bytes shipped | T26, T28 |
| `ApiClient`, `TripModel`, `UserModel`, `loading_overlay`, `offline_gate` exported from `flutter_shared` | both apps use raw `Map<String,dynamic>` and hand-rolled HTTP | T27 |
| `wallet_balance_piastres` etc. from migration `0005` | written by some paths, skipped by others, read by none | T03, T04 |
| `system_config` — seven admin-writable knobs | no Flutter client reads them; cancellation-fee settings are dead | T05, T23, T26 |
| `spend_limit_month`, `allowed_vehicle_types`, `allowed_hours`, `credit_limit` | enforced nowhere | T20 |
| `rating_avg` | read by no dispatch, ordering, threshold or review path | T17 |
| `read_at` (chat), `app_role` (device tokens), `no_show` (intercity), `speed` (path points) | selected/accepted and never used | T27, T26, T20, T21 |

Two consequences follow, and they are why this root matters more than its individual entries:

1. **A dedicated sweep is worth more than 18 separate tickets.** One engineer, one pass, with a
   simple rule — for every exported symbol, config key and declared asset, either find a call site or
   delete it. Estimated M. It retires findings in eleven tracks and removes ~2.5 MB from both APKs.
2. **It is the same failure as the unverified-PR problem.** PR #46 committed a deploy workflow to
   `docs/` and was titled as though it had installed one. That is this root, applied to process
   instead of code: the artefact was created, the effect never was, and nobody checked. §9 is built
   around this.

### R4 — Two apps, one behaviour, two implementations, and the fix lands in one of them

*16 findings across T03, T06, T07, T09, T10, T12, T13, T14, T15, T16, T17, T20, T24, T26, T27, T28.*

`trip_ws.dart`, `trip_chat_screen.dart`, `login_screen.dart`, the wallet screens, the SOS screens and
the splash screens all exist twice, with measured similarity of 50–57% — meaning they were copied and
then diverged. The pattern that matters is not the duplication itself but its consequence: **a fix
lands in one app and not the other, and the two halves of one trip then disagree.** The captain's
chat has WebSocket delivery, a typing indicator and `AppStrings`; the rider's has none, and renders
history in reverse order — the two people in one car read the same conversation in opposite
directions. The captain's SOS uses the correct dark token; the rider's hardcodes a light one and
renders a full-brightness white screen at night. `AlignmentDirectional` was fixed in the captain's
chat and not the rider's. Reduce-motion is honoured in the rider's splash and ignored in the
captain's.

`packages/flutter_shared` exists and is the obvious home — but see R3: it already exports components
neither app imports. **Extraction is not the hard part; adoption is.** T27 owns this and its P0.1–P0.3
(shared `TripStatus`, shared chat view, shared SOS view) are the entry point; T12's primitives, T13's
motion tokens and T28's animation library must all land *inside* that shared layer rather than beside
it, or this root regenerates.

### R5 — One location pipeline, four independent breaks, four tracks

*8 findings across T06, T07, T10, T21, T24.*

The captain's position is the product. It fails in four places at once, and no single track saw all
four: location is published only on 50 m of movement with no time floor, so a **stationary** captain
ages out of the GeoCell after 120 s and stops being dispatchable (T06); backgrounding the app cancels
the GPS stream entirely while D1 still records `is_online = 1` (T06, T10); there is no Android
foreground service, so this happens every time the captain opens Google Maps to navigate (T10); and
at real driving speed the 50 m filter publishes 1.7–3.9× faster than the server's own 30/60 s rate
limit accepts, so the excess is 429'd and silently discarded (T07, T21). The rider sees the car move
for a quarter of a minute, freeze for 38–47 seconds, then teleport.

The trap here is that the four fixes interact: lengthening the publish interval to respect the rate
limit makes the marker look *worse* unless interpolation ships with it (T13, T28 both say so
explicitly), and T24 additionally wants the rate-limit counter moved off KV into the GeoCell DO the
request already contacts. **This is one work item, not four**, and it is gate item 8.

### R6 — The trip lifecycle has no terminal state, and the rider pays for it

*7 findings across T06, T09, T16, T27.*

No timeout, no "unfulfilled" status, no sweeper: a trip nobody accepts stays `searching` forever. The
`ACTIVE_TRIP` guard then refuses to let that rider book again — and the 409 that would let the client
recover carries a `tripId` the rider app discards. Add F-06-01/F-16-02 (scheduled trips dispatch at
booking time, exhausting the wave rollout hours early) and the most reliable way to brick a rider
account is to book a ride for tomorrow morning.

### R7 — Two timestamp formats in one column type, and the invoices are wrong

*4 findings across T08, T20.*

`lib/utils.ts:5` writes ISO-8601 with `Z`; SQL defaults write `YYYY-MM-DD HH:MM:SS`. Both land in the
same TEXT columns. Five sites compare them raw and eight normalise. The visible consequence is
financial: the monthly B2B invoice job's `SUM` and its settling `UPDATE` disagree about format, so
first-day trips are re-invoiced *every minute* — and a second generator in `companies.ts` has the
mirror defect and under-bills. T20 reproduced all three behaviours in SQLite. One root, two invoice
generators, three billing outcomes, real corporate money.

### R8 — Nothing observes, and nothing enforces

*8 findings across T22, T23.*

No monitor, no alert rule, no external probe exists in any file. `/health` is a static literal that
touches no binding and is the only gate in the deploy smoke test. One handler serves both crons,
ignores `event.cron`, and swallows every error — so Cloudflare records 100% successful invocations
while the dispatch cron silently does nothing. And `main` is unprotected **[verified]**, so none of
the checks that do exist can stop anything. The observability half and the enforcement half are
usually filed separately; together they mean **the platform can neither prevent a bad change nor
notice its effects**, which is the precondition for the whole "claimed fixed, was not fixed" pattern
in R3.

---

## 5. Contradictions, and the ruling

Tracks recommended incompatible things. Each is decided here, with the reason. Where I cannot decide
on evidence, it goes to §5.10 as an open decision with a recommendation — not left silent.

### 5.1 Google Places vs. the entire map stack — **ruled: reject Google Places**

- **T21** recommends a commercial geocoder with **Google Places preferred** for Arabic Egyptian POI
  quality (P1.2), having measured public Nominatim returning *zero results* for ordinary
  landmark-relative Egyptian phrasing in 3 of 14 live queries, and resolving `كوبري أكتوبر` to a
  bridge ~30 km away.
- **T21 itself** also notes Google's terms forbid displaying Google-sourced results on a non-Google
  map, and separately recommends **MapTiler or Mapbox** for tiles (P0.4).
- **T12** independently chooses **MapTiler or self-hosted OpenMapTiles** (P2.1), replacing the CARTO
  free legacy CDN.
- Both Flutter apps are built on `flutter_map` with CARTO tiles, and the admin console on Leaflet.

**Ruling: do not adopt Google Places.** Its quality advantage is real, but it is only purchasable
together with moving the entire map surface to Google — which contradicts T12's tile decision, T21's
own tile decision, and the `flutter_map` architecture in both apps and the admin console. Adopt
**Mapbox for geocoding and tiles together** (one vendor, mutually compatible terms, T21's own
"pragmatic alternative"), and **self-hosted OSRM for routing** (T21 P0.1, ~\$10–20/month from the
169 MB Geofabrik Egypt extract). Mitigate the Arabic-POI quality gap with T21's curated local
`places` table seeded from the F-21-06 failure corpus, which T16 also proposes — that is cheaper than
a vendor migration and it compounds.

### 5.2 Which balance is authoritative? — **ruled: T03 wins the end state, T27 ships first**

- **T27 P0.4:** make `users.wallet_balance` the single authority; ledger aggregation becomes a
  reconciliation figure returned alongside.
- **T03 P0.5:** rebuild as a double-entry ledger in which the *ledger* is authoritative and
  `amount_piastres INTEGER` is the only amount column.
- **T10** raises it as an open question, having found the captain's displayed balance and the balance
  gating their payout are computed by different queries.

These are opposite architectures and both are filed as P0. **Ruling: they are not alternatives, they
are phases.** T27's P0.4 ships first — it is S-sized, it stops the captain being shown a number
different from the one the payout guard enforces, and it does not foreclose anything. T03's P0.5 then
makes the ledger authoritative and demotes `users.wallet_balance` to a derived cache. **This must be
written down where the T27 work happens**, because implementing T27 P0.4 as though it were the
permanent design is the obvious mistake, and it would have to be unwound.

### 5.3 Integer piastres: three tracks, three migrations — **ruled: one cutover, owned by T03**

T03 P0.5, T08 P2.1 and T20 P2.2 each propose their own slice of the same float→integer currency
migration, and T05 P1.3 proposes a fourth for the bidding columns. Migration `0005` already attempted
this once and left shadow columns that are written by some paths and read by none (R3). **Ruling: one
cutover, owned by T03, absorbing all four.** A partial repeat of `0005` is worse than the current
state, because it adds a third representation.

### 5.4 Where does instrumentation live? — **ruled: T22's pipeline, no exceptions**

T21 (P0.3 geo counters), T18 (`risk_events` alerting), T19 (an `analytics_events` table its author
calls "an interim shim"), T24 (§8 metrics), T03 (P0.7 reconciliation alerts) and T11 (audit-failure
counter) each specify their own emission path. T22 explicitly asks that they not. **Ruling: T22's
structured-logging and Analytics Engine pipeline is the only sink.** Every other track's observability
item becomes a producer within it. Six parallel telemetry paths in a two-person team is how you get
six things nobody watches — and note T22's own constraint: do not enable Logpush until the `?token=`
WebSocket parameter is removed, or JWTs get persisted to storage.

### 5.5 ARB vs. AppStrings — **ruled: delete ARB (T14 and T27 over T09)**

T14 P0.1 and T27 P2.1 both say delete the dead ARB pipeline and keep the 544-key `AppStrings`
catalogue. **T09 recommends the opposite** — register the delegate and migrate onto ARB. **Ruling:
delete ARB.** T14 owns the axis and has the stronger argument: `AppStrings` drift is a compile error,
ARB drift is silent, and 544 live keys against 208 dead ones makes the migration direction obvious.
Flagged explicitly because T09's rider-app owner would otherwise implement the reverse in good faith.

### 5.6 Does SOS confirm? — **ruled: hold-to-activate, one shared implementation**

Three positions: **T15** wants hold-to-activate (~1.5 s, haptic), built once in `flutter_shared`, and
explicitly rejects both "both apps confirm" and "neither confirms". **T10** treats the rider's
confirmation dialog as a defect — a tap in a panic. **T27 P0.3** proposes extracting the captain's
visual treatment *plus the rider's confirmation dialog*, i.e. keeping it. And **T17** finds the dialog's
text is factually false. **Ruling: T15's hold-to-activate.** It satisfies T10 (no extra tap), gives
T27 its single shared component, and lets T17 delete the false copy rather than rewrite it.

### 5.7 Fail-open or fail-closed — **ruled: split by control type**

T22 recommends the rate limiter keep failing open and says the decision is T02's; T02's P1.2 proposes
KV revocation that also fails open, for availability; T01 files Turnstile's fail-open as an S1. The
three are inconsistent. **Ruling: availability controls fail open with a counter and an alert (rate
limiting); security controls fail closed (Turnstile, suspension revocation).** A bot defence that
disappears when a secret is unset is not a defence, and T01 is right to call it S1.

### 5.8 Which green? — **ruled: engineering constraint fixed, choice is the owner's**

T12 Route A proposes `#7CC142` for dark mode; T15 requires `#4E8419` for AA; T27 wants `#4e842d`;
today Flutter ships `#4E842D` and the admin console renders `#6BB522` at 2.54:1. Four values, three
tracks. **Ruling: the *choice* belongs to the product owner (T12 Q1) but the *constraints* are not
negotiable** — one value, shared by Flutter and admin from a single generated token source (T12 P1.1),
and it must clear 4.5:1 on white. That reduces a four-way disagreement to a single decision with a
pass/fail test. Related and separate: the product ships under two names ("GoDrive" in the UI,
"Synaptic Go" in every push notification). That is also an owner decision and it blocks T12 P0.1.

### 5.9 Cairo and Giza — **ruled: one dispatch pool**

T06 encodes `city` into the GeoCell key, making Cairo and Giza separate dispatch namespaces for
captains who may be two kilometres apart; T21 raises the same thing from the geo side and notes
`city` is unvalidated client-supplied text that *also* selects the tariff row. **Ruling: one pool for
dispatch, tariffs still resolvable per governorate, and `city` must stop being client-supplied** —
derive it server-side from the coordinates. Under a Cairo-only launch this is not gate, but it must
be settled before the second city, and the client-supplied tariff selector should be closed with the
dispatch change.

### 5.10 Open decisions — cannot be ruled on evidence

These need the product owner. Each has a recommendation; none should be left to be decided implicitly
by whoever writes the code first.

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | **The launch shape itself** (§2.1) | narrow as proposed / enable wallet+card / enable verticals | Narrow. Enabling payments adds ~3 engineer-weeks and 6 gate items. |
| D2 | Does booking **fail** when routing fails? | 503 and let the rider retry / keep silent straight-line pricing | Fail the booking. A rare visible error beats permanent silent mispricing. |
| D3 | Who funds a promo discount? | platform / captain / split | Platform. Today the captain silently funds ~85% and does not know. |
| D4 | Cancellation-fee level, grace window, and recipient | — | Needed before T16 P0.3 can be built at all. |
| D5 | Number masking for rider↔captain calls | PSTN vendor / in-app VoIP / defer | Defer, but stop returning `rider_phone` pre-acceptance immediately. |
| D6 | Who is on call at 03:00, and are they staff? | founder rotation / in-house / outsourced first line | Required before gate item 10 means anything — an SOS queue with nobody watching it is R3 again. |
| D7 | WCAG AA: commitment or aspiration? | — | Changes whether §3.2's largest downgrade is correct. |
| D8 | Chat and location-trace retention windows | 30/90/365 days | 90 days, pending counsel (T25). |
| D9 | Egyptian PDPL, VAT after Law 157/2025, transport licensing, captain employment classification | — | External counsel. **Start now** — these have the longest lead times in the plan and no engineering can compress them. |

---

## 6. Dependencies and execution waves

### 6.1 Work that must land *inside* another track's work, not beside it

This is the list that a flat P0 backlog cannot express, and getting it wrong is how a parallel team
produces two of everything. Each row is a merge requirement, not a coordination suggestion.

| This work | Must land inside | Why |
|---|---|---|
| T21 P0.3 geo counters · T18 `risk_events` alerts · T19 DLQ/analytics · T24 §8 metrics · T03 P0.7 reconciliation alerts · T11 audit counter | **T22's logging + Analytics Engine pipeline** | §5.4. Six parallel telemetry paths = six things nobody watches. |
| T04 P0.1 webhook · T05 settlement · T18 P0.1 · T20 intercity money · T16 cancellation/waiting fees | **T03's money primitive (P0.5 `postEntryGroup`)** | R1. Each is another hand-rolled copy of the idiom that is already wrong in three places. |
| T08 P2.1 · T20 P2.2 · T05 P1.3 | **T03's single integer-currency cutover** | §5.3. Migration `0005` already half-did this once. |
| T09/T10 screen fixes · T12 primitives · T13 motion tokens · T15 SOS · T17 chat · T28 animation library | **T27's `flutter_shared` component layer** | R4. Extraction is easy; adoption is the whole problem. |
| T12 · T13 · T14 · T15 · T25 proposed CI workflows | **T23's single installed `.github/workflows/`** | All five are blocked on the same missing `workflows` permission and the same human `git mv`. |
| T28 P1.x signature moments | **T13 P0.4 motion tokens** | T13 and T28 both say so; T28 cannot start without the token scale. |
| T27 P0.4 balance unification | **precedes** T03 P0.5 | §5.2 — phases, not alternatives. |
| T11 P0.2 SOS console | **with** T17 P0.2 SOS queue | Same feature from two sides; shipping either alone leaves an alert nobody can action. |

### 6.2 Ordering traps

Every one of these was stated by a track author and would be invisible in a flat list. Violating them
makes the product *worse* than not doing the work.

1. **T01 P0.3 before T01 P0.2.** Client single-flight refresh must be adopted *before* server-side
   atomic rotation, or the security fix logs every captain out en masse.
2. **T07 P0.2 before T07 P1.3.** `serializeAttachment` must survive eviction before hibernation is
   enabled, or rare bugs become routine ones — and the alternative costs ~\$4,000/month.
3. **T28 P1.1 with or before T07 P0.1.** Lengthening the publish interval without marker
   interpolation makes the car look worse even though the data is strictly better.
4. **T08 P0.2 before T08 P1.3.** Normalise timestamps before removing the `datetime()` wrappers in
   `admin.ts`, or a slow query becomes a wrong one.
5. **T19 P0.1 before T19 P0.2.** Fix the queue consumer before adding the first producer, or 100% of
   messages fail three times into a DLQ with no consumer.
6. **T06 P0.2 before T06 P0.5/P0.6**, and **T06 P1.3 after T06 P0.1** — changing the cell key before
   the heartbeat exists produces a supply blackout.
7. **T10 P0.1 with T10 P0.6.** Shipping the navigation hand-off without the foreground service
   actively worsens the product: it encourages captains to leave an app that cannot survive being
   left.
8. **T20 P0.2 before intercity ships**, and **T14 P0.2 ratchet before T14 P1.1 migration**.
9. **T23 P0.1 before everything.** Branch protection is what makes every other gate enforceable.

### 6.3 The waves

**Wave 0 — the first day.** Cheap, unblocking, and mostly configuration. Nothing else should start
until these are done, because they are what make later work verifiable.

- Branch protection + required checks (gate 1) · install the deploy workflow via human `git mv`
  (gate 2) · kill the bare `wrangler deploy`
- Enforce the launch shape server-side (gate 3) · freeze the payout button (gate 4) · disable the
  B2B invoice cron (gate 5)
- One-line truth fixes: `/accept` settles `offered_price` (gate 6) · remove the false SOS copy ·
  rider SOS dark-mode token · disable the `سفر` chip
- **Start every external clock on day one**, because none of them can be compressed later: counsel
  for PDPL/VAT/licensing/employment classification (D9), Apple D-U-N-S enrolment, Meta WhatsApp
  template approval, Paymob sandbox credentials, and the OSRM host.

**Wave 1 — the launch gate (remaining items 7–16).** Roughly 4–6 engineer-weeks with the team in §7.
Ends when a paying passenger can be carried responsibly. Sequenced by §6.2, with gate 8 (the location
pipeline) as the long pole and gate 12 (privacy) as the item most likely to slip on external
dependencies rather than code.

**Wave 2 — first 30 days after launch (the 98 G2 findings).** The R3 dead-code sweep (one engineer,
one pass, eleven tracks retired). T15's accessibility P0 block — one focused week, and the thing this
plan is least comfortable deferring. T27's shared component layer, which unlocks T12/T13/T28. T01's
session work. T17's absent safety features, now with an operator to run them. T19's notification
queue, before anything starts producing to it.

**Wave 3 — 90 days / volume-triggered (the 316 G3 findings).** T24's cost work, triggered by measured
volume rather than by date — the natural trigger is T24's own: 6 GB of D1 or p95 statement duration
above 500 ms. T08's retention and integer-currency cutover. T18's risk engine. T20's verticals. T28's
signature moments. **Do not schedule these by date.** Wave 3 exists so that Wave 2 does not silently
absorb it.

---

## 7. Effort by discipline

Aggregated mechanically from all 403 planned items across the 28 documents, with each track assigned
to the discipline that owns most of its work. `S/M/L` are the authors' own effort labels.

| Discipline | P0 | P1 | P2 | Reads as |
|---|---|---|---|---|
| **Backend / API** | 94 (S37 · M47 · L10) | 77 (S21 · M37 · L18) | 45 (S7 · M14 · L15) | The centre of gravity, by a wide margin |
| **Flutter (both apps)** | 43 (S27 · M15 · L1) | 47 (S10 · M25 · L5) | 25 (S4 · M9 · L8) | Many small items — consistent with R4: the same fix, twice |
| **Ops / CI / Release** | 25 (S12 · M12) | 12 (S2 · M6) | 6 (L3) | Cheap and high-leverage; almost all of Wave 0 |
| **Admin console** | 6 (M5 · L1) | 5 | 3 | Small count, large items — the console is missing whole surfaces |
| **Legal / compliance** | 10 (S2 · M5 · L3) | 5 | 0 | Calendar-bound, not effort-bound |
| **Total** | **178** | **146** | **79** | |

**Translated to a small team.** Assumptions, stated so they can be disagreed with: two backend
engineers, one-and-a-half Flutter engineers, one part-time ops/release engineer, a founder acting as
product owner, and external counsel on retainer. S ≈ half a day to one day, M ≈ one to three days,
L ≈ one to two weeks. No allowance for the recruitment of anyone new.

| Phase | Elapsed, that team | Notes |
|---|---|---|
| Wave 0 | **1–2 days** | Mostly configuration; one human `git mv`; the external clocks start here |
| Wave 1 (the gate) | **4–6 weeks** | Long poles: gate 8 (location pipeline, L), gate 12 (privacy — calendar-bound), gate 13 (Android release). Not compressible below ~4 weeks by adding people, because gate 12's dependencies are external. |
| Wave 2 (30 days) | **6–8 weeks** | Overlaps launch. Dominated by T27's shared layer and T15's accessibility week. |
| Wave 3 (90 days) | **quarter-scale** | Explicitly volume-triggered, not date-triggered. |

**The honest read: this is a 10–14 week programme to a responsible narrow launch and a stable first
30 days, not the "178 P0 items" the raw backlog implies.** The biggest single risk to that estimate
is not engineering — it is D9. If counsel and licensing take eight weeks, gate 12 sets the launch
date and everything else finishes early.

---

## 8. What we are explicitly not doing now

A plan without this section is a wish list. Each of these is evidenced, real, and deliberately not
being done before launch. The reason matters more than the item.

| Not doing | Why not | Revisit when |
|---|---|---|
| **Wallet and card payments** | The mint (R1) and the replay are in this surface. Disabling is hours; fixing correctly is ~3 engineer-weeks. Cash-only is also how inDrive operates in this market. | The ledger rebuild (T03 P0.5) plus reconciliation (T04 P0.5) are done and tested |
| **Intercity and B2B** | Two whole verticals with no admin surface, no operator, and live billing defects. B2B is currently auto-billing employers with no opt-in — no procurement department accepts that. | After the first quarter; B2B before intercity (less work, contracted revenue) |
| **Promotions and referrals** | Four independent budget-drain paths (TOCTOU, free create-cancel loop, no per-user cap, captain-funded discount). The referral loop does not exist at all. | When there is a marketing budget and D3 is answered |
| **iOS** | 6–10 weeks from a standing start, most of it not code. Android dominates the Egyptian market. | Enrolment paperwork starts Wave 0; ship when it clears |
| **T24's cost programme** | Priced at 10k–50k trips/day; worth ~\$20/month at launch volume. Fixes are cheap and will still be cheap later. | 6 GB D1, or p95 statement duration >500 ms |
| **The risk/fraud engine (T18 P1+)** | A closed, manually-onboarded captain cohort is a stronger control at launch scale than any rule engine — and it is free. The engine matters when supply is open. | When captain onboarding opens to self-service |
| **Turn-by-turn navigation, multi-stop, female-driver matching, loyalty, delivery** | Competitive surface, not launch surface. T20 sizes delivery alone at 14–19 engineer-weeks plus operational capability the company does not have. | Post-launch, on evidence of demand |
| **Full WCAG AA conformance** | The P0 subset (~1 week) is Wave 2; full conformance including 200% text-scale reflow is larger. | Wave 2 for the P0 block; full conformance driven by D7 |
| **The dead-code sweep (R3) as 18 separate tickets** | Doing it as one pass is cheaper and catches instances nobody filed. | Wave 2, one engineer, one pass |

**Descoped is not fixed.** Every G1‡ row in §3.3 is a defect that a configuration change is hiding.
The register of those 25 findings is the checklist that must be worked *before* the corresponding
surface is re-enabled, and it should be read at the meeting where someone proposes turning card
payments on.

---

## 9. Protocol for the execution phase

The review protocol was built for parallel, independent, read-only work. Implementation is the
opposite: the tasks are coupled, they write to shared files, and they can break each other. Reusing
`board/PROTOCOL.md` unchanged would be a mistake. This replaces it.

### 9.1 Rules

1. **One task is one change.** A task that touches an API contract, a migration and two Flutter apps
   is three tasks with a stated order — see §6.2 for what happens when they land in the wrong one.
2. **Tests are mandatory and named in the task.** Every task states its test before it starts. A task
   whose test is "manual check" is not ready to be worked. The API currently has zero tests, so the
   first tasks in each area carry the cost of the first fixture; that is expected and is not a reason
   to skip.
3. **No self-merge.** The author of a change never merges it. This is now enforceable rather than
   aspirational, because gate item 1 turns on branch protection.
4. **Migrations are forward-only and rehearsed.** Four existing backfills are irreversible. Every
   migration PR states its rollback (a forward repair migration, or a restore) and the restore has
   been executed at least once — gate item 15.
5. **Claims stay atomic.** Keep `board/claims/` and the create-without-`sha` lock; it worked. Add a
   heartbeat: an in-progress claim untouched for 90 minutes is takeable, and the takeover is recorded
   in the file rather than performed silently.
6. **`PROJECT.md` stays append-only** with the sentinel and the re-read-on-conflict rule. It worked
   28 times.

### 9.2 Independent verification — the part that is not optional

**This is the reason this document exists at all.** This review round was commissioned because a
previous fix round declared success without verification. The briefs given to the 28 chats told them
to treat every claim from ~58 prior PRs as unverified until they read the code on current `main` —
and that instruction was vindicated: T23 established that PR #46, titled *"deploy the API from main
instead of from someone's laptop"*, merged without doing so, and `docs/DEPLOYMENT.md` records PR #45
sitting merged while all three of its fixes were still reported broken, because the live Worker
predated the merge. §4's root R3 shows the same shape eighteen more times in the code itself.

If the implementation phase runs on the author's word, there will be a third round that says the same
things again.

**Therefore, for every implementation PR:**

- **A second chat verifies against `main` after the merge, not against the PR description.** It reads
  the code as it now exists, re-runs the reproduction from the original finding, and posts the result
  as a comment on the PR and a line in `PROJECT.md`. The verifier is not the author and does not read
  the author's summary before forming a view.
- **A finding is closed by the verifier, never by the author.** The author moves it to
  `awaiting-verification`. This single rule is what R3 is missing at the process level.
- **The verification names the effect, not the artefact.** "Workflow file added" is not verification;
  "workflow ran, run URL, deploy landed" is. "Token defined" is not verification; "token rendered on
  screen, screenshot attached" is. This wording is deliberate — R3 is a catalogue of artefacts that
  were created while their effect never was.
- **Nine claims in this document are marked [verified]** and were re-opened by hand against
  `b0c0866`. Every other `path:line` inherits its author's snapshot. Before acting on any citation
  not marked `[verified]`, open the file.

### 9.3 Suggested lightweight cadence

A daily 15-minute standing check against exactly three questions: what merged, what did the verifier
independently confirm, and which of §6.2's ordering constraints is now at risk. Nothing more
ceremonious than that — the team in §7 is five people.

---

## 10. Gaps, and what this consolidation could not do

### 10.1 What was verified first-hand

Nine claims were re-opened against `main` at `b0c0866` because a decision in §2 or §5 rested on them.
All nine confirmed:

1. `trips.ts:993-1053` — rider debit computes `txnStatus`, which is then never read; the captain
   credit block executes regardless. The mint is real.
2. `payments.ts:175-186` + `:223` — unguarded balance `UPDATE` after `INSERT OR IGNORE`, intention
   settled 40 lines later. The replay window is real.
3. `payments.ts:12-18` — `amount` and `tripId` are both caller-supplied and unvalidated.
4. `trips.ts:468` — `body.paymentMethod || "cash"`: the API accepts `wallet` from any caller
   regardless of what the shipped client sends. **This is why gate item 3 must be server-side.**
5. `trips.ts:315` vs `:346` — `/estimate` is registered above `authMiddleware`.
6. `safety.ts:83` vs `index.ts:120`, and `safety.ts:11` — the share URL omits the `/safety` prefix,
   and the "public" route is behind the auth middleware. Both bugs, as described.
7. `build.gradle` — `targetSdk = 34`; `signingConfig = keystorePropertiesFile.exists() ?
   signingConfigs.release : signingConfigs.debug`.
8. `wrangler.toml:88`, `:148`, `:176` — `router.project-osrm.org` in default, prod and staging;
   `routing.ts` falls back through a bare `catch`.
9. GitHub branch API for `main` — `protected: false`, `enforcement_level: "off"`, `contexts: []`.

### 10.2 What could not be calibrated

- **No production or runtime access.** Nothing here observes the live system. Whether Turnstile is
  configured, whether migrations 0018/0019 are applied to prod, whether `OSRM_URL` is overridden by a
  secret, and what actual p50/p95 latency is — all unknown, all raised by their tracks as
  `needs-check`, none resolvable from the repository. T23's recommendation stands: run
  `wrangler d1 migrations list --remote --env prod` before anything else ships.
- **Effort labels are the authors' and were not re-estimated.** They are internally consistent within
  a track and probably not across tracks. §7's totals inherit that.
- **Severity for a market this document cannot see.** Whether a 2.54:1 contrast ratio or a missing
  Arabic POI is "serious" depends on the buyer and the user, and 28 engineers reviewing code cannot
  settle it. §3.2's largest downgrade (accessibility) is the most exposed to this.
- **Some duplicate detection is inference.** Where two tracks cite the same `path:line` the merge is
  certain. Where they describe the same behaviour in different words — several R3 and R4 entries —
  the merge is a judgement and could be wrong in either direction.

### 10.3 Process gaps

- **All 28 tracks were `done` at the readiness gate**, with PRs #59–#86 and no `in_progress` or
  `abandoned` claims. The consolidation is complete with respect to its inputs.
- **None of the 28 PRs is merged.** If any is revised during review, this document is stale in that
  area. It should be regenerated after the 28 merge, or the merge should be treated as a formality —
  but not both silently.
- **T29's claim was taken over at 13 minutes rather than the 90 minutes `PROTOCOL.md` §2.8
  specifies.** The prior holder had produced no branch, no document and no PR, and the repository's
  newest commit was still T22's `PROJECT.md` entry from 16:50Z. Nothing was overwritten because
  nothing existed. The full reasoning is in `board/claims/T29.md` rather than hidden.
- **Two tracks (T20, T25) nest their plan items under `6.x` subheadings** and three branch names in
  the repository duplicate task numbers (`plan/02-matching-dispatch-engine`,
  `plan/04-payments-wallet-ledger`, `plan/06-realtime-infrastructure`, `plan/12-trust-and-safety`) —
  stale branches from an earlier round, not additional deliverables. The claim files are the
  authority on which branch holds which document.

### 10.4 Questions only the product owner can answer

Consolidated from all 28 documents' §10 sections. The nine in §5.10 (D1–D9) are the ones that block
work. Beyond those, the recurring ones — each raised independently by three or more tracks — are:
**who is on call and are they staff**; **is WCAG AA a commitment**; **what is the product called and
what colour is it**; **who funds discounts**; **what are the retention windows**; and **is this a
timetable business or a marketplace business** for intercity.

The single most urgent is **D9**. Everything else in this plan is compressible by adding engineers.
Egyptian PDPL standing, VAT treatment after Law 157 of 2025, transport-sector licensing, and whether
captains are contractors or employees are not, and they gate the launch as hard as any line of code
in §2.

---

*Consolidation of T01–T28 · `chat-20260801-1723-8e5c` · base `b0c0866` · 2026-08-01*
