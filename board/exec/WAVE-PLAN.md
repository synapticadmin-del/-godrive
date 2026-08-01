# WAVE-PLAN — execution decomposition and the proof it does not collide

Derived from `docs/plan/00-EXECUTION-PLAN.md` §2.2 (the 16-item launch gate) and §6 (waves).
This file exists because the gate is a good **decision list** and a bad **work breakdown**.

## Why the gate could not be handed out as-is

Mapping the gate's 16 items to the "Files to change" lists in the 28 track documents gives
**36 colliding pairs**. Three files cause 42 of them:

| File | Plan items touching it | Gate items colliding on it |
|---|---|---|
| `apps/api/src/index.ts` | 36 | 7 (items 3, 5, 7, 9, 10, 12, 14) |
| `apps/api/src/routes/trips.ts` | 55 | 6 (items 3, 6, 7, 9, 11, 14) |
| `apps/api/src/lib/schemas.ts` | 22 | 4 |

Handing gate item 6 to one chat and item 7 to another means both edit `trips.ts`. The review phase
never hit this because it was read-only.

## The fix

1. **Two structural tasks first (E02, E03)** that split the hub files with no behaviour change.
   After E02, `index.ts` is frozen. After E03, the money and dispatch logic live in files a single
   task can own.
2. **Every task declares an exclusive `owns:` list**, enforced at claim time by PROTOCOL-EXEC §3.
3. **Where two tasks must touch the same file, one depends on the other** — never parallel.

Validated mechanically: **0 unsafe overlaps.** Five task pairs share a file and all five are ordered
by a dependency edge:

| Pair | Shared file | Ordered by |
|---|---|---|
| E02 → E07 | `apps/api/src/cron/invoices.ts` | E07 depends on E02 |
| E02 → E09 | `apps/api/src/cron/dispatch.ts` | E09 depends on E02 |
| E02 → E12 | `apps/api/src/lib/health.ts` | E12 depends on E02 |
| E03 → E08 | `apps/api/src/lib/settlement.ts` | E08 depends on E03 |
| E03 → E09 | `apps/api/src/routes/trips.ts`, `lib/dispatch.ts` | E09 depends on E03 |

## Wave 0 — spine (mostly sequential)

E01 → E02 → E03 is a chain; each must be **merged and verified** before the next starts. E05 and E06
are client/wallet-only and can run alongside from the start.

| Task | Title | Gate | Depends on |
|---|---|---|---|
| **E01** | Deploy safety net: no more bare wrangler deploy | 2 | — |
| **E02** | index.ts structural pass — split the cron, fix the mounts, then FREEZE | 3,5,10,14 (enabler) | E01 |
| **E03** | trips.ts structural pass — extract settlement and dispatch (pure refactor) | 6,7,9 (enabler) | E02 |
| **E04** | Enforce the launch shape server-side: cash-only, verticals off | 3 | E03 |
| **E05** | Client truth fixes: disable سفر chip, SOS dark mode, delete the false SOS claim | 3,10 | — |
| **E06** | Freeze the payout debit | 4 | — |
| **E07** | Disable the B2B invoice cron and collapse to one generator | 5 | E02, E04 |

## Wave 1 — the gate (parallel)

Eight tasks are startable the moment Wave 0's spine has merged: **E09, E11, E12, E13, E15, E16, E17,
E18**. That is the real parallelism ceiling for this codebase — more chats than that will queue on
the file lock rather than go faster.

| Task | Title | Gate | Depends on |
|---|---|---|---|
| **E08** | Settlement correctness: accept settles offered_price, cash floor, one money primitive | 6,+R1 | E03, E12 |
| **E09** | Trip lifecycle: expiry sweeper, active-trip recovery, scheduled dispatch | 7,9 | E03, E02 |
| **E10** | Rider client: active-trip recovery and the discarded 409 tripId | 7 | E09 |
| **E11** | Captain location pipeline: heartbeat, foreground service, cadence, interpolation | 8 | — |
| **E12** | Observability spine: correlation id, structured log, real /health, cron dead-man | 14 | E02 |
| **E13** | Safety API: redact the share payload, fix the public route, SOS lifecycle | 10 | E02 |
| **E14** | Operator console: SOS queue and payout queue | 10,4 | E06, E13 |
| **E15** | Own the routing: self-host OSRM, fail closed, stop pricing off a straight line | 11 | E01, E03 |
| **E16** | Privacy: policy, server-side consent, account deletion and export | 12 | — |
| **E17** | Android release: targetSdk 35, fail-closed signing, CI-built artefact | 13 | E01 |
| **E18** | One rehearsed restore: D1 export to R2 plus a runbook someone has run | 15 | E01 |
| **E19** | Tests on the money paths that stay live | 16 | E01, E08 |

## Ordering traps that the dependency graph does not express

These come from the track authors and violating them makes the product **worse**, not just late.

- **E11 must ship interpolation with the cadence change.** Lengthening the publish interval without
  `AnimatedVehicleMarker` makes the marker look worse even though the data is strictly better.
  T13 and T28 both state this independently.
- **E11's foreground service and the navigation hand-off ship together.** Hand-off without the
  service encourages captains to leave an app that cannot survive being left.
- **E09 before any recurrence work.** Scheduled dispatch is the most reliable way to trigger the
  permanent-`searching` state.
- **E13's payload redaction before the URL fix.** Fixing the two URL bugs first would publish the
  rider's home address to an unauthenticated 7-day token.
- **E12 before E08's audit call** — E08 depends on `lib/audit.ts` existing.
- **E16 starts on day one regardless of engineering capacity.** Counsel and store review are calendar,
  not effort.

## Full file-ownership map

| Task | Owns |
|---|---|
| E01 | `apps/api/package.json` · `apps/api/deploy.sh` · `docs/DEPLOYMENT.md` |
| E02 | `apps/api/src/index.ts` · `apps/api/src/cron/` · `apps/api/src/lib/health.ts` |
| E03 | `apps/api/src/routes/trips.ts` · `apps/api/src/lib/settlement.ts` · `apps/api/src/lib/dispatch.ts` |
| E04 | `apps/api/src/lib/schemas.ts` · `apps/api/src/routes/payments.ts` · `apps/api/src/routes/intercity.ts` · `apps/api/src/routes/companies.ts` |
| E05 | `apps/rider/lib/screens/home/vehicle_selector.dart` · `apps/rider/lib/screens/safety/sos_screen.dart` |
| E06 | `apps/api/src/routes/wallet.ts` · `migrations/@NEXT_payout_requests.sql` |
| E07 | `apps/api/src/cron/invoices.ts` |
| E08 | `apps/api/src/lib/settlement.ts` · `apps/api/src/lib/money.ts` |
| E09 | `apps/api/src/routes/trips.ts` · `apps/api/src/lib/dispatch.ts` · `apps/api/src/cron/dispatch.ts` · `apps/api/src/lib/cleanup.ts` |
| E10 | `apps/rider/lib/services/app_state.dart` · `apps/rider/lib/screens/home/fare_estimate_sheet.dart` · `apps/rider/lib/main.dart` |
| E11 | `apps/captain/lib/services/` · `apps/captain/lib/screens/home/` · `apps/captain/android/app/src/main/AndroidManifest.xml` · `apps/api/src/routes/captain.ts` · `apps/api/src/durable-objects/TripRoom.ts` · `apps/api/src/durable-objects/CaptainInbox.ts` · `packages/flutter_shared/lib/widgets/animated_vehicle_marker.dart` · `packages/flutter_shared/lib/motion/go_motion.dart` |
| E12 | `apps/api/src/middleware/requestId.ts` · `apps/api/src/lib/log.ts` · `apps/api/src/lib/audit.ts` · `apps/api/src/lib/health.ts` |
| E13 | `apps/api/src/routes/safety.ts` · `migrations/@NEXT_sos_lifecycle.sql` |
| E14 | `apps/api/src/routes/admin.ts` · `apps/admin/` |
| E15 | `apps/api/src/lib/routing.ts` · `apps/api/src/lib/geocode.ts` · `apps/api/src/routes/geocode.ts` · `apps/api/wrangler.toml` |
| E16 | `apps/api/src/routes/user.ts` · `migrations/@NEXT_consent_and_deletion.sql` · `docs/legal/` · `apps/rider/lib/screens/profile/settings_screen.dart` · `apps/captain/lib/screens/profile/settings_screen.dart` |
| E17 | `apps/rider/android/app/build.gradle` · `apps/captain/android/app/build.gradle` · `apps/rider/ios/Runner/Info.plist` · `apps/captain/ios/Runner/Info.plist` |
| E18 | `scripts/backup-d1.sh` · `docs/RUNBOOK-restore.md` |
| E19 | `apps/api/test/` · `apps/api/vitest.config.ts` |

Anything not listed here is owned by nobody and must not be edited during this wave.

## Not in this wave

Wave 2 (98 G2 findings) and Wave 3 (316 G3) are scoped in §6.3 of the plan. The dead-code sweep
(root R3), the accessibility block, T27's shared component layer and the cost programme are all Wave
2 or later, deliberately. Do not pull them forward — §8 of the plan explains what each is waiting on.
