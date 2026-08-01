# 22 — Observability, Operations & Incident Response

> Track: D — Engineering excellence & production readiness · Reviewer: `chat-20260801-1630-3996` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `913718bafb1c8a10f6d8c6a387abca952d72289f`
> Every `path:line` in this document was read at that commit. Where a claim could not be verified it is marked `needs-check` rather than assumed safe.

---

## 1. Scope

This document covers how Synaptic Go is **observed and operated**: what is logged, what is measured, what alerts, how an incident is diagnosed, and what the on-call practice should be. It answers one question first and everything else second:

> If the platform breaks at 8 a.m. on a Sunday, how would anyone know?

The honest answer today is: **a rider tells you.** There is no alerting, no metrics, no crash reporting, and no correlation id. The one piece of observability infrastructure that *is* switched on — Workers Logs — emits 22 unstructured strings across the entire API, and none of them come from the payment, auth, wallet, admin, or captain routes.

**In scope**

- Logging: format, destination, correlation, and the request-tracing scheme.
- Metrics: the catalogue that matters for a ride-hailing product, and how to emit it on Cloudflare.
- Alerting: the alert set, thresholds calibrated for launch volume, and the delivery path.
- Client-side error reporting for both Flutter apps and the admin console, with the privacy constraints that apply to an Egyptian product handling location and payment data.
- Cloudflare-native tooling: Workers Logs, Analytics Engine, Tail Workers, Logpush — what is configured, what should be, what it costs.
- Health checks, cron observability, and queue/DLQ health.
- Five incident runbooks and the on-call practice around them.
- SLOs and an error-budget policy sized for a two-person team.

**Explicitly not in scope** (owned elsewhere; findings that touch these are in §9)

| Area | Owner |
|---|---|
| Auth design, JWT handling, session security | T02 |
| The `audit_log` table's schema, retention and immutability as a *security* control | T02, T08 |
| Dispatch algorithm correctness and matching quality | the dispatch track |
| Realtime/Durable Object architecture and WebSocket protocol design | T07 |
| Payment correctness, idempotency and reconciliation as a *money* problem | the payments track |
| Rider/captain app convergence and the duplicated-screen problem | T27 |
| CI/CD as a delivery pipeline (this document covers only its observability and rollback properties) | the CI track |

Where this document names a defect that belongs to another track, it says so and hands it over rather than proposing the fix.

---

## 2. What I actually read

48 files pulled at the pinned commit. Read in full unless noted.

**Worker core**

| File | Note |
|---|---|
| `apps/api/src/index.ts` | Read in full, 372 lines. Entrypoint, CORS, global rate limit, `/` and `/health`, route mounting, both WebSocket upgrade paths, `notFound`/`onError`, the queue consumer, and the `scheduled` cron handler. The single most important file for this track. |
| `apps/api/wrangler.toml` | Read in full, 180 lines. Bindings, queues, crons, three environments, and the three `[observability]` blocks. |
| `apps/api/deploy.sh` | Read in full, 51 lines. The manual deploy path. |
| `apps/api/package.json` | Read. Wrangler `^4.22.0`. |
| `apps/api/src/lib/audit.ts` | Read in full, 37 lines. The whole audit mechanism. |
| `apps/api/src/lib/cleanup.ts` | Read in full, 75 lines. The daily purge and its audit row. |
| `apps/api/src/lib/utils.ts` | Read. Looking for a logging/response seam; `jsonError` is the candidate. |
| `apps/api/src/middleware/rateLimit.ts` | Read in full, 90 lines. Includes `parseBody`. |
| `apps/api/src/middleware/auth.ts` | Read. |
| `apps/api/src/lib/notifications.ts`, `paymob.ts`, `jwt.ts`, `types.ts` | Read for error paths and side-effect logging. |

**Routes** — all 14 read or grepped systematically for `console.*`, `logAudit(`, and error handling: `admin.ts`, `auth.ts`, `captain.ts`, `companies.ts`, `devices.ts`, `geocode.ts`, `intercity.ts`, `payments.ts`, `promo.ts`, `safety.ts`, `search.ts`, `trips.ts`, `user.ts`, `wallet.ts`. `payments.ts` and `trips.ts` were read closely; `admin.ts` (36 KB) and `captain.ts` (25 KB) were grepped for instrumentation and audit coverage rather than read line by line — **skimmed, and I am saying so.**

**Durable Objects** — `TripRoom.ts`, `GeoCell.ts`, `CaptainInbox.ts`, `OfferScheduler.ts`. Read for error paths, alarm handling and hibernation behaviour.

**CI / deploy**

| File | Note |
|---|---|
| `.github/workflows/ci.yml` | Read, 8.8 KB. Three jobs, `continue-on-error` steps, and the `Result` aggregators. |
| `docs/ci/deploy-api.yml` | Read, 5.9 KB. The deploy pipeline that **is not installed** — it sits in `docs/`, not `.github/workflows/`. |
| `docs/DEPLOYMENT.md`, `docs/COST.md`, `docs/ARCHITECTURE.md`, `docs/CHECKLIST.md`, `docs/IMPROVEMENTS.md` | Read. |

**Clients**

| File | Note |
|---|---|
| `packages/flutter_shared/lib/services/api_client.dart` | Read in full — 36 lines total. No timeout, no retry, no reporting. |
| `packages/flutter_shared/lib/services/fcm_service.dart` | Read. |
| `apps/rider/lib/main.dart`, `apps/captain/lib/main.dart` | Read in full. Checked for `runZonedGuarded` / `FlutterError.onError`. |
| `apps/rider/lib/services/app_state.dart` (25 KB), `apps/captain/lib/services/captain_state.dart` (47 KB) | Grepped exhaustively for `catch`, `SnackBar`, `ScaffoldMessenger`, `print`; read the surrounding context of every catch block found. Not read line by line. |
| `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml` | Read in full — the dependency inventory is the crash-reporting answer. |
| `apps/admin/src/components/ui/ErrorBoundary.tsx`, `apps/admin/src/lib/api.ts`, `apps/admin/src/main.tsx` | Read in full. |

**Repository metadata** — `migrations/` directory listing at the pinned commit: 19 files, `0001_init.sql` through `0019_trips_captain_status_index.sql`.

---

## 3. How it works today

### 3.1 Logging

There are **22** `console.*` calls in the entire API. That is the complete logging surface. Here it is in full, because the whole picture fits in one table and the shape of it is the finding:

| File | Lines | Count |
|---|---|---|
| `apps/api/src/index.ts` | 234, 260, 277, 280, 330, 369 | 6 |
| `apps/api/src/lib/cleanup.ts` | 38, 40, 54, 56, 71 | 5 |
| `apps/api/src/routes/trips.ts` | 68, 583, 762, 790, 795, 823, 1357 | 7 |
| `apps/api/src/routes/safety.ts` | 195, 288 | 2 |
| `apps/api/src/lib/audit.ts` | 35 | 1 |
| `apps/api/src/durable-objects/OfferScheduler.ts` | 118 | 1 |
| **`payments.ts`, `auth.ts`, `admin.ts`, `wallet.ts`, `captain.ts`, `user.ts`, `companies.ts`, `intercity.ts`, `promo.ts`, `devices.ts`, `geocode.ts`, `search.ts`** | — | **0** |

Every one is an unstructured string with interpolated values — `console.error("offer fcm failed", cap.userId, e)` (`trips.ts:583`). None carries a request id, a timestamp field, a severity level, or any structure a log query could filter on.

The global error handler is `apps/api/src/index.ts:233-236`:

```ts
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: err.message || "Internal error", code: "INTERNAL" }, 500);
});
```

It logs the raw error object with no route, method, user, or trip context — and it returns `err.message` to the client, which leaks internal error text to callers (that half belongs to T02; noted in §9).

**Where the logs go.** They are captured. `[observability] enabled = true` is set in all three environments — `wrangler.toml:93-94` (default), `151-152` (prod), `179-180` (staging). This is genuinely the one thing already working on this axis: Workers Logs is on, and every `console.*` above lands in the Cloudflare dashboard with 7-day retention on the Workers Paid plan. What is *absent* is everything that would make those logs useful: `logpush` is not set, `[[tail_consumers]]` is not present, and `[[analytics_engine_datasets]]` is not present. All three confirmed absent from all three environments.

**Can you correlate a rider's complaint to the request that failed?** No. There is no request id generated anywhere in the codebase, so there is nothing to correlate on. The practical procedure today is: full-text search 7 days of unstructured logs for a phone number or trip id that mostly is not in them.

### 3.2 Request tracing

There is no correlation id. Not in the Worker, not in the Flutter client, not in the Durable Objects, not in the admin console.

`packages/flutter_shared/lib/services/api_client.dart` is 36 lines long and sends exactly two headers (`api_client.dart:10-13`):

```dart
Map<String, String> get _headers => {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
```

No trace header, no client version, no device id. When a captain reports "the app froze during a trip", there is no identifier that ties their session to a Worker invocation, to a `TripRoom` Durable Object, or to a D1 query. A distributed trip spans the Flutter client, the Worker, `TripRoom`, `GeoCell`, `CaptainInbox`, `OfferScheduler`, D1, KV and the notification queue — and nothing joins them.

### 3.3 Metrics

None. No `[[analytics_engine_datasets]]` binding, no `writeDataPoint` call anywhere, no counters, no histograms. Cloudflare's built-in per-Worker dashboards give request count, error rate, CPU time and subrequest count for the Worker as a whole — that is the entire quantitative picture. There is no way to answer:

- How many trips were created in the last hour?
- What fraction of trips found a captain?
- What is p95 time-to-match?
- What is the payment success rate?
- How many WebSockets are connected right now?

Every one of these has to be reconstructed by hand from D1 with an ad-hoc query, after someone thinks to ask.

### 3.4 Audit logging

`apps/api/src/lib/audit.ts` is the whole mechanism — 37 lines. It writes one row to `audit_log` (singular; `audit.ts:18`) and it ends like this (`audit.ts:33-36`):

```ts
} catch (e) {
  // Never break the main request because of audit failures.
  console.error("audit log failed", e);
}
```

The comment states the intent correctly — an audit write must not fail a rider's trip. The consequence is that audit loss is invisible: a D1 problem silently stops the audit trail while every request keeps returning 200.

Coverage is the larger problem. Call counts per route file, counting call sites only:

| Route | `logAudit` calls |
|---|---|
| `admin.ts` | 9 |
| `auth.ts` | 3 |
| `payments.ts` | 3 |
| `companies.ts` | 2 |
| `intercity.ts` | 2 |
| `promo.ts` | 2 |
| `safety.ts` | 1 |
| `wallet.ts` | 1 |
| **`trips.ts`** | **0** |
| **`captain.ts`** | **0** |
| **`user.ts`, `devices.ts`, `geocode.ts`, `search.ts`** | **0** |

`trips.ts` is 1371 lines. It owns trip creation, offer dispatch, acceptance, cancellation, completion and fare finalisation — the entire lifecycle and the moment money is settled. It **imports** `logAudit` at `trips.ts:20` and never calls it. The import is the tell: someone intended to instrument this file and did not.

### 3.5 Health checks

`apps/api/src/index.ts:99-106`:

```ts
app.get("/health", (c) =>
  c.json({
    ok: true,
    service: "synaptic-go-api",
    version: c.env.APP_VERSION ?? "0.3.0",
    time: new Date().toISOString(),
  }),
);
```

It returns a static literal. It does not touch D1, KV, R2 or any Durable Object. It returns `ok: true` when the database is unreachable, when KV is failing, and when every trip in the system is stuck. It proves exactly one thing: a Worker isolate started.

This matters more than it looks, because `/health` is also the **only** gate in the deploy smoke test (`docs/ci/deploy-api.yml`). A deploy that breaks every database write ships green.

Nothing monitors it externally. No uptime probe, no Cloudflare health check, no third-party monitor is configured in any file read.

### 3.6 Cron observability

Two crons are configured (`wrangler.toml:62-65`, repeated for prod at `140`):

```toml
crons = [
  "*/1 * * * *",  # every minute: dispatch due scheduled trips
  "0 3 1 * *",    # 1st of month 03:00 UTC: generate company invoices
]
```

Both land in one handler, and the handler discards which cron fired (`index.ts:267`):

```ts
async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
```

The underscore prefix is the author telling us `event` is deliberately unused. The consequence is that the monthly invoice branch is gated on a date check inside the handler instead — `if (day === 1)` at `index.ts:336` — so on the first of every month that branch is evaluated 1,440 times and the `0 3 1 * *` trigger is redundant with the every-minute one.

The handler has three independent `try`/`catch` blocks — cleanup (`272-281`), scheduled dispatch (`284-331`), monthly invoices (`334-370`) — and each one ends by swallowing into `console.error`. From Cloudflare's point of view the invocation always succeeds. **Cloudflare does not alert on cron failure by default, and this handler cannot fail.** If the dispatch query throws every minute for a week, the cron dashboard shows 10,080 successful invocations and every pre-booked rider is silently stranded.

### 3.7 Queue and DLQ

The notification queue is configured with a dead-letter queue (`wrangler.toml:50-55`):

```toml
[[queues.consumers]]
queue = "synaptic-go-notifications"
max_batch_size = 100
max_batch_timeout = 5
max_retries = 3
dead_letter_queue = "synaptic-go-notifications-dlq"
```

The consumer retries on any error (`index.ts:259-262`):

```ts
} catch (e) {
  console.error("notification queue error", e);
  msg.retry();
}
```

After three retries a message lands in `synaptic-go-notifications-dlq`. **There is no `[[queues.consumers]]` block for the DLQ anywhere in `wrangler.toml`** — confirmed absent. Nothing drains it, nothing counts it, nothing alerts on it. A customer whose trip-offer or payment-confirmation notification fails three times has their message parked in a queue that no human or process is watching.

### 3.8 Client-side error reporting

**Neither Flutter app has any crash reporting.** `apps/rider/pubspec.yaml` and `apps/captain/pubspec.yaml` were read in full: `firebase_core` and `firebase_messaging` are present for push; `firebase_crashlytics`, `sentry_flutter`, `bugsnag`, Datadog, Rollbar and Instabug are all absent from both.

Neither `main.dart` installs an error hook. `apps/rider/lib/main.dart:18-31` and `apps/captain/lib/main.dart:18-37` both call `runApp` directly, with no `runZonedGuarded`, no `FlutterError.onError`, and no `PlatformDispatcher.instance.onError`. An unhandled Dart exception crashes the app and the event never leaves the device.

Inside the state classes, failures are swallowed rather than surfaced. Rider `app_state.dart` has silent catches at `102`, `148`, `211`, `283` and `527`; captain `captain_state.dart` has them at `203`, `238`, `270`, `682`, `691`, `718`, `783` and `1114`, plus a bare `onError: (_) {}` on the GPS stream at `655`. Neither file contains a single `SnackBar` or `ScaffoldMessenger` call — user-facing error text depends entirely on each screen reading an `error` string field, which is set in one code path in the rider app (`app_state.dart:379`) and two in the captain app (`captain_state.dart:603`, `972`).

`fcm_service.dart` prints its init failure only when `kDebugMode` is true (`fcm_service.dart:71-73`), and its background handler body is wrapped in `try { … } catch (_) {}` (`fcm_service.dart:109-115`). In a release build, FCM initialisation can fail completely and silently.

The admin console has an `ErrorBoundary` (`apps/admin/src/components/ui/ErrorBoundary.tsx`) wired at the app root. Its `componentDidCatch` calls `console.error` and nothing else — the file's own comment at line 38 says it plainly: *"No error-reporting service is wired up yet, so the console is the only place this detail survives."* `apps/admin/src/main.tsx` installs no `window.onerror` and no `unhandledrejection` listener.

### 3.9 Deployment and rollback

Two deploy paths exist and neither is safe.

`apps/api/deploy.sh` is the manual path, and it has three defects:

1. It applies exactly one hardcoded migration — `MIGRATION="$SCRIPT_DIR/../../migrations/0009_captain_city.sql"` (`deploy.sh:30`) — while the repository contains 19. It is a script written for one specific deploy in the past and never generalised.
2. `wrangler d1 execute "$DB_NAME" --file="$MIGRATION"` (`deploy.sh:40`) has no `--remote` flag. Wrangler defaults to the local D1 instance, so this step does not touch production at all.
3. `wrangler deploy` (`deploy.sh:47`) has no `--env prod`. `wrangler.toml:77-85` documents in detail why that is dangerous: the top-level block shares the worker name and the D1 binding with `[env.prod]`, so a bare deploy publishes the top-level `[vars]` straight over production.

The automated path, `docs/ci/deploy-api.yml`, is better — it runs typecheck and test gates, applies migrations with `wrangler d1 migrations apply --remote --env prod`, deploys with `--env prod`, then smoke-tests. **It is not installed.** It lives under `docs/`, not `.github/workflows/`, so it has never run. Every production deploy today is a manual `wrangler` invocation from one developer's laptop.

`.github/workflows/ci.yml` *is* installed and does run, but it is explicit about its own limits (`ci.yml:6-9`):

```
# IMPORTANT: this workflow makes failures VISIBLE, it does not make them
# BLOCKING. To actually stop a broken merge, all three jobs below must be added
# as required status checks in Settings > Branches > branch protection rule for
# `main`. Until that is done a red run can still be merged past.
```

The individual steps are `continue-on-error: true`, but each of the three jobs ends with a `Result` step that re-aggregates the outcomes and exits 1 (`ci.yml:76-98` for the node job, `169-190` for flutter, `225-244` for checks). So the jobs genuinely do go red — the workflow is correctly built. The gap is purely the missing branch-protection rule.

### 3.10 Environments

Production and default share a worker name and a D1 database id (`wrangler.toml:1`/`9-10` vs `100`/`108-109`) — the hazard described above.

Staging is a stub. `[env.staging]` (`wrangler.toml:157-180`) declares a D1 database whose id is the literal string `staging-d1-database-id-placeholder` (`wrangler.toml:167`), and it declares **no** KV namespace, **no** R2 bucket, **no** Durable Object bindings and **no** queues. A Worker deployed to staging would fail on the first session lookup. There is nowhere to rehearse an incident or test a migration.
---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-22-01 | S1 | Nothing alerts. No monitor, no notification rule, no external probe exists in any file in the repository. | absence across `wrangler.toml`, `.github/workflows/ci.yml`, `docs/DEPLOYMENT.md` | A Sunday-morning outage is discovered by a rider, not by the team. Mean time to detection is unbounded. | confirmed |
| F-22-02 | S1 | `/health` is a static literal that touches no binding, and it is the only gate in the deploy smoke test. | `apps/api/src/index.ts:99-106`; `docs/ci/deploy-api.yml` smoke step | A deploy that breaks every D1 write passes the smoke test and ships green. An uptime monitor pointed here would report 100% during a total database outage. | confirmed |
| F-22-03 | S1 | Cron failure is structurally undetectable: one handler serves both crons, ignores `event.cron`, and swallows every error into `console.error`. | `apps/api/src/index.ts:267`, `279-281`, `329-331`, `368-370` | The every-minute dispatch cron can fail continuously while Cloudflare records 100% successful invocations. Pre-booked riders are silently never dispatched. | confirmed |
| F-22-04 | S1 | No correlation id anywhere in the stack — client, Worker, or Durable Objects. | `packages/flutter_shared/lib/services/api_client.dart:10-13`; no id generation found in `apps/api/src/**` | A rider complaint cannot be tied to a request, a trip cannot be traced across the Worker and four DOs, and debugging a distributed trip is guesswork. | confirmed |
| F-22-05 | S1 | The trip lifecycle and fare settlement produce **zero** audit rows. `trips.ts` imports `logAudit` and never calls it. | `apps/api/src/routes/trips.ts:20` (import); 0 call sites across 1371 lines; `captain.ts` 0 calls | Trip state transitions, cancellations and fare finalisation leave no trail. A fare dispute or a captain-fraud investigation has nothing to read. | confirmed |
| F-22-06 | S2 | The rate limiter fails **open** on any KV error, silently. | `apps/api/src/middleware/rateLimit.ts:31-34` | A KV degradation removes all IP rate limiting platform-wide with no signal. The security control disappears exactly when the platform is already unhealthy. | confirmed |
| F-22-07 | S2 | `logAudit` swallows every write failure. | `apps/api/src/lib/audit.ts:33-36` | Audit gaps are invisible. Combined with F-22-05, the audit trail is both incomplete by design and silently lossy in practice. | confirmed |
| F-22-08 | S2 | All 22 log statements in the API are unstructured strings, and the five highest-value route files emit none at all. | census, §3.1; zero in `payments.ts`, `auth.ts`, `admin.ts`, `wallet.ts`, `captain.ts` | Workers Logs is enabled and capturing — but the payment, auth and admin paths write nothing to it. Log search cannot filter by trip, user, or severity. | confirmed |
| F-22-09 | S2 | The notification DLQ has no consumer. | `wrangler.toml:50-55` declares `dead_letter_queue`; no `[[queues.consumers]]` for `synaptic-go-notifications-dlq` anywhere in the file | Messages that fail three retries are parked permanently. A rider whose trip-offer or payment-confirmation notification lands there never receives it, and nobody knows. | confirmed |
| F-22-10 | S2 | No crash reporting in either Flutter app or the admin console; no error hooks installed. | `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml` (no Crashlytics/Sentry); `apps/rider/lib/main.dart:18-31`, `apps/captain/lib/main.dart:18-37` (no `runZonedGuarded`/`FlutterError.onError`); `apps/admin/src/components/ui/ErrorBoundary.tsx:38` | Mobile crashes are completely invisible. The apps are where the users are, and it is the one tier with zero telemetry. | confirmed |
| F-22-11 | S2 | `deploy.sh` applies one hardcoded migration, runs D1 against the **local** database, and deploys **without** `--env prod`. | `deploy.sh:30` (migration 0009 of 19), `deploy.sh:40` (no `--remote`), `deploy.sh:47` (no `--env prod`); hazard documented at `wrangler.toml:77-85` | Running the repo's own deploy script skips 18 migrations, silently no-ops the migration step against production, and risks publishing dev vars over prod. | confirmed |
| F-22-12 | S2 | The automated deploy pipeline is not installed. | file exists at `docs/ci/deploy-api.yml`, not `.github/workflows/` | Every production deploy is manual and unaudited. There is no deploy log, no gate, and no record of who shipped what. | confirmed |
| F-22-13 | S3 | CI reports failures but does not block merges. | `.github/workflows/ci.yml:6-9` (states this in-file); `Result` aggregators at `76-98`, `169-190`, `225-244` exit 1 | The workflow is correctly built — jobs do go red. Only the branch-protection rule is missing, which makes this a settings fix, not an engineering one. | confirmed |
| F-22-14 | S3 | Staging is non-functional: placeholder D1 id and no KV, R2, DO or queue bindings. | `wrangler.toml:157-180`, id literal at `167` | There is nowhere to rehearse a migration, test a runbook, or reproduce an incident. Every change is tested in production. | confirmed |
| F-22-15 | S3 | No metrics infrastructure: no Analytics Engine dataset, no Tail Worker, no Logpush. | absence of `[[analytics_engine_datasets]]`, `[[tail_consumers]]`, `logpush` in all three environments of `wrangler.toml` | No business or technical metric can be queried, charted or alerted on. | confirmed |
| F-22-16 | S3 | Payment **failure** paths write `wallet_transactions` rows without an `idempotency_key`, while success paths use one. | with key: `payments.ts:176`, `262`; without: `payments.ts:208`, `216`, `235`, `289` | A replayed or retried failure webhook duplicates ledger rows. Belongs to the payments track as a correctness issue; flagged here because it defeats reconciliation. | confirmed |
| F-22-17 | S4 | `cleanup.ts` documents a migration range nine migrations out of date. | `apps/api/src/lib/cleanup.ts:11-13` claims "0001–0010"; 19 exist | Misleading to anyone reasoning about what the cleanup job covers. | confirmed |

### S1 — the blockers

**F-22-01 — Nothing alerts.** This is the finding the whole document exists to state. Across `wrangler.toml`, the CI workflow, the deployment docs and the cost docs, there is no notification rule, no uptime probe, no dead-man's switch, no paging integration. The platform is pre-production, so this has cost nothing yet. On the first Sunday after launch it will cost the difference between a fifteen-minute outage and a six-hour one. Everything else in this document is downstream of this: the metrics in §8 exist to be alerted on, and the runbooks in §6 exist to be triggered by an alert.

**F-22-02 — `/health` verifies nothing, and it is the deploy gate.** The endpoint returns `{ok: true}` from a literal. It performs no `SELECT 1` against D1, no KV read, no R2 head, no DO ping. Two consequences compound. First, any external uptime monitor pointed at it will report a green service while every trip in the country fails. Second — and worse — `docs/ci/deploy-api.yml` uses this endpoint as its post-deploy smoke test, so the pipeline's only correctness gate is "an isolate booted". A deploy that breaks the D1 binding, exhausts a KV namespace, or corrupts a DO migration passes. The fix is small and high-leverage: a `/health` that actually probes its dependencies turns both the monitor and the smoke test into real gates in one change.

**F-22-03 — Cron failure is silent by construction.** Cloudflare does not notify on cron failure by default; that is a platform property the team cannot change. What the code adds on top is worse: the handler catches every error in all three of its branches and returns normally, so from Cloudflare's perspective the invocation *succeeded*. There is no failure to notify about even if notification existed. Because `event.cron` is discarded (`index.ts:267`), the two schedules are also indistinguishable — the monthly invoice branch is gated on `if (day === 1)` at `index.ts:336` and therefore re-evaluated 1,440 times on the first of each month. The dispatch branch is the dangerous one: it is the mechanism that turns a pre-booked trip into a live search. If its D1 query starts throwing, riders who booked a ride for 7 a.m. simply never get one, and the only trace is a `console.error` line in a 7-day log buffer nobody is reading.

**F-22-04 — No correlation id.** A single trip touches the Flutter client, the Worker, `TripRoom`, `GeoCell`, `CaptainInbox`, `OfferScheduler`, D1, KV and the notification queue. Nothing joins those hops. When a captain says "I lost the trip at around 3 p.m.", the investigator has: an approximate timestamp, a phone number that appears in no log line, and 22 unstructured strings to grep. This is the single change with the highest debugging leverage in the document, and it is roughly thirty lines of middleware.

**F-22-05 — The money path writes no audit rows.** `admin.ts` calls `logAudit` nine times; `auth.ts` three; `payments.ts` three. `trips.ts` — 1371 lines covering creation, dispatch, acceptance, cancellation, completion and fare settlement — calls it zero times, and `captain.ts` zero. The import at `trips.ts:20` is the strongest evidence that this is an oversight rather than a decision: someone wired up the dependency and never used it. For a product where a completed trip moves money between a rider's wallet, a captain's balance and a commission account, the absence of an audit row at completion means a fare dispute has no authoritative record to consult. This overlaps T02 and T08 on the security and retention side; §9 hands it over.

### S2 — the majors

**F-22-06 — The rate limiter fails open.** `rateLimit.ts:31-34` catches any error from `SESSIONS.get` and calls `next()`. The intent is charitable — do not fail a rider's request because KV hiccuped — but the effect is that a KV degradation silently disables IP rate limiting across every route, including `/auth`. The failure mode is adversarially useful: an attacker who can pressure KV gets unlimited request volume. Whether the limiter should fail open or closed is T02's call; what belongs here is that it currently fails open **silently**, and that a single log line plus a counter would make the difference between an invisible security regression and an alert.

**F-22-07 — Audit writes fail silently.** Same shape as above. The `catch` at `audit.ts:33-36` is right to not break the request and wrong to not signal. Combined with F-22-05, the audit trail is incomplete where it exists and lossy where it does not.

**F-22-08 — Unstructured logs, and none on the paths that matter.** Workers Logs is on and capturing, which is the good news buried in this section. The bad news is what it captures: `console.error("cancel fanout failed", trip.id, e)`. There is no level field, no request id, no route, no user. And the five files where an operator most needs a log line during an incident — `payments.ts`, `auth.ts`, `admin.ts`, `wallet.ts`, `captain.ts` — emit nothing at all. The payment webhook can reject a Paymob callback for a bad HMAC and the only record is a D1 audit row (`payments.ts:106-113`); nothing reaches the log stream.

**F-22-09 — Nobody drains the DLQ.** The queue is configured correctly with three retries and a DLQ. What is missing is the other half: no consumer is bound to `synaptic-go-notifications-dlq`. Messages accumulate there forever. Because notifications carry trip offers and payment confirmations, a message in the DLQ is a customer who did not learn something they needed to know. The Cloudflare Queues API does expose backlog depth, so this is alertable as soon as anyone looks.

**F-22-10 — The apps are dark.** Both `pubspec.yaml` files were read in full and neither contains a crash-reporting package. Neither `main.dart` installs `runZonedGuarded`, `FlutterError.onError`, or `PlatformDispatcher.instance.onError`. An unhandled exception in the captain app during a live trip terminates the process and produces no artifact anywhere. Add the silent catches — thirteen across the two state classes, listed in §3.8 — and the mobile tier is not merely unmonitored but actively suppressing its own error signal. `fcm_service.dart:71-73` gates its only diagnostic on `kDebugMode`, so in the build users actually run, FCM can fail to initialise in total silence, which would disable push notifications for that install permanently and invisibly.

**F-22-11 and F-22-12 — The deploy story.** These belong together. The repo contains a good deploy pipeline that has never run (`docs/ci/deploy-api.yml`) and a bad deploy script that presumably has (`deploy.sh`). The script's three defects are independently serious, and the third is the one that matches a warning the codebase writes to itself: `wrangler.toml:77-85` explains at length that a bare `wrangler deploy` publishes top-level vars over production because the two blocks share a worker name and D1 id. `deploy.sh:47` then runs exactly that command. Today the blast radius is limited because `DEV_OTP` is `"false"` in both blocks (`wrangler.toml:85`, `145`) — but the guard is a coincidence of matching values, not a mechanism.
---

## 5. Benchmark gap

The benchmark for this track is **not** Uber's observability stack. It is: *a two-person team can diagnose a Sunday-morning outage in fifteen minutes.* Measured against that bar, and against what the comparable operators actually do:

| Capability | Uber / Careem (confident) | inDrive (assumed) | Synaptic Go today | Gap |
|---|---|---|---|---|
| Distributed tracing across services | Uber built and open-sourced Jaeger; every request carries a trace id end to end. | Assumed: standard APM with trace propagation. | No request id at all. | Total. This is the single widest gap. |
| Business metrics in real time | Trips/min, fill rate, time-to-match and surge inputs are live operational dashboards, not reports. | Assumed: equivalent, since dynamic matching depends on it. | Nothing. Numbers reconstructed by hand from D1. | Total. |
| Mobile crash reporting | Standard across the industry; Crashlytics or an equivalent on every release. | Assumed present. | Absent from both apps. | Total, and the cheapest to close. |
| Paging on-call | Full rotations with follow-the-sun coverage. | Assumed: regional rotation. | Nobody is paged for anything. | Total — but a two-person team should copy the *alert discipline*, not the rotation. |
| Health checks that verify dependencies | Deep health checks gating deploys and load-balancer membership. | Assumed equivalent. | Static literal. | Total, and trivially closable. |
| Structured logs | Fully structured, indexed, queryable. | Assumed equivalent. | 22 unstructured strings; Workers Logs **is** enabled and capturing them. | Partial — the transport exists, the payload does not. |
| Audit trail on money movement | Immutable ledger plus audit events on every state change. | Assumed equivalent. | `audit_log` exists and is used on 9 admin paths — but zero on the trip lifecycle. | Partial. The mechanism is built; it is not called where it matters. |

Two honest observations about the comparison.

**Synaptic Go is closer than the table suggests, in one specific way.** The hard architectural pieces of observability are already in place: a Cloudflare Workers deployment with `[observability]` enabled, an `audit_log` table with a working writer, a queue with a DLQ, and a CI workflow that correctly aggregates and reddens. This is not a codebase that needs an observability platform built. It needs the existing pieces *connected and called* — which is why most of §6's P0 work is measured in hours, not weeks.

**Scale down the SRE doctrine honestly.** Google's SRE practice assumes an org that can staff a rotation and run an error-budget freeze as a social process. Two engineers cannot. The parts that transfer are: define a small number of SLIs from real user pain, alert on symptoms rather than causes, and write down what you did after an incident. The parts that do not transfer are the ceremony. §6's P1.5 and §7 reflect that split.

---

## 6. Improvement plan

Ordered by leverage. P0 items are what must exist before production traffic; each is small, and together they take a platform from "a rider tells you" to "you know first".

### P0.1 — Correlation id and structured logging

- **Goal** — Any support complaint can be traced to the exact request, trip and Durable Object interaction that failed, in one log query.
- **Design** — A Hono middleware mounted before all routes generates a request id (accept an inbound `X-Request-Id` if present, else `crypto.randomUUID()`), stores it on the Hono context, echoes it in the response header, and exposes a `log()` helper that emits a single-line JSON object. `apps/api/src/lib/utils.ts` already holds `jsonError`, the function every route calls on an error path — that is the natural seam to instrument so error logging becomes automatic rather than opt-in. Propagate the id into the Durable Objects by forwarding the header on the `stub.fetch` calls at `index.ts:181`, `216` and `229`, and into the notification queue by adding it to the message body enqueued in `lib/notifications.ts`. On the client, add the header in `api_client.dart:10-13` and generate the id per app session plus per request.

  ```ts
  // apps/api/src/middleware/requestId.ts (new)
  export function requestId() {
    return async (c: Context<AppEnv>, next: Next) => {
      const id = c.req.header("X-Request-Id") ?? crypto.randomUUID();
      c.set("requestId", id);
      c.header("X-Request-Id", id);
      await next();
    };
  }

  // apps/api/src/lib/log.ts (new)
  export function log(c: Context<AppEnv>, level: "info" | "warn" | "error",
                      event: string, fields: Record<string, unknown> = {}) {
    console.log(JSON.stringify({
      level, event,
      rid: c.get("requestId"),
      route: c.req.routePath ?? c.req.path,
      method: c.req.method,
      userId: c.get("user")?.id ?? null,
      ts: new Date().toISOString(),
      ...fields,
    }));
  }
  ```

  Then rewrite `index.ts:233-236` to use it, and add `log(c, "error", ...)` to the payment webhook rejection paths (`payments.ts:106`, `149`) and the auth failure paths — the five files that currently emit nothing.
- **Files to change** — new `apps/api/src/middleware/requestId.ts`, new `apps/api/src/lib/log.ts`, `apps/api/src/index.ts` (mount middleware, rewrite `onError`, forward header on three `stub.fetch` calls), `apps/api/src/lib/utils.ts` (`jsonError` emits a log line), `apps/api/src/routes/payments.ts`, `auth.ts`, `wallet.ts`, `admin.ts`, `captain.ts` (add log calls on failure paths), `packages/flutter_shared/lib/services/api_client.dart`.
- **DB** — none.
- **API contract** — additive only: requests may send `X-Request-Id`; all responses gain it.
- **Effort** — M.
- **Risk** — Log volume rises. Workers Logs includes 20 M events/month on the Paid plan, and at launch volume the API will produce far less than that, so cost risk is negligible. Rollback is reverting the middleware mount.
- **Acceptance criteria** — Every response carries `X-Request-Id`. Every 5xx produces exactly one JSON log line containing `rid`, `route`, `method` and `userId`. Given a request id from a support ticket, a single dashboard query returns the Worker line and any DO lines for the same id.
- **Tests** — Unit test that the middleware honours an inbound id and generates one otherwise. An integration test asserting a forced 500 emits parseable JSON containing the same id as the response header.

### P0.2 — A `/health` that verifies its dependencies

- **Goal** — `/health` fails when the platform is broken, so that both the uptime monitor and the deploy smoke test become real gates.
- **Design** — Replace the literal at `index.ts:99-106` with a handler that probes each binding under a short timeout and reports per-dependency status, returning 200 only when all required checks pass and 503 otherwise. Keep it cheap — this endpoint will be polled every 30 seconds.

  ```ts
  app.get("/health", async (c) => {
    const t0 = Date.now();
    const probe = async (name: string, fn: () => Promise<unknown>) => {
      const s = Date.now();
      try { await fn(); return { name, ok: true, ms: Date.now() - s }; }
      catch (e) { return { name, ok: false, ms: Date.now() - s,
                           error: (e as Error).message?.slice(0, 120) }; }
    };
    const checks = await Promise.all([
      probe("d1",  () => c.env.DB.prepare("SELECT 1").first()),
      probe("kv",  () => c.env.SESSIONS.get("health:probe")),
      probe("r2",  () => c.env.FILES.head("health:probe")),
    ]);
    const ok = checks.every((x) => x.ok);
    return c.json({
      ok, service: "synaptic-go-api",
      version: c.env.APP_VERSION ?? "0.4.0",
      checks, totalMs: Date.now() - t0,
      time: new Date().toISOString(),
    }, ok ? 200 : 503);
  });
  ```

  Keep a separate `/health/live` returning the old literal for liveness-only probes, so a D1 outage does not cause a restart loop in anything that treats 503 as "kill this instance". Do **not** probe the Durable Objects here — a DO probe instantiates an object and costs more than it tells you; DO health is covered by the metrics in P1.1.
- **Files to change** — `apps/api/src/index.ts:99-106`.
- **DB** — none. `SELECT 1` does not touch a table.
- **API contract** — `GET /health` gains a `checks[]` array and may now return 503. New `GET /health/live`.
- **Effort** — S.
- **Risk** — A monitor that treated `/health` as always-200 will start alerting. That is the point. `R2.head` on a nonexistent key returns null rather than throwing, so it verifies reachability, not content.
- **Acceptance criteria** — With a deliberately broken D1 binding in a local `wrangler dev`, `/health` returns 503 with `checks[0].ok === false`. Normal operation returns 200 and `totalMs` under 100 ms.
- **Tests** — Integration test per binding failure. Assert the deploy smoke test fails when D1 is unbound.

### P0.3 — Make cron failure detectable

- **Goal** — If the every-minute dispatch cron stops working, someone is paged within two minutes.
- **Design** — Three changes, in order of importance.

  1. **Stop swallowing.** Each of the three branches in `scheduled` currently ends in `console.error` and returns. Track failure explicitly and re-throw at the end so Cloudflare records a failed invocation, which makes the platform's own cron metrics meaningful for the first time.
  2. **Route on `event.cron`.** Replace `_event` at `index.ts:267` with a real parameter and dispatch on it, so the every-minute trigger runs dispatch and the `0 3 1 * *` trigger runs invoices. This removes the `if (day === 1)` gate at `index.ts:336` and the 1,440 redundant evaluations on the first of each month.
  3. **Dead-man's switch.** Cloudflare will not tell you that a cron *stopped firing* — only an external observer can. Ping a Healthchecks.io check at the end of a successful dispatch run.

  ```ts
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    const failures: string[] = [];
    if (event.cron === "*/1 * * * *") {
      await runCleanupIfDue(env).catch((e) => failures.push(`cleanup: ${e.message}`));
      await dispatchDueScheduledTrips(env).catch((e) => failures.push(`dispatch: ${e.message}`));
      if (failures.length === 0 && env.HC_DISPATCH_UUID) {
        ctx.waitUntil(fetch(`https://hc-ping.com/${env.HC_DISPATCH_UUID}`).catch(() => {}));
      }
    } else if (event.cron === "0 3 1 * *") {
      await generateMonthlyInvoices(env).catch((e) => failures.push(`invoices: ${e.message}`));
      if (failures.length === 0 && env.HC_INVOICE_UUID) {
        ctx.waitUntil(fetch(`https://hc-ping.com/${env.HC_INVOICE_UUID}`).catch(() => {}));
      }
    }
    if (failures.length) throw new Error(`scheduled failures: ${failures.join("; ")}`);
  }
  ```

  Note the ordering: the heartbeat fires **only** when the run had no failures, so a cron that runs but fails still trips the dead-man's switch. Configure the Healthchecks.io check with a 1-minute period and a 90-second grace, and the invoice check with a monthly period and a 90-minute grace (the invoice job iterates every active company against D1 and can legitimately take minutes).
- **Files to change** — `apps/api/src/index.ts:266-371` (extract the three branches into named functions in `lib/`, add routing and heartbeats).
- **DB** — none.
- **API contract** — none. New secrets `HC_DISPATCH_UUID`, `HC_INVOICE_UUID` via `wrangler secret put` (treat the UUIDs as credentials — anyone holding one can silence the alarm).
- **Effort** — M.
- **Risk** — Re-throwing means Cloudflare now records cron failures, which is the intent, but it also means a transient D1 blip shows as a failed invocation. That is correct behaviour and the 90-second grace absorbs single misses.
- **Acceptance criteria** — Forcing the dispatch query to throw produces a failed invocation in the Cloudflare cron dashboard **and** a Healthchecks.io alert within 90 seconds. On the first of the month, the invoice branch executes once, not 1,440 times.
- **Tests** — Unit tests for the three extracted functions. A manual game-day: revoke the D1 binding in staging and confirm the page arrives.

### P0.4 — The minimum viable alert set

- **Goal** — Six alerts that would each have caught a real outage, delivered to a phone.
- **Design** — Thresholds are calibrated for launch volume (~200 trips/day, ~8/hour). Ratio alerts break at low N, so each carries a minimum-sample gate (MSG) and an absolute-count fallback. Delivery path: Analytics Engine or Queues API → a 5-minute poller (Better Stack or a small scheduled Worker) → webhook → PagerDuty/Better Stack → phone. Cron alerts come directly from Healthchecks.io.

| # | Alert | Condition | Window | Severity | Why this number |
|---|---|---|---|---|---|
| A1 | Dispatch cron silent | Healthchecks.io check `down` (no ping within 60 s period + 30 s grace) | continuous | **Page** | Two consecutive missed fires. Every minute of silence is a pre-booked rider who is not being dispatched. |
| A2 | `/health` failing | 2 consecutive failed probes from an external monitor, 30 s interval | 1 min | **Page** | Two consecutive rules out a single transient. Depends on P0.2 shipping first — against today's static endpoint this alert is meaningless. |
| A3 | Payment webhook rejections | ≥3 responses of 401 from `POST /payments/paymob/webhook` | 10 min | **Page** | Paymob retries a failed callback, so a single 401 can be legitimate. Three means the HMAC secret is wrong or rotated — and every card payment is failing. |
| A4 | Trips stuck searching | ≥3 trips with `status='searching'` and `created_at` older than 5 min | 5 min | **Page** | At 8 trips/hour, three simultaneously stuck is not a coincidence — it is a dispatch failure. Ratio would never fire at this volume; absolute count is correct here. |
| A5 | DLQ depth | `synaptic-go-notifications-dlq` backlog ≥5 | 5 min | **Ticket** (≥5), **Page** (≥20) | Normal steady state is zero. Five means repeated failures against a push provider; twenty means it is systemic. |
| A6 | Worker 5xx rate | >2% of invocations with `scriptThrewException`, MSG ≥30 invocations; absolute fallback ≥5 in 5 min | 5 min | **Ticket** (2%), **Page** (>10%) | The MSG stops a 1-of-3-requests blip from paging. The absolute fallback catches the low-traffic case the ratio would suppress. |

  Two more worth adding once the metric layer exists (P1.1), which cannot be expressed today: audit-write failures ≥3 in 10 minutes (`audit.ts:35`), and rate-limiter KV failures ≥3 in 5 minutes (`rateLimit.ts:31`) — both currently invisible security-relevant events.

  **The discipline that keeps this working:** every alert here has a named first action (see the runbooks). An alert without a response is noise, and a two-person team that starts ignoring pages is worse off than one with no alerts at all. Review every firing after the fact; if it was a false positive, change the threshold before the next rotation.
- **Files to change** — none in the API for A1/A2/A5; A3/A4/A6 depend on P1.1.
- **DB** — none.
- **Effort** — M (mostly configuration).
- **Risk** — Alert fatigue is the real risk, not cost. Start with these six. Do not add the long tail until these have been quiet for two weeks.
- **Acceptance criteria** — Each alert has fired at least once in a deliberate game-day test and reached a phone.
- **Tests** — Game-day: break D1, stop the cron, push a poison message to the queue, send a bad-HMAC webhook.

### P0.5 — Audit the trip lifecycle

- **Goal** — Every trip state transition and every fare settlement leaves a queryable, attributable row.
- **Design** — Call the `logAudit` that `trips.ts:20` already imports, at each state transition: create, offer, accept, cancel, complete, and fare finalisation. Use stable action names (`trip.created`, `trip.accepted`, `trip.cancelled`, `trip.completed`, `trip.fare_settled`) with `entityType: "trip"` and `entityId: tripId`, and include actor, previous status and new status in the payload. Do the same for the captain state changes in `captain.ts` (online/offline, radius change, document submission). Additionally, make audit failure visible: keep the swallow at `audit.ts:33-36` so requests never break, but emit a structured `log(..., "error", "audit_write_failed", ...)` so A-series alerting can see it.
- **Files to change** — `apps/api/src/routes/trips.ts` (six call sites), `apps/api/src/routes/captain.ts`, `apps/api/src/lib/audit.ts` (structured failure log).
- **DB** — none. The `audit_log` table already exists and `admin.ts:222` already reads it. Index coverage for querying by `entity_id` is T02/T08's call — flagged in §9.
- **API contract** — none.
- **Effort** — M.
- **Risk** — Each `logAudit` adds a D1 write to the trip hot path. `logAudit` is already `await`ed elsewhere; on the completion path consider `ctx.waitUntil` to keep it off the critical path. Audit volume grows with trips — retention policy is T08's.
- **Acceptance criteria** — A completed trip produces audit rows for created, accepted, completed and fare_settled, all sharing `entity_id`. A forced audit failure produces a structured error log without failing the trip.
- **Tests** — Integration test walking a trip through the full lifecycle and asserting the audit row sequence.

### P0.6 — Make deployment safe and recorded

- **Goal** — No one can deploy production from a laptop with the wrong flags, and every deploy is logged.
- **Design** — Three independent changes, all small:
  1. **Install the pipeline.** Move `docs/ci/deploy-api.yml` to `.github/workflows/deploy-api.yml`. It already does the right things — gates, `wrangler d1 migrations apply --remote --env prod`, `wrangler deploy --env prod`, smoke test. *This document cannot make that move: the GitHub App has no `workflows` permission, so the file is provided for a human to copy.*
  2. **Fix or delete `deploy.sh`.** It applies one hardcoded migration of 19 (`deploy.sh:30`), omits `--remote` so the migration hits the local database (`deploy.sh:40`), and omits `--env prod` (`deploy.sh:47`). The honest fix is deletion once the pipeline is installed. If it must stay as a break-glass path, it needs `wrangler d1 migrations apply "$DB_NAME" --remote` and `wrangler deploy --env prod`.
  3. **Turn on branch protection.** `ci.yml:6-9` documents exactly what is needed: add the three jobs as required status checks on `main`. This is a settings change, not code, and it converts an existing correct workflow from advisory to binding.
  Once the smoke test is meaningful (P0.2), extend it to fail the deploy on a 503 and add an automatic `wrangler rollback --env prod` on smoke failure — noting the limit in the rollback table below.
- **Files to change** — `apps/api/deploy.sh`; a human moves `docs/ci/deploy-api.yml`; repository settings.
- **DB** — none.
- **Effort** — S.
- **Risk** — Branch protection will block merges that are currently getting through. Expect a backlog of genuine failures on first enforcement.
- **Acceptance criteria** — A PR with a type error cannot be merged. A deploy appears in `wrangler deployments list` with a CI run id. `deploy.sh` either applies all migrations remotely or does not exist.
- **Tests** — Open a deliberately broken PR and confirm it is blocked.

### P0.7 — Give the DLQ an owner

- **Goal** — No customer notification dies silently.
- **Design** — Add a `[[queues.consumers]]` block for `synaptic-go-notifications-dlq` bound to a handler that writes each dead message to a `notification_dlq` table (or the existing notification log) with its payload and last error, emits a structured log line, and acks. That converts an invisible backlog into a queryable list and makes A5 alertable. Manual replay is then a matter of reading rows and re-enqueueing.
- **Files to change** — `apps/api/wrangler.toml` (new consumer block in default and `env.prod`), `apps/api/src/index.ts` (the exported `queue` handler must branch on which queue delivered the batch).
- **DB** — one migration (`0020_notification_dlq.sql`) if a dedicated table is preferred: `id`, `user_id`, `topic`, `payload` (JSON), `error`, `failed_at`, `replayed_at`.
- **API contract** — optionally an admin endpoint to list and replay; coordinate with the admin track.
- **Effort** — S.
- **Risk** — Low. Worst case the DLQ consumer itself fails, which is visible via A6.
- **Acceptance criteria** — A message that fails three retries appears as a row within a minute and produces a log line. DLQ backlog returns to zero.
- **Tests** — Enqueue a poison message; assert it lands in the table after retries are exhausted.
### P1.1 — Metrics via Workers Analytics Engine

- **Goal** — Trips, matches, payments and latency become numbers on a chart instead of an ad-hoc D1 query.
- **Design** — Add three Analytics Engine datasets and emit from the code paths that already exist. Analytics Engine takes `blobs` (string dimensions), `doubles` (numeric values) and exactly **one** `indexes` entry — supplying more than one index silently drops the data point, and array order is positional, so it must stay stable across every write to a dataset.

  ```toml
  # apps/api/wrangler.toml — repeat under [env.prod] as [[env.prod.analytics_engine_datasets]]
  [[analytics_engine_datasets]]
  binding = "TRIP_EVENTS"
  dataset = "synaptic_go_trip_events"

  [[analytics_engine_datasets]]
  binding = "PAYMENT_EVENTS"
  dataset = "synaptic_go_payment_events"

  [[analytics_engine_datasets]]
  binding = "HTTP_REQUESTS"
  dataset = "synaptic_go_http_requests"
  ```

  Datasets are created on first write; no `wrangler` create step. Emission is fire-and-forget and does not need `await`:

  ```ts
  // at each trip transition in trips.ts, alongside the logAudit call from P0.5
  c.env.TRIP_EVENTS.writeDataPoint({
    blobs:   [eventType, city, paymentMethod, cancelledBy ?? ""],
    doubles: [1, timeToAcceptSec, finalFare, captainsOffered],
    indexes: [tripId],
  });
  ```

  **Metric catalogue.** Business metrics first, because they are the ones that tell you the product is broken rather than the server:

| Metric | Type | Emit at | Dimensions | Why it matters |
|---|---|---|---|---|
| `trip.created` | counter | `trips.ts`, after the trip INSERT | city, payment_method, scheduled? | Demand baseline. A drop is a broken booking funnel. |
| `trip.offered` | counter | `trips.ts`, on transition to `offered` | city, captains_offered | With `trip.created`, gives dispatch fill rate — the core supply health number. |
| `trip.accepted` | counter + histogram | `trips.ts`, on transition to `assigned` | city, time_to_accept_sec | p95 time-to-match. The number that decides whether a rider closes the app. |
| `trip.completed` | counter | `trips.ts`, on completion | city, payment_method, final_fare | GMV proxy. |
| `trip.cancelled` | counter | `trips.ts`, on cancellation | city, cancelled_by, from_status | Cancellation by stage. Post-assignment rider cancels mean ETAs are too long. |
| `dispatch.fill_rate` | derived gauge | `trip.offered / trip.created` per 5 min per city | city | Feeds A4. Below ~0.9 sustained means supply or radius config is wrong. |
| `payment.settled` | counter | `payments.ts:224` | purpose, method, amount | Payment success rate denominator/numerator with the next row. |
| `payment.failed` | counter | `payments.ts:230` | purpose, reason | Distinguishes a provider outage from a card decline. |
| `payment.rejected_hmac` | counter | `payments.ts:106-113` | — | Security signal. Non-zero means the webhook is being probed or the secret rotated. Feeds A3. |
| `audit.write_failed` | counter | `audit.ts:35` | action | Makes F-22-07 visible. |
| `ratelimit.kv_failed` | counter | `rateLimit.ts:31` | prefix | Makes F-22-06 visible — the security control silently disengaging. |
| `queue.notification_failed` | counter | `index.ts:260` | topic | Leading indicator for DLQ growth. |
| `cron.dispatch_processed` | counter | dispatch branch | rows_processed | A run that processes zero rows on a day with bookings is a failure the heartbeat cannot see. |
| `http.request` + `duration_ms` | counter + histogram | Tail Worker (P1.2) | method, route, status | p50/p95/p99 and error rate per route, with zero hot-path cost. |
| `ws.connection_opened` | counter | `index.ts:129`, `187` | type, auth_method | Connection load and post-deploy reconnect storms. |

- **Files to change** — `apps/api/wrangler.toml`, `apps/api/src/routes/trips.ts`, `payments.ts`, `apps/api/src/lib/audit.ts`, `apps/api/src/middleware/rateLimit.ts`, `apps/api/src/index.ts`.
- **DB** — none.
- **Effort** — M.
- **Risk** — Low; `writeDataPoint` does not block the response. Cost is the real question and the answer is reassuring: at 250 trips/day and ~15 points per trip, roughly 112 K points/month against the 10 M/month included in the Workers Paid plan. Even at 2,000 trips/day this stays inside the included tier. `needs-check`: confirm the account is on Workers Paid — Durable Objects are in use, which requires it, so this is near-certain but was not verified in any file read.
- **Acceptance criteria** — A completed trip produces `created`, `offered`, `accepted`, `completed` points queryable via the Analytics Engine SQL API. Fill rate and p95 time-to-match are chartable.
- **Tests** — Assert `writeDataPoint` is called with a stable positional shape at each transition.

### P1.2 — Tail Worker for per-request metrics

- **Goal** — Latency and error rate per route without touching a single route handler.
- **Design** — Deploy a separate small Worker whose `tail()` handler receives every invocation outcome — including `wallTime`, `outcome` and the response status — and writes one `HTTP_REQUESTS` data point per invocation. Bind it with `[[tail_consumers]] service = "synaptic-go-tail"` in the API's `wrangler.toml` (and under `[env.prod]`). This is the cleanest way to get T1/T2 metrics: no hot-path cost, no route edits, and it captures invocations that threw before any handler ran.
- **Files to change** — new `apps/tail/` Worker; `apps/api/wrangler.toml`.
- **DB** — none.
- **Effort** — M.
- **Risk** — Tail Workers require the Workers Paid plan. Billed on the Tail Worker's CPU time, negligible at this volume.
- **Acceptance criteria** — p95 latency per route is chartable without any change to `routes/`.

### P1.3 — Crash reporting in the apps

- **Goal** — A crash in a captain's app during a live trip produces an artifact someone can read.
- **Design** — Sentry (`sentry_flutter`) in both Flutter apps and `@sentry/react` in the admin. Sentry over Crashlytics for two reasons: `beforeSend` runs synchronously and gives complete control over what leaves the device, and the data-residency options matter for an Egyptian product. `SentryFlutter.init` installs `runZonedGuarded`, `FlutterError.onError` and `PlatformDispatcher.instance.onError` itself, so this also closes the "no error hooks" half of F-22-10.

  **Privacy is the hard part, not the integration.** This product handles precise location, phone numbers, national ID documents and payment tokens. Scrubbing is not optional:

| Data | Where it leaks from | Action |
|---|---|---|
| Precise coordinates | `captain_state.dart` location pushes, `activeTrip`, offers | Round to 2 dp (~1.1 km) or strip |
| Phone numbers | `user['phone']`, registration payloads | Mask; drop breadcrumbs matching the Egyptian mobile pattern |
| JWT access/refresh tokens | `Authorization` header, `AppState.token` | Strip all `Authorization` headers; never in breadcrumbs |
| National ID | captain document upload | Strip keys matching `national_id`/`nid` |
| Paymob iframe URL | `topUpViaPaymob` response | Strip — carries a one-time token in the query string |
| FCM device token | `fcmToken` | Strip |

  Keep `options.sendDefaultPii = false` (the default), gate initialisation behind a first-launch consent flag, and enable only in release builds. Update `ErrorBoundary.componentDidCatch` (`apps/admin/src/components/ui/ErrorBoundary.tsx:36-41`) to call `Sentry.captureException` alongside its existing `console.error`.

  Separately and independently of Sentry: `api_client.dart` has no timeout and no retry (`api_client.dart:15-27`). Add a request timeout and surface failures to the UI — thirteen silent catches across the two state classes (§3.8) mean users currently see nothing when the network fails.
- **Files to change** — both `pubspec.yaml`, both `main.dart`, `apps/admin/src/main.tsx`, `apps/admin/src/components/ui/ErrorBoundary.tsx`, `packages/flutter_shared/lib/services/api_client.dart`.
- **Effort** — M.
- **Risk** — Shipping PII to a third party if scrubbing is wrong. Review the first week of events manually before considering it done.
- **Acceptance criteria** — A deliberate crash in a release build appears in Sentry within a minute, with no coordinate, phone number or token anywhere in the payload.

### P1.4 — The runbooks and the on-call practice

Delivered in §6.R below. Effort M; the cost is writing them, and they are written.

### P1.5 — SLOs sized for two people

- **Goal** — Three numbers that drive decisions, and a policy two people would actually follow.

| SLO | SLI | Target | Window | Why this number |
|---|---|---|---|---|
| API availability | non-5xx invocations without `scriptThrewException` / total | **99.5%** | 28-day rolling | ~3.4 h of budget per 28 days. 99.9% (43 min) is not survivable while shipping fixes and running 19-deep migrations pre-launch. Cloudflare's own reliability is far higher, so the budget is spent almost entirely on application errors — which is the team's actual responsibility. |
| Time to match | fraction of immediate trips reaching `offered` within 90 s | **90%** | 7-day rolling | Matching is the rider-experience metric. At early supply density ~10% of trips legitimately have no nearby captain. A 7-day window is deliberate — matching degrades fast when supply drops, and a 28-day window would hide a bad week. |
| Payment settlement | webhooks reporting success that settle in D1 within 30 s / all success webhooks | **99.9%** | 28-day rolling | The highest-stakes path: a miss means a rider was charged and not credited. ~40 failures per 28 days at launch volume — each should be investigated individually. Achievable because the settle path is a single D1 update. |

  **Error budget policy, honestly scaled.** A 30-minute weekly check where one engineer posts three burn numbers. Under 50% consumed at the halfway point: ship normally. 50–75%: both engineers review any change touching D1 schema, payments or dispatch, and every deploy carries a written rollback plan. Over 75%, or exhausted: only security fixes and P0 remediation deploy until the burn is back under 50%. Any single incident consuming >20% of the budget gets a blameless write-up — three action items, thirty minutes, before the next feature deploy. No freeze ceremony, no committee. If the burn was caused by a third-party outage rather than the team's code, keep shipping but add the mitigation as a P0.

  Payment SLO carries one extra rule regardless of budget: every settlement failure gets a support ticket and the user is made whole within 24 hours.

  **On-call for two.** There is no 24/7 rotation and pretending otherwise causes burnout. One engineer is primary for a week; the other is reachable by escalation only. Nights are covered for P0 only: dispatch cron silent (A1), `/health` down (A2), payment webhook rejections (A3), trips stuck searching (A4). Everything else waits for morning. Escalation: primary has 10 minutes to acknowledge, then the secondary is paged; beyond that there is no tier, and the team should write that down rather than pretend. Group correlated alerts into one incident — when D1 fails, A2, A4, A5 and A6 all fire and the engineer should get one page, not four. Tooling that makes this work costs about $25–45/month total: Better Stack free tier for the external `/health` probe and on-call scheduling, Healthchecks.io for the cron dead-man's switch, PagerDuty free tier for the rotation, on top of the existing Workers Paid plan.

### P2.1 — A staging environment that exists

`[env.staging]` has a placeholder D1 id and no KV, R2, DO or queue bindings (`wrangler.toml:157-180`). Provision the real bindings so migrations and runbooks can be rehearsed somewhere other than production. Effort M. This is P2 only because it is not required to *detect* an outage — but every game-day test in this document is degraded without it.

### P2.2 — Dashboards and log retention

Point Grafana (free tier) at the Analytics Engine SQL API for the four charts that matter: trips by status over time, dispatch fill rate by city, payment success rate, and p95 latency by route. Consider `logpush = true` to R2 only if retention beyond the Workers Logs window is needed for compliance — coordinate with T08, and note it requires a Logpush job to exist in the dashboard first or writes are silently dropped. Effort S–M.

---

## 6.R — The five runbooks

Each is written for a two-person team at 03:00. All table and column names below were verified against the source at the pinned commit. Note the table is **`audit_log`**, singular.

### R1 — Payments down / webhook failures

**How you find out (today):** a rider says their wallet was not credited. There is no alert on webhook 401s. After P0.4, alert **A3**.

**Blast radius:** all card payments and wallet top-ups. Cash trips are unaffected. Payment *initiation* still works — riders get a Paymob iframe, pay, and hear nothing back.

**Diagnosis**

1. Tail the webhook: `wrangler tail --env prod --format pretty | grep webhook`. A 401 means HMAC verification failed (`payments.ts:113`); a 502 from `POST /payments/paymob/intention` means the outbound Paymob call failed (`payments.ts:91`).
2. Read the rejections — the code writes them to the audit table (`payments.ts:106-113`):
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command \
     "SELECT created_at, action, payload FROM audit_log
       WHERE action LIKE 'payment.webhook%' ORDER BY created_at DESC LIMIT 20;"
   ```
3. Find stuck money — intentions that never settled:
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command \
     "SELECT id, user_id, order_id, amount_piastres, purpose, status, created_at
        FROM payment_intentions
       WHERE status = 'pending' AND created_at < datetime('now','-15 minutes')
       ORDER BY created_at DESC LIMIT 20;"
   ```
4. Confirm the secret exists: `wrangler secret list --env prod`. A missing `PAYMOB_HMAC` fails every callback.

**Mitigation**

1. Missing or rotated secret: `wrangler secret put PAYMOB_HMAC --env prod`. Secrets take effect immediately; no redeploy.
2. Replay from the Paymob dashboard. The success path is idempotent — `wallet_transactions` uses `INSERT OR IGNORE` on `idempotency_key = paymob:{orderId}:{txnId}` (`payments.ts:174-179`), so a replay cannot double-credit. **Caution:** the *failure* paths write without an idempotency key (`payments.ts:208, 216, 235, 289`), so replaying a failed callback can duplicate ledger rows. Check before bulk replay.
3. Manual credit only as a last resort, and record it. The balance update is `users.wallet_balance` / `wallet_balance_piastres` (`payments.ts:183`).

**Rollback:** a wrong secret is not a code problem — do not roll back the Worker. If a `paymob.ts` change caused it, `wrangler rollback --env prod` reverts code but not D1 rows already written.

**Post-incident:** count intentions still `pending` in the window — each is a rider owed money. Add A3 if not already live.

### R2 — Dispatch not matching

**How you find out (today):** a rider says no captain ever came; the trip sits in `searching`. After P0.4, alert **A4**.

**Blast radius:** all new trips in the affected city. In-progress trips unaffected.

**Diagnosis**

1. Confirm the symptom:
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command \
     "SELECT id, city, status, created_at FROM trips
       WHERE status IN ('searching','offered')
         AND created_at < datetime('now','-5 minutes')
       ORDER BY created_at DESC LIMIT 20;"
   ```
2. Is anyone online? Zero online captains is the most common cause and is not an outage:
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command \
     "SELECT city, COUNT(*) AS online FROM captains WHERE is_online = 1 GROUP BY city;"
   ```
3. Check the radius filter. `trips.ts` filters GeoCell results by each captain's `search_radius_km`; if every nearby captain has a small radius the filtered list is empty and the trip never leaves `searching`. Worse, that filter's failure path swallows the error (`trips.ts:68`) and returns the list **unfiltered**, so a degraded D1 causes over-notification rather than under — a real behaviour difference worth knowing at 03:00.
4. Check the scheduled-dispatch backlog — this is the cron's work:
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command \
     "SELECT id, trip_id, status, scheduled_for, dispatched_at
        FROM scheduled_trip_dispatch
       WHERE status = 'pending' AND scheduled_for <= datetime('now')
       ORDER BY scheduled_for LIMIT 20;"
   ```
   Rows here with `scheduled_for` in the past mean the cron is not running — go to R-cron below and check the Healthchecks.io state.
5. Offer waves: `OfferScheduler` pushes wave 1 immediately and later waves on a DO alarm; a failed push is logged and dropped (`OfferScheduler.ts:118`) with no retry and no persistent record. `wrangler tail` is the only window.

**Mitigation:** if captains are offline, this is an operations problem, not an engineering one — contact them. To re-drive a stuck trip, reset it to `searching` and let the client resubmit. There is no automated re-dispatch after teardown.

**Rollback:** only if a deploy introduced it — `wrangler rollback --env prod`.

### R3 — WebSocket mass disconnect

**How you find out (today):** riders report the live map froze, or captains stop receiving offers. Note FCM push is a partial fallback for offers (`trips.ts:574-585`), so captains may still get *some* offers while the socket is dead — which makes this failure quieter than it should be.

**Diagnosis**

1. `curl -s https://api.synapticstudio.tech/health` — if the Worker is down, this is R5.
2. `wrangler tail --env prod --format pretty | grep -E "TripRoom|CaptainInbox|webSocket"` and look for closes without matching reconnects.
3. Check whether a deploy just happened: `wrangler deployments list --env prod`. **Every `wrangler deploy` drops all live WebSocket connections.** A "mass disconnect" that coincides with a deploy is expected behaviour, not an incident — this is the first thing to rule out.
4. Two structural notes worth knowing while diagnosing. `TripRoom` accepts sockets via the hibernation API, so the in-memory session map and the hibernation registry can disagree after an eviction. And the pending-auth timeout is a `setTimeout`, which does **not** survive hibernation — an unauthenticated socket that outlives an eviction is never closed by the timer. Both belong to T07; they are listed in §9.

**Mitigation:** clients reconnect by reopening the app; there is no server-side reconnect signal. If the DO namespace itself is unhealthy, there is no lever on the team's side beyond waiting on Cloudflare.

**Rollback:** rollback also drops all sockets. Reconnection is required either way.

### R4 — D1 degraded

**How you find out (today):** 500s in the app. After P0.2 and P0.4, alert **A2** and **A6**.

**Blast radius:** near-total. Auth, trip creation, payments and admin all read or write D1 on every request. GeoCell captain presence lives in DO storage and survives, so captains may appear online while nothing else works.

**Diagnosis**

1. Is D1 reachable at all?
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command "SELECT 1;"
   ```
2. Check Cloudflare status before anything else — D1 has no failover and no read replica.
3. Migration state, if this follows a deploy:
   ```sh
   wrangler d1 execute synaptic-go --remote --env prod --command \
     "SELECT name FROM d1_migrations ORDER BY name DESC LIMIT 5;"
   ```
   Compare against the 19 files in `migrations/` (`0001`–`0019`).
4. **Expect partial writes.** There are no transactions or batches on the money paths: the webhook inserts a `wallet_transactions` row and then separately updates `users.wallet_balance` (`payments.ts:176-186`), and trip completion issues several sequential statements. A D1 failure between them leaves a settled ledger row and a stale balance. After any D1 incident, reconcile ledger sum against balance rather than assuming consistency. The non-atomicity itself is the payments track's to fix; §9 hands it over.

**Mitigation:** wait out a platform incident; there is no application-level lever. Correct partial writes manually afterwards, from the ledger.

**Rollback:** `wrangler rollback` reverts Worker code only. **D1 migrations are not reversible** — recovery from a bad migration is a forward migration. D1 Time Travel may be available on the account but is not configured in anything read here (`needs-check`).

### R5 — Bad deploy

**How you find out (today):** users report breakage. The smoke test cannot catch it, because `/health` is a literal (F-22-02).

**Diagnosis**

1. `wrangler deployments list --env prod` — what changed and when.
2. `curl -s https://api.synapticstudio.tech/health` (meaningful only after P0.2).
3. `wrangler tail --env prod --format pretty | grep -E "5[0-9]{2}|error"`.
4. **Check for an accidental bare deploy.** If someone ran `deploy.sh`, it deployed without `--env prod` (`deploy.sh:47`), publishing the top-level `[vars]` over production. Today both blocks set `DEV_OTP = "false"` (`wrangler.toml:85`, `145`) so the worst case is contained — but verify rather than assume:
   ```sh
   curl -s -X POST https://api.synapticstudio.tech/auth/otp/send \
     -H 'Content-Type: application/json' -d '{"phone":"01000000000"}'
   ```
   If the OTP appears in the response body, a dev-vars deploy is live and anyone can log in as anyone. Redeploy with `--env prod` immediately — do **not** `wrangler rollback`, which may land on an even older bad version.

**Mitigation, least destructive first**

1. Code-only regression, no migration applied: `wrangler rollback --env prod`. Instant, D1 untouched.
2. Code plus migration: rollback reverts the code but the schema change stays. If the old code cannot read the new schema, roll forward instead.
3. Remember the smoke test runs *after* the deploy is live (`docs/ci/deploy-api.yml`), so a smoke failure does not undo anything — rollback is manual until P0.6 automates it.

| Change | Reversible? |
|---|---|
| Worker code | Yes — `wrangler rollback --env prod` |
| D1 migration | **No** — forward migration only |
| D1 data (credits, trips) | No — manual SQL |
| Secrets | Overwrite with `wrangler secret put` |

**Post-incident:** install `docs/ci/deploy-api.yml` (P0.6) so this stops being a manual path.
---

## 7. Phasing

| Item | Phase | Effort | Owner type | Unblocks |
|---|---|---|---|---|
| P0.2 — real `/health` with dependency probes | **P0** | S | backend | A2, and makes the deploy smoke test meaningful |
| P0.6 — install deploy pipeline, fix `deploy.sh`, branch protection | **P0** | S | ops | Safe deploys; R5 |
| P0.7 — DLQ consumer | **P0** | S | backend | A5 |
| P0.1 — correlation id + structured logging | **P0** | M | backend | Every runbook; all log-based alerts |
| P0.3 — cron routing, re-throw, dead-man's switch | **P0** | M | backend + ops | A1 |
| P0.4 — the six-alert set | **P0** | M | ops | On-call has something to receive |
| P0.5 — audit the trip lifecycle | **P0** | M | backend | Fare disputes; T02/T08 |
| P1.1 — Analytics Engine metric emission | P1 | M | backend | A3, A4, A6; all SLOs |
| P1.3 — Sentry in both apps + admin | P1 | M | Flutter + admin | Mobile visibility |
| P1.4 — runbooks in the repo, on-call set up | P1 | M | ops | Delivered in §6.R |
| P1.5 — SLOs and error-budget policy | P1 | S | ops | Weekly review |
| P1.2 — Tail Worker for per-request latency | P1 | M | backend | p95 per route |
| P2.1 — provision a real staging environment | P2 | M | ops | Game-days, migration rehearsal |
| P2.2 — Grafana dashboards, Logpush if needed | P2 | S–M | ops | Weekly SLO review |

**The P0 set is deliberately small.** Seven items, four of them S or fast M. The ordering inside P0 matters: `/health` and the deploy fixes are the cheapest and unblock the most, the correlation id is the highest debugging leverage, and the alert set should land last in P0 because several of its alerts depend on the others existing.

**One dependency to respect:** do not configure alert A2 before P0.2 ships. Alerting on today's static `/health` would create an alert that can never fire — worse than no alert, because it looks like coverage.

---

## 8. Metrics

What to instrument to prove this work landed. Current values are "unknown" wherever the platform genuinely cannot answer the question today — that absence is itself the baseline.

| Metric | Current | Target | How measured |
|---|---|---|---|
| Mean time to detection (MTTD) for a total outage | Unbounded — a rider tells you | < 5 min | Game-day: break D1, measure to page |
| Fraction of 5xx responses with a structured log line carrying a request id | 0% | 100% | Log query for `rid` field |
| API files emitting zero log lines on failure paths | 5 of 14 route files (`payments`, `auth`, `admin`, `wallet`, `captain`) | 0 | Static census, same method as §3.1 |
| Trip lifecycle transitions producing an audit row | 0 of 6 | 6 of 6 | Integration test through full lifecycle |
| Alerts configured and tested end-to-end | 0 | 6 | Each fired once in a game-day |
| Cron silent-failure window | Unbounded | ≤ 90 s | Healthchecks.io grace configuration |
| `/health` dependency coverage | 0 bindings probed | D1, KV, R2 | Response `checks[]` length |
| DLQ messages with a recorded owner | 0% | 100% | Row count in DLQ table vs queue backlog |
| Mobile crashes visible to the team | 0% | > 95% of sessions reporting | Sentry release health |
| Deploys through the audited pipeline | 0% (all manual) | 100% | GitHub Actions run per `wrangler deployments list` entry |
| Dispatch fill rate | Unknown | Measured, then ≥ 90% | `trip.offered / trip.created`, per city, 5-min buckets |
| p95 time-to-match | Unknown | Measured, then ≤ 90 s | `trip.accepted` histogram |
| Payment settlement rate | Unknown | ≥ 99.9% | `payment.settled / (settled + failed)` |
| Observability cost | $0 | < $50/month all-in | Cloudflare bill + Healthchecks.io + Better Stack |

The most important row is the first one, and the most important thing about the rest is that eleven of them currently read "unknown" or "0%". This axis is not underperforming — it is unmeasured, which is a different and more urgent problem.

---

## 9. Cross-cutting notes

Findings outside this track's remit, handed to their owners. Not fixed here.

**→ T02 (auth / security)**

- The rate limiter fails open on any KV error (`rateLimit.ts:31-34`). Whether it should fail open or closed is a security decision, not an observability one. This document only adds the counter that makes the event visible (P1.1).
- The global error handler returns `err.message` to the client (`index.ts:235`), leaking internal error text — including, potentially, D1 error strings — to any caller.
- The deprecated `?token=` query parameter on both WebSocket upgrade paths (`index.ts:142-144`, `197-199`) puts JWTs into access logs. The code comments already flag this as deprecated; it interacts with observability because enabling Logpush would persist those tokens to storage. **Resolve the token-in-URL issue before enabling Logpush.**
- `deploy.sh:47` deploys without `--env prod`, which `wrangler.toml:77-85` documents as the path that can publish `DEV_OTP` over production. Currently contained only because both blocks happen to set `"false"`.

**→ T08 (data / audit retention)**

- `audit_log` has no retention policy visible in `cleanup.ts` (which purges only `otp_codes` and `refresh_tokens`). Once P0.5 lands, audit volume grows with every trip.
- Query performance: `admin.ts:222` reads `audit_log` with `ORDER BY created_at DESC LIMIT ?` and no filter. Whether `entity_id` and `actor_id` are indexed was not verified — `needs-check`. Brief question 8 asks whether the audit log is "queryable at speed, complete, and immutable": it is currently **not complete** (F-22-05), and speed and immutability are T08's to answer.
- `cleanup.ts:11-13` documents the migration range as "0001–0010" when 19 exist — stale comment, may indicate the cleanup coverage was never revisited as tables were added.

**→ T07 (realtime / Durable Objects)**

- `TripRoom` mixes an in-memory `sessions` map with the hibernation registry when broadcasting; after an eviction the two can disagree, and the pending-auth filter applies to one path but not the other.
- The pending-auth timeout is a `setTimeout`, which does not survive hibernation — a socket that outlives an eviction is never closed by the 10-second timer.
- `OfferScheduler` logs and drops a failed wave push (`OfferScheduler.ts:118`) with no retry and no persistent record, so a captain silently never receives the offer.
- Every `wrangler deploy` drops all live WebSockets. That is inherent to Workers, but it should be a documented, deliberate part of the deploy procedure rather than a surprise during an incident.

**→ payments track**

- The webhook is not atomic: `INSERT OR IGNORE INTO wallet_transactions` and the subsequent `UPDATE users SET wallet_balance` are separate statements with no transaction (`payments.ts:176-186`). A failure between them leaves a settled ledger row and a stale balance.
- Failure paths write `wallet_transactions` without an `idempotency_key` (`payments.ts:208, 216, 235, 289`) while success paths use one (`176`, `262`). A replayed failure callback duplicates rows — which directly undermines the replay mitigation in runbook R1.

**→ dispatch track**

- `trips.ts:64-70` — when the captain-radius filter query fails, the error is swallowed and the **unfiltered** list is returned. A degraded D1 therefore causes over-notification of captains, and nothing in the trip record indicates the filter was bypassed.

**→ CI track**

- `.github/workflows/ci.yml` is correctly built — the `Result` aggregators at `76-98`, `169-190` and `225-244` do exit 1, so jobs genuinely go red. The only missing piece is the branch-protection rule, exactly as the file's own comment at `6-9` states.
- `docs/ci/deploy-api.yml` is a good pipeline that has never run because it is not in `.github/workflows/`. This document cannot move it — the GitHub App has no `workflows` permission — so a human must.

**→ T27 (rider / captain parity)**

This track touched both apps while auditing error handling, and they have drifted in ways that matter for telemetry. Each needs reconciling, not fixing in one app:

- **Silent-catch density differs sharply.** Rider `app_state.dart` has 5 silent catches (`102`, `148`, `211`, `283`, `527`); captain `captain_state.dart` has 8 (`203`, `238`, `270`, `682`, `691`, `718`, `783`, `1114`) plus a bare `onError: (_) {}` on the GPS stream at `655`. Neither app contains a single `SnackBar` or `ScaffoldMessenger` call. T27 must decide one error-surfacing contract and apply it to both.
- **The error contract itself differs.** Rider sets `error` and **rethrows** (`app_state.dart:379`); captain sets `error` and does **not** rethrow (`captain_state.dart:972`), and uses a separate `gpsError` field for online-toggle failures (`captain_state.dart:603`). A screen written against one app behaves differently when copied to the other — which, given the duplicated-screen problem T27 owns, is a live hazard.
- **The auth interceptor is duplicated, not shared.** Rider implements it at `app_state.dart:294` and captain at `captain_state.dart:249`, with different catch behaviour. This is the one place a token-handling regression would need patching twice. It belongs in `packages/flutter_shared`.
- **`main.dart` structure diverges** — rider is a `StatefulWidget` with an `AnimatedSwitcher` root gate, captain is a `StatelessWidget` with a ternary. When P1.3 adds `SentryFlutter.init` wrapping `runApp`, it must be applied to both shapes; they cannot share a snippet verbatim.

Confidence: the line references above come from a systematic grep of both state files with surrounding context read, not a full line-by-line read of all 73 KB — `confirmed` for existence and location, `likely` for completeness of the counts.

---

## 10. Open questions

**Q1 — Is the account on the Workers Paid plan?**
Analytics Engine (P1.1), Tail Workers (P1.2) and Logpush all depend on it. Durable Objects are in use, which requires Paid, so this is near-certain — but no file read states the plan, and `docs/COST.md` names no tier. *Recommendation:* confirm before committing to P1.2. If for any reason the account is on Free, P1.1 still works within the 100 K data points/day free allowance at launch volume, and P1.2 must be dropped in favour of inline instrumentation. `needs-check`.

**Q2 — Should the rate limiter fail open or closed?**
Today it fails open silently (`rateLimit.ts:31-34`). Options: (a) keep failing open, add a counter and an alert — availability over enforcement; (b) fail closed on KV error — enforcement over availability, and a KV outage becomes a full outage; (c) fail open but degrade to a stricter in-memory per-isolate limit. *Recommendation:* (a) now, because a silent failure is the actual problem and a counter fixes it cheaply; revisit with T02 before launch. The decision is T02's; the instrumentation is this track's either way.

**Q3 — Who is on-call, and does the team accept that nights are P0-only?**
§6/P1.5 proposes a weekly primary with escalation to the secondary and only four alerts that page overnight. This needs explicit agreement, because the alternative — everything pages — will produce alert fatigue within two weeks and the team will start ignoring pages. *Recommendation:* accept the P0-only night policy and write it on the status page so expectations are external too.

**Q4 — What is the crash-reporting consent model?**
P1.3 recommends gating Sentry behind a first-launch consent flag. That costs some crash coverage — users who decline are invisible. *Recommendation:* gate it. This is an Egyptian product handling location, phone numbers and identity documents; the coverage loss is worth the posture. Needs a product decision on the consent copy in both apps.

**Q5 — Should `logAudit` move off the request hot path?**
P0.5 adds six `logAudit` calls to `trips.ts`, each a D1 write on the trip path — including at completion, which is already the heaviest handler. Options: keep them awaited (simplest, slowest), or move to `ctx.waitUntil` (faster, but a failure after the response is even less visible). *Recommendation:* `waitUntil` for the completion path only, paired with the `audit.write_failed` counter from P1.1 so the reduced visibility is compensated.

**Q6 — Retain logs beyond the Workers Logs window?**
Workers Logs gives 7 days on the Paid plan. If an Egyptian regulatory or payment-dispute requirement needs longer, Logpush to R2 is the mechanism. *Recommendation:* do not enable Logpush until the `?token=` WebSocket parameter is removed (see T02 above) — otherwise JWTs get persisted to object storage. Decide with T08 what the real retention requirement is before spending on it.
