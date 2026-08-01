# WAVE-PLAN — what runs when, and the proof it does not collide

Derived from `docs/plan/00-EXECUTION-PLAN.md` §2.2 (the 16-item launch gate) and §6 (waves).
This file exists because the gate is a good **decision list** and a bad **work breakdown**.

Base `main` at generation: `f480905deb2db331d9087594ccd285029ba61660`. Regenerate with `validate.py` after any brief edit —
the schedule below is computed from the briefs' `depends_on` and `owns` fields, never typed by hand.

> **Read this before claiming anything.** The round number in each brief is not advice. A task whose
> dependencies have not merged cannot be worked on: its `owns` files are still moving underneath it.

## 1. The schedule

| Round | Runs in parallel | Tasks |
|---|---|---|
| **0** | 1 human | **E00** |
| **1** | 5 chats | **E01** · **E05** · **E06** · **E11** · **E16** |
| **2** | 4 chats | **E02** · **E17** · **E18** · **E20** |
| **3** | 3 chats | **E03** · **E12** · **E13** |
| **4** | 4 chats | **E04** · **E08** · **E14** · **E15** |
| **5** | 3 chats | **E07** · **E09** · **E19** |
| **6** | 1 chat | **E10** |

**Critical path — 6 deep:** `E01` → `E02` → `E03` → `E08` → `E09` → `E10`.
This is the floor. Opening more chats cannot beat it, because every arrow on that path is a
*merge*, not a handoff: the next task reads the previous task's code on `main`.

**Do not open more than 5 chats at once.** Any extra chat will find every task either claimed or
blocked on an unmerged dependency, and will correctly stop. That is the ceiling for this repository,
not a throttle we chose.

## 2. What must be sequential

### 2.1 The spine

```
  E01  ──►  E02  ──►  E03  ──►  E08  ──►  E09  ──►  E10
```
Each must be **merged and verified** before the next starts.
`E02` and `E03` are on it for a reason that is not their own value: they are pure refactors whose
entire purpose is to unblock everyone else. `E02` splits the cron out of `index.ts` and then freezes
that file; `E03` lifts settlement and dispatch out of `trips.ts`. Run either in parallel with work that
touches the same Worker and you get two large diffs moving the same code — an unreviewable rebase.

### 2.2 File-lock dependencies — hard

Both tasks own the same path. Violating the order means one chat's merge silently deletes the other's:

| Must run after | Task | Shared file |
|---|---|---|
| `E02` | **E07** | `apps/api/src/cron/invoices.ts` |
| `E02` | **E09** | `apps/api/src/cron/dispatch.ts` |
| `E02` | **E12** | `apps/api/src/lib/health.ts` |
| `E03` | **E08** | `apps/api/src/lib/settlement.ts` |
| `E03` | **E09** | `apps/api/src/lib/dispatch.ts` · `apps/api/src/routes/trips.ts` |

### 2.3 Logical dependencies — different files, but meaningless out of order

| Must run after | Task | Why |
|---|---|---|
| `E01` | **E02** | the deploy path must be safe before the Worker is restructured |
| `E01` | **E15** | environment config changes ship through the fixed deploy path |
| `E01` | **E17** | release signing rides on the fixed deploy scripts |
| `E01` | **E18** | the backup script uses the corrected migration commands |
| `E01` | **E19** | E01 adds the `@cloudflare/vitest-pool-workers` devDependency E19 needs |
| `E02` | **E03** | — |
| `E02` | **E13** | the public `/safety/track/:token` mount must exist before the route is corrected |
| `E03` | **E04** | the launch-shape guards land on the refactored route module |
| `E03` | **E15** | `getRoute`'s new signature must not race the `trips.ts` extraction |
| `E04` | **E07** | the companies vertical must be off before the second generator is declared dead |
| `E06` | **E14** | the payout queue needs the `payout_requests` table and E06's debit primitive |
| `E08` | **E09** | E09 points the accept handler at E08's settlement primitive |
| `E08` | **E19** | there is nothing to test until the money primitive exists |
| `E09` | **E10** | the rider client needs `GET /trips/active` to exist |
| `E12` | **E07** | E07 calls `pingDeadMan()` from the invoice job's success path |
| `E12` | **E08** | E08 calls `logAudit` — `lib/audit.ts` has to exist |
| `E12` | **E09** | E09 calls `pingDeadMan()` from the dispatch job's success path |
| `E13` | **E09** | E09 calls `revokeShareToken()` and `purgeExpiredShareTokens()` |
| `E13` | **E14** | the SOS console needs E13's lifecycle columns and endpoints |
| `E15` | **E09** | E09 flips the booking call site onto E15's `allowFallback` and writes `route_source` |

## 3. What runs in parallel

**Round 1 — start these together, on day one:** `E01` · `E05` · `E06` · `E11` · `E16`

They have no dependencies and no shared files. Two of them decide the launch date and should be
started first regardless of who is free:

- **`E11`** is the largest item in the gate (size L, the whole captain location pipeline). It is on
  nobody's critical path, which makes it easy to defer and expensive to have deferred.
- **`E16`** is governed by counsel and store review, not by engineering effort. Calendar time starts
  the day it starts, so start it before anything is ready for it.

Within every later round, the listed tasks are also fully parallel — that is what §5 proves.

## 4. Gate items that no single PR can close

**9 of the 16 gate items are delivered by more than one task.** The fix and the place it takes
effect live in files owned by different chats, so the item is only true once *every* listed PR has merged
and been verified. **A verifier who closes one of these on the first PR closes it wrong** — that is root
R3 exactly: work declared done at the point of definition rather than effect.

This table was generated from the `gate_items:` field of every brief, and that turned out **not** to be
sufficient. Round 1 finished with three independent chats each reporting a row missing from it: E06 for
item 4, E11 for item 8, E16 for item 12, and E05 correcting the span of items 3 and 10. The generator reads
`gate_items:`, but a split only exists when the *second* half lands in a file the first task does not own —
and that fact lives in prose, not in a field. Rows for **8** and **12** were added by hand on 2026-08-01
after round 1; treat this table as curated-and-verified, not as self-maintaining, and add a row the moment
you find your task is half of one.

| Gate item | Closed by | Unblocked by | Verify only when |
|---|---|---|---|
| **2** — no more bare `wrangler deploy` | `E00` + `E01` | — | both merged |
| **3** — the launch shape is enforced, not just intended | `E04` + `E05` | `E02` | both merged |
| **4** — the payout debit cannot mint money | `E06` + `E14` | — | both merged |
| **6** — settlement pays the price that was agreed | `E08` + `E09` | `E03` | both merged |
| **7** — a rider is never locked out of booking | `E09` + `E10` | `E03` | both merged |
| **8** — the captain stays visible | `E11` + `E20` | — | both merged |
| **10** — the safety features do not lie or leak | `E05` + `E09` + `E13` + `E14` | `E02` | all 4 merged |
| **11** — no price is ever computed off a straight line | `E09` + `E15` | — | both merged |
| **12** — deletion and consent actually reachable | `E16` + `E02` + **human** | — | both merged **and** counsel signed off |

The remaining items have a single closing task and may be verified on their own PR: **1** → `E00` · **5** → `E07` · **9** → `E09` · **13** → `E17` · **14** → `E12` · **15** → `E18` · **16** → `E19`.

Three of the multi-task items are worth calling out because the split is not obvious from the briefs:

- **Item 3** is three-way: `E02` unmounts `/intercity` and `/companies`, `E04` makes the server reject
  them, and `E05` stops the rider client from offering the سفر chip at all. Disabling the client without
  the server guard leaves the endpoint live to anyone with curl.
- **Item 10** is the widest in the gate — `E05` deletes the false "authorities are notified" claim,
  `E13` redacts the share payload and exports revocation, `E09` calls that revocation at trip end, and
  `E14` gives an operator somewhere to see an SOS. Any one of them alone still leaves a safety feature
  that lies.
- **Item 6** and **item 11** are definition/call-site pairs: `E08` and `E15` write the primitive, `E09`
  owns `trips.ts` and is the only task that can point the code at it.
- **Item 8** is a pipeline/consumer pair, found by `E11` mid-run. `E11` fixes the captain end — heartbeat,
  foreground service, paced publishing — and ships `AnimatedVehicleMarker`, but the widget has no caller:
  the rider screens that render the car are `apps/rider/lib/screens/trip/trip_screen.dart` and
  `home_screen.dart`, which were in nobody's `owns`. Better data arriving at an unchanged marker still
  teleports. `E20` owns that wiring. Do not close item 8 on PR #91.
- **Item 12** is three-way and one of the three is not an engineer. `E16` writes the handler, the policy
  and the migration; `E02` mounts `publicUserRoutes` in the frozen `index.ts` — without which the
  store-listing deletion URL returns 401 and the listing is rejected; and a **human** supplies the
  controller identity left as `TODO(legal)`, counsel's review of `docs/legal/`, and the two store URLs.
  Calendar, not effort. `E16` flagged this from inside its own run.

## 5. Proof the partition is safe

Mapping the gate's 16 items onto the "Files to change" lists in the 28 track documents gives
**36 colliding pairs**. Three files cause 42 of them:

| File | Plan items touching it | Gate items colliding on it |
|---|---|---|
| `apps/api/src/index.ts` | 36 | 7 |
| `apps/api/src/routes/trips.ts` | 55 | 6 |
| `apps/api/src/lib/schemas.ts` | 22 | 4 |

The review phase never hit this because it was read-only. The fix is three rules:

1. **Two structural tasks first** (`E02`, `E03`) split the hub files with no behaviour change.
2. **Every task declares an exclusive `owns:` list**, enforced at claim time by PROTOCOL-EXEC §3.
3. **Where two tasks must touch one file, one depends on the other** — never parallel.

Checked mechanically over all 190 task pairs by `validate.py`: **0 unsafe overlaps.**
5 pairs share a file and every one is ordered by a dependency edge (§2.2). No two tasks in
the same round share any path.

## 6. Ordering traps the graph cannot express

Violating these makes the product **worse**, not just late.

- **`E11` must ship interpolation with the cadence change.** Lengthening the publish interval without
  `AnimatedVehicleMarker` makes the marker look worse even though the data is strictly better. T13 and
  T28 state this independently.
- **`E11`'s foreground service and the navigation hand-off ship together.** Hand-off without the service
  encourages captains to leave an app that cannot survive being left.
- **`E13`'s payload redaction lands before the URL fix** — in the same PR. Fixing the two URL bugs first
  would publish the rider's home address to an unauthenticated 7-day token.
- **`E09` before any recurrence work.** Scheduled dispatch is the most reliable way to trigger the
  permanent-`searching` state.
- **`E16` starts on day one regardless of engineering capacity.** Counsel and store review are calendar,
  not effort.
- **Nothing re-enables what §2.1 turned off.** Those are G1‡ — disabled, not fixed.

## 7. Seams closed in this pass

A seam is work a brief requires that lands in a file the brief does not own. The first collision check
compared declared `owns` lists and found none — it was reading the wrong thing. Briefs describe work in
prose ("the two callers", "revoke at trip end", "wire into CI"), and prose does not name paths. Every
row below was invisible to the path-level check:

| Seam | Ruling |
|---|---|
| `E15` said "split the two callers" — they are `trips.ts:331` and `:382`, owned by `E09` | `E15` ships `allowFallback` defaulting to today's behaviour; `E09` flips it. Gate item 11 split. |
| `E15` must persist `route_source`, which needs a migration and a write in `trips.ts` | `E15` owns the migration; `E09` writes the column. `E15` flipped to `migration: yes`. |
| `E12`'s cron dead-man ping would edit `cron/invoices.ts` (`E07`) and `cron/dispatch.ts` (`E09`) | `E12` exports `pingDeadMan()`; the cron owners call it. Added `E07→E12`, `E09→E12`. |
| `E13` must revoke share tokens at trip end and purge on a schedule — both in `E09`'s files | `E13` exports both functions; `E09` wires them. Added `E09→E13`. |
| `E08`'s accept fix targets `trips.ts:829`, owned by `E09` | `E08` fixes the primitive; `E09` moves the call site. Added `E09→E08`. Gate item 6 split. |
| `E11` must move the rate-limit counter into `GeoCell`, owned by nobody | `GeoCell.ts` added to `E11`'s `owns`. It exists on `main` and is bound in `wrangler.toml`. |
| `E19` needs a `package.json` devDependency (`E01`) and a `ci.yml` edit (impossible for any agent) | `E01` pre-adds the dependency; the CI YAML goes to `docs/plan/assets/` for a human. |
| `E18`'s "scheduled export" implied a Worker cron — needing `index.ts` (`E02`, frozen) **and** a `wrangler.toml` trigger (`E15`) | Descoped to a script plus human-installed scheduling YAML. `E18` stays in round 2. |
| `E16`'s public deletion URL needs a mount in the frozen `index.ts` | `E02` mounts it pre-emptively, merged or not. `E16` keeps no dependency and stays in round 1. |
| `E07`'s "exactly one generator" required deleting code in `companies.ts` (`E04`) | `E04`'s vertical shutdown kills that path; `E07`'s acceptance reworded to the joint outcome. |
| `E05`'s "no copy in **either** app" reaches into `apps/captain/` (`E11`) | `E05` scoped to the rider app; the captain copy audit moved into `E11`. |
| `E00` (human) would paste migration state into `docs/DEPLOYMENT.md` (`E01`) | `E00` records it in its `PROJECT.md` block instead. |

**One reported seam was rejected on the evidence.** `E04` narrows the payment-method enum in
`schemas.ts`, and the audit flagged that `trips.ts:468` reads `body.paymentMethod || "cash"` raw — which
would make the narrowing cosmetic and force `E04` into `E09`'s file. Reading `main`: `trips.ts:359` calls
`parseBody(c, createTripSchema)`, so the body is already validated against the schema and `:468` only
reads the validated value. Narrowing `schemas.ts:60` genuinely rejects `wallet` and `card`. No edge added.

Net effect on the schedule: **none.** Four dependency edges were added and the round count stayed at
6 — the new edges run parallel to the existing critical path rather than extending it.

## 8. Full file-ownership map

| Round | Task | Owns |
|---|---|---|
| 0 | **E00** | `.github/workflows/deploy.yml` |
| 1 | **E01** | `apps/api/package.json` · `apps/api/deploy.sh` · `docs/DEPLOYMENT.md` · `package-lock.json` |
| 1 | **E05** | `apps/rider/lib/screens/home/vehicle_selector.dart` · `apps/rider/lib/screens/safety/sos_screen.dart` |
| 1 | **E06** | `apps/api/src/routes/wallet.ts` · `migrations/0020_payout_requests.sql` |
| 1 | **E11** | `apps/captain/lib/services/` · `apps/captain/lib/screens/home/` · `apps/captain/android/app/src/main/AndroidManifest.xml` · `apps/captain/pubspec.yaml` · `apps/captain/pubspec.lock` · `apps/api/src/routes/captain.ts` · `apps/api/src/durable-objects/TripRoom.ts` · `apps/api/src/durable-objects/GeoCell.ts` · `apps/api/src/durable-objects/CaptainInbox.ts` · `packages/flutter_shared/lib/widgets/animated_vehicle_marker.dart` · `packages/flutter_shared/lib/motion/go_motion.dart` |
| 1 | **E16** | `apps/api/src/routes/user.ts` · `migrations/0021_consent_and_deletion.sql` · `docs/legal/` · `apps/rider/lib/screens/profile/settings_screen.dart` · `apps/captain/lib/screens/profile/settings_screen.dart` · `packages/flutter_shared/lib/l10n/app_strings.dart` |
| 2 | **E02** | `apps/api/src/index.ts` · `apps/api/src/cron/` · `apps/api/src/lib/health.ts` |
| 2 | **E17** | `apps/rider/android/app/build.gradle` · `apps/captain/android/app/build.gradle` · `apps/rider/ios/Runner/Info.plist` · `apps/captain/ios/Runner/Info.plist` |
| 2 | **E18** | `scripts/backup-d1.sh` · `docs/RUNBOOK-restore.md` |
| 2 | **E20** | `apps/rider/lib/screens/trip/trip_screen.dart` · `apps/rider/lib/screens/home/home_screen.dart` |
| 3 | **E03** | `apps/api/src/routes/trips.ts` · `apps/api/src/lib/settlement.ts` · `apps/api/src/lib/dispatch.ts` |
| 3 | **E12** | `apps/api/src/middleware/requestId.ts` · `apps/api/src/lib/log.ts` · `apps/api/src/lib/audit.ts` · `apps/api/src/lib/health.ts` |
| 3 | **E13** | `apps/api/src/routes/safety.ts` · `migrations/0022_sos_lifecycle.sql` |
| 4 | **E04** | `apps/api/src/lib/schemas.ts` · `apps/api/src/routes/payments.ts` · `apps/api/src/routes/intercity.ts` · `apps/api/src/routes/companies.ts` |
| 4 | **E08** | `apps/api/src/lib/settlement.ts` · `apps/api/src/lib/money.ts` |
| 4 | **E14** | `apps/api/src/routes/admin.ts` · `apps/admin/` |
| 4 | **E15** | `apps/api/src/lib/routing.ts` · `apps/api/src/lib/geocode.ts` · `apps/api/src/routes/geocode.ts` · `apps/api/wrangler.toml` · `migrations/0023_route_source.sql` |
| 5 | **E07** | `apps/api/src/cron/invoices.ts` |
| 5 | **E09** | `apps/api/src/routes/trips.ts` · `apps/api/src/lib/dispatch.ts` · `apps/api/src/cron/dispatch.ts` · `apps/api/src/lib/cleanup.ts` · `apps/api/src/durable-objects/OfferScheduler.ts` |
| 5 | **E19** | `apps/api/test/` · `apps/api/vitest.config.ts` |
| 6 | **E10** | `apps/rider/lib/services/app_state.dart` · `apps/rider/lib/screens/home/fare_estimate_sheet.dart` · `apps/rider/lib/main.dart` |

Anything not listed here is owned by nobody and **must not be edited** during this wave. If your task
needs it, you have found a seam the same way the ones in §7 were found: say so on the PR and stop.
`apps/api/src/durable-objects/OfferScheduler.ts` and `GeoCell.ts` were unowned until this pass — both
are live and bound, and an unowned live file is a collision waiting for two chats to notice it.

**Still unowned after round 1, deliberately.** Three files were reached for by a round-1 task and left
alone correctly. They are recorded here so the next chat does not rediscover them as novel:

| File | Wanted by | Ruling |
|---|---|---|
| `packages/flutter_shared/lib/l10n/app_strings.dart` | `E11` (SOS copy at `:2588`/`:3637`/`:4537`/`:5583`) and `E16` (consent + deletion strings) | It **is** in `E16`'s brief `owns:` — but `E16`'s claim file omitted it, and `E16` shipped a per-screen `_t(context, ar, en)` rather than editing it. So the copy fix is still outstanding and the file is still effectively unowned. Two independent tasks blocking on one file is an ownership gap, not two workarounds. Needs a Wave-2 task; a 5,664-line three-place edit is not a spare-capacity job. |
| `apps/api/src/middleware/auth.ts` | `E16` (a stateless JWT stays valid for its remaining lifetime after account deletion) | Bounded and documented in `docs/legal/account-deletion.md` §4. One check against `users.deleted_at`, which `0021` creates. Not gate-blocking — the session cannot be *extended*, only outlived. Wave 2. |
| `apps/api/tsconfig.json` | `E19` (`include: ["src/**/*"]` does not cover `apps/api/test/`) | Reported by `E01`. `E19` will hit this the moment it starts. Assign it to `E19`'s `owns:` before round 5, or `E19` stops at the same seam. |

## 9. Not in this wave

**Flutter tests are out of scope, deliberately.** `apps/rider/test/` and `apps/captain/test/` hold only
the default `widget_test.dart` scaffold, are owned by no task, and `ci.yml` runs `flutter analyze` but
**never `flutter test`** — so a Dart test added during this wave would execute nowhere. Gate item 16 is
scoped to the API money paths (`E19`) for that reason. Wiring `flutter test` into CI needs an edit to
`.github/workflows/ci.yml`, which no agent can make; it belongs with the other human workflow steps in
`E00`. Chats whose brief names no tests should say so in the PR and stop — several briefs previously
carried a blanket "tests are not optional" line that sent at least one chat looking for a harness that
does not exist. That line is now conditional.

Wave 2 (98 G2 findings) and Wave 3 (316 G3) are scoped in §6.3 of the plan. The dead-code sweep (root
R3), the accessibility block, T27's shared component layer and the cost programme are all Wave 2 or
later, deliberately. Do not pull them forward — §8 of the plan explains what each is waiting on.

## 10. Changelog

The board is a shared file. When it changes underneath you, this is where to look.

### 2026-08-01 — post-round-1 reconciliation (`chat-20260801-1910-a4e5`, at the board owner's instruction)

Round 1 closed with five tasks `done`, five PRs green, and nothing merged. Every later task correctly
reported *"no unblocked task"*. That stall exposed four defects in the board itself, all fixed here:

1. **Nobody owned `merge`.** §8 of PROTOCOL-EXEC forbids every chat from merging; §7 assumes a merge
   happens between author and verifier; §1 of this file listed one human task whose scope did not
   include it. Fixed: `E00` gains a standing merge duty and the round boundary is now explicit.
2. **§4 was three rows short**, and its claim to be generated-not-curated was wrong. Items **8** and
   **12** added; the header now says what the generator can and cannot see.
3. **Two `owns:` entries were placeholders.** `migrations/@NEXT_sos_lifecycle.sql` (E13) and
   `@NEXT_route_source.sql` (E15) cannot be intersected against another claim, so the §3 file lock was
   silently weaker for the two tasks that touch the schema. Numbers **0022** and **0023** are now
   reserved and the filenames are concrete.
4. **Gate item 8 had no owner for its second half.** `E20` added — `E11` ships the marker, `E20` wires
   it into the two rider screens that render the car.

No product code was touched, no PR merged, no claim altered.
