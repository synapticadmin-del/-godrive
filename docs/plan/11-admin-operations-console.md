# 11 — Admin Console & Operations Tooling

> Track: B — Product surface & experience · Reviewer: chat-20260801-1235-66c2 · Date: 2026-08-01 (UTC)
> Base commit reviewed: `697f4347045e67bc488a9c91631d6497ab6511d7`

## 1. Scope

The admin console judged as an **operator's workplace** — the room where captains get
approved, disputes get resolved, supply gets watched and prices get changed. Concretely:
all 10 pages and 11 shared components of `apps/admin`, its four library modules, and the
API surface it is supposed to cover (`routes/admin.ts` plus `companies.ts`,
`intercity.ts`, `promo.ts`, `wallet.ts`, `safety.ts`).

The central question is not "is the React tidy" — it largely is. It is **can a support
agent do their job**, and the answer turns out to depend less on the console's code
quality than on the gap between what the API can do and what any screen exposes.

Explicitly **not** covered, with the owner:

| Out of scope | Owner |
|---|---|
| Whether the admin JWT itself is sound (rotation, revocation) | T01 |
| Server-side RBAC enforcement and IDOR on admin routes | T02 |
| Whether the ledger those screens *would* show is correct | T03 / T04 |
| Fare formula correctness (I cover the *guardrails*, not the maths) | T05 |
| Design-token conformance and the shared visual language | T12 |
| Motion and micro-interaction craft | T13 |
| Arabic content design and RTL as a system | T14 |
| Formal accessibility audit (I flag operator-density issues only) | T15 |
| Realtime transport for a future live console | T07 |

One boundary I deliberately crossed: I cover **captain payout** and **B2B invoicing**
even though T03/T04/T20 own the money mechanics, because in both cases the finding is
*"the API does this and no human can see it"* — which is an operations-tooling failure,
not a money-integrity one. I say what the console must show and leave the correctness of
the underlying numbers to those tracks.

## 2. What I actually read

Downloaded at `697f4347` and read from disk; line numbers are real.

**Admin console — read in full**

| File | Lines | Note |
|---|---|---|
| `apps/admin/src/App.tsx` | 66 | Route table. The definitive list of what exists. |
| `apps/admin/src/lib/api.ts` | 114 | Fetch wrapper, 401→refresh→retry, blob fetch for documents. |
| `apps/admin/src/lib/auth.tsx` | 92 | Token storage and login. |
| `apps/admin/src/lib/csv.ts` | 125 | Export helpers. Read closely for formula injection. |
| `apps/admin/src/lib/escape.ts` | 16 | HTML escaping for Leaflet popups. |
| `apps/admin/src/lib/usePolling.ts` | 56 | The only refresh mechanism in the console. |
| `apps/admin/src/components/layout/TopBar.tsx` | 181 | QuickSearch trigger, Ctrl+K binding. |
| `apps/admin/src/pages/LoginPage.tsx` | 104 | Password-only in practice. |
| `apps/admin/src/pages/UsersPage.tsx` | 74 | The whole user-management surface. |

**Admin console — read the operative paths, skimmed presentation markup**

| File | Lines | What I read |
|---|---|---|
| `apps/admin/src/pages/CaptainVerificationPage.tsx` | 1050 | Modal viewer (150–410), approve/reject handlers (515–600), grouping and pagination (640–1030). |
| `apps/admin/src/pages/PricingPage.tsx` | 760 | Load/save (95–170), estimator (180–200), form fields (410–560), add-city modal (660–760). |
| `apps/admin/src/pages/SettingsPage.tsx` | 665 | Config load/save (45–170), promo CRUD (100–150), form fields (520–600). |
| `apps/admin/src/pages/CaptainsPage.tsx` | 605 | Two-step suspend confirm (69–72, 280–320), row actions (580–600). |
| `apps/admin/src/pages/TripsPage.tsx` | 301 | Fetch + client filter (50–95), columns (95–140), DataTable props (275–284). |
| `apps/admin/src/pages/LiveMapPage.tsx` | 265 | Fetch (38–55), marker layers (100–140), polling (156), error banner (199–205). |
| `apps/admin/src/pages/AnalyticsPage.tsx` | 719 | Range handling (125–185), KPI render (330–400). |
| `apps/admin/src/pages/AuditLogPage.tsx` | 235 | Filters (55–80), columns (77–129), cap banner (215–219). |
| `apps/admin/src/pages/DashboardPage.tsx` | 291 | Fetch + polling (45–110), KPI cards (185–260). |
| `apps/admin/src/components/ui/DataTable.tsx` | 348 | Sort memo (87–98), empty/loading (140–200), header (218–231). |
| `apps/admin/src/components/RejectionReasonModal.tsx` | 226 | Preset reasons (12–49), validation (58–75). |
| `apps/admin/src/components/ui/QuickSearchModal.tsx` | 167 | Confirmed it is now rendered and reachable. |

**API — read to establish what the console *could* expose**

| File | Lines | What I read |
|---|---|---|
| `apps/api/src/routes/admin.ts` | 937 | All 24 handlers. The coverage matrix in §3.2 is built from this file. |
| `apps/api/src/routes/companies.ts` | 239 | All 9 endpoints; the invoice generator at 167–190. |
| `apps/api/src/routes/intercity.ts` | 463 | All 14 endpoints; admin block at 394–460. |
| `apps/api/src/routes/safety.ts` | 291 | SOS handler in full (15–51). |
| `apps/api/src/routes/wallet.ts` | 142 | Payout request (98–135). |
| `apps/api/src/routes/promo.ts` | 108 | Create/deactivate (60–108). |
| `apps/api/src/middleware/auth.ts` | 75 | `requireRole` (67–74). |
| `apps/api/src/lib/audit.ts` | 37 | The whole thing — it is 37 lines and two of them matter. |
| `apps/api/src/lib/schemas.ts` | 331 | `pricingUpdateSchema` (222–230), `systemConfigUpdateSchema` (303–323). |
| `apps/api/src/index.ts` | 372 | The monthly B2B invoice cron (334–370). |

**Migrations read:** `0008` (rejection reason), `0012` (document identity fields),
`0014` (document types), `0015` (captain onboarding), `0016` (system config).

**Docs read for context:** `docs/ROADMAP.md`, `docs/IMPROVEMENTS.md`, `docs/CHECKLIST.md`.

**Not read:** the Leaflet/Recharts vendor behaviour beyond how the pages call them, and
`apps/admin/src/design/*` beyond confirming the token names the pages use — that is T12's
file. There are **no tests** in `apps/admin` (no test runner in `package.json:6-12`),
which is flagged to T23.

## 3. How it works today

### 3.1 The shape of it

A React 19 + Vite SPA, Arabic-only, deployed to Cloudflare Pages. Ten protected pages
behind a token check, all lazy-loaded, all talking to `api.synapticstudio.tech` through
one 114-line fetch wrapper.

```
LoginPage ──(password)──► /auth/login ──► localStorage: token + refresh + user
                                              │
                          ProtectedLayout ────┤  token present? else /login
                                              │
   ┌──────────────┬──────────────┬────────────┴──┬──────────────┬─────────────┐
Dashboard      LiveMap       Captains      Verification      Trips       Analytics
  (poll 8s)    (poll 8s)     (on demand)    (on demand)    (on demand)  (on demand)
                                                     Pricing · Users · Audit · Settings
```

`App.tsx:48-60` is the complete route table. There are ten protected routes. There is no
`/companies`, no `/intercity`, no `/trips/:id`, no `/sos`, no `/payouts`, no `/refunds`.

Session handling is better than the file count suggests. `api()` wraps every call, and on
a 401 it refreshes once and retries the original request, sharing one in-flight promise so
a burst of parallel 401s produces exactly one `/auth/refresh`
(`apps/admin/src/lib/api.ts:47-77`, `:99-107`). Only if the refresh also fails does it
clear the session and redirect. That is the correct pattern and it is correctly
implemented.

Refresh is the *only* live mechanism, though. Two pages poll on an 8-second interval —
Dashboard (`DashboardPage.tsx:49`) and LiveMap (`LiveMapPage.tsx:156`) — and `usePolling`
is well behaved: it clears on `document.hidden` and restarts with an immediate fetch on
visibility restore (`usePolling.ts:34-43`), and clears on unmount (`:51-54`). Every other
page is fetch-once with a manual refresh button. Nothing in the console uses the four
Durable Objects the platform already runs.

### 3.2 The coverage matrix

Every endpoint the platform exposes to an operator, and the screen that reaches it. This
is the backbone of the whole document.

**`routes/admin.ts` — all 24 handlers**

| Endpoint | What it does | UI page |
|---|---|---|
| `GET /admin/stats` | Platform KPIs, today's GMV | Dashboard |
| `GET /admin/live-trips` | Active trips with coordinates | Dashboard, LiveMap |
| `GET /admin/analytics` | Daily GMV/commission, top captains, period deltas | Analytics |
| `GET /admin/audit-log` | Recent audit entries | AuditLog |
| `GET /admin/captains` | Captain list + status filter | Captains |
| `POST /admin/captains/:id/approve` | `approval_status='approved'`, `users.status='active'` | Captains |
| `POST /admin/captains/:id/suspend` | Suspend + force offline | Captains |
| `GET /admin/trips` | Trip list + status filter | Trips |
| `GET /admin/users` | Read-only user list | Users |
| `GET /admin/pricing` | All city pricing rules | Pricing |
| `GET /admin/vehicle-types` | Vehicle categories + multipliers | Pricing (read-only) |
| `PUT /admin/pricing/:city` | Upsert a city's pricing | Pricing |
| `GET /admin/system-config` | Platform settings | Settings |
| `PUT /admin/system-config` | Update platform settings | Settings |
| `GET /admin/search` | Cross-entity search | TopBar (Ctrl+K) |
| `GET /admin/documents` | Verification queue, paged by captain | Verification |
| `POST /admin/documents/:id/review` | Approve/reject a document | Verification |
| `POST /admin/captains/:id/documents/:docId/reject` | Reject with reason | Verification |
| `GET /admin/documents/:id/file` | Serve document from R2 | Verification |
| `GET /admin/online-captains` | Online captains + last GPS | LiveMap |
| `GET /admin/document-types` | List required document types | **NONE** |
| `POST /admin/document-types` | Create a document type | **NONE** |
| `PUT /admin/document-types/:id` | Update a document type | **NONE** |
| `DELETE /admin/document-types/:id` | Soft-delete a document type | **NONE** |

20 of 24 covered. The four uncovered are the document-type catalogue — the thing that
defines what every captain in the country must upload, editable only by curl.

**Everything else the platform can do**

| Area | Endpoints | UI |
|---|---|---|
| **B2B companies** (`companies.ts`) | 9 — create company, list, detail+roster, add employee, patch employee, generate invoice, list invoices, portal, trip pre-auth | **NONE** |
| **Intercity** (`intercity.ts`) | 14 — routes CRUD, schedules, assign captain, manifests, bookings, cancel/refund | **NONE** |
| **Safety / SOS** (`safety.ts`) | 7 — SOS, share token, track, chat, typing | **NONE** |
| **Wallet / payouts** (`wallet.ts`) | 4 — balances, transactions, payout request | **NONE** |
| **Promos** (`promo.ts`) | create, list, deactivate | Settings ✓ |

Counting only what an operator plausibly needs: **roughly 30 operator-relevant endpoints
exist with no screen at all**, spanning two entire business lines (B2B, intercity), the
safety system, and every money operation except promos.

### 3.3 The verification workflow, which is the console's best work

This is the highest-volume operator task and the page that has clearly had the most care
spent on it. The document viewer is not the `<img>` tag I expected: `ZoomablePreviewModal`
gives 0.5×–5× zoom with `+`/`-` keys (`CaptainVerificationPage.tsx:206-213`), drag-to-pan
above 1× (`:237-252`), reset on `0` (`:201-204`), and prev/next document navigation on the
arrow keys (`:215-221`). PDFs render in an iframe (`:388-391`).

Crucially, the identity fields migration 0012 added are shown **next to the image** — both
in the card grid (`:914-957`) and as a strip inside the modal itself (`:329-369`), with a
traffic-light chip on expiry. That is exactly the comparison affordance the job needs.

The image loads correctly too, and non-obviously so: `/admin/documents/:id/file` requires
an `Authorization` header, which a bare `<img src>` cannot send, so `fetchDocumentBlobUrl`
fetches with the header and hands back an object URL
(`apps/admin/src/lib/api.ts:28-34`), revoked on unmount (`CaptainVerificationPage.tsx:123-126`).

Rejection is mandatory-reason: five Arabic presets plus a custom textarea, and submitting
with an empty custom reason is blocked (`RejectionReasonModal.tsx:12-49`, `:71-73`).

And — worth recording because the brief asked me to hunt for them — I found **no
optimistic-UI lies on this page**. Every mutation awaits the API and then refetches via
`load()` (`:529`, `:549`, `:595`). The class of bug PR #40 fixed is genuinely fixed here.

What it costs an agent, though, is measured in §4: no vehicle details, no bulk across
captains, a serial approve loop, and no "next captain".

### 3.4 Where the data comes from, and how much of it

Every list endpoint is hard-capped and every filter above it is client-side.

| Page | Server query | Cap | Client-side filtering | Cap disclosed? |
|---|---|---|---|---|
| Trips | `ORDER BY created_at DESC LIMIT 200` (`admin.ts:320`) | 200 | text search + date range (`TripsPage.tsx:65-91`) | **no** |
| Users | `LIMIT 200` (`admin.ts:328-330`) | 200 | none at all | **no** |
| Audit | `min(limit, 500)` (`admin.ts:220-226`) | 500 | action + text (`AuditLogPage.tsx:62-75`) | yes (`:215-219`) |
| LiveMap | `LIMIT 200` ×2 (`admin.ts:934`, `:53-61`) | 200 each | mode toggle | **no** |
| Verification | server-paged by captain, 10/page | — | none | n/a |

`DataTable` sorting is a `useMemo` over the `data` prop (`DataTable.tsx:87-98`), so sorting
sorts the fetched page, never the table. No handler accepts a sort parameter.

## 4. Findings

Severity per `board/TEMPLATE.md`. Confidence: **confirmed** = read the code;
**likely** = strong inference; **needs-check** = unverified.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-11-01 | S1 | There is no trip detail view. Investigation is a table row and two raw UUIDs — no timeline, bids, GPS path, chat, or payment history is reachable from any screen | `apps/admin/src/pages/TripsPage.tsx:275-284` (no `onRowClick`, though `DataTable.tsx:27` supports it); `apps/api/src/routes/admin.ts:312-324` (`SELECT * FROM trips`, no joins) | The core support workflow — "customer complains, here is the trip id" — cannot be performed. Every dispute is resolved by guesswork or by a developer running SQL. | confirmed |
| F-11-02 | S1 | An SOS alert has no admin surface of any kind: no page, and no endpoint to list, view or close one | `apps/api/src/routes/safety.ts:15-51` writes `sos_alerts` and pushes FCM to admins; zero references to `sos_alerts` in `apps/api/src/routes/admin.ts` (937 lines) | A rider presses the panic button and the only trace an operator ever sees is a phone notification. Dismiss it and the alert is unrecoverable without D1 access. No queue, no acknowledgement, no audit of response time. | confirmed |
| F-11-03 | S1 | Trip and user lists silently truncate to the 200 most recent rows while presenting a search box that only filters those 200 | `apps/api/src/routes/admin.ts:320`, `:328-330`; `apps/admin/src/pages/TripsPage.tsx:65-91`; contrast `AuditLogPage.tsx:215-219` which *does* warn | An agent searching a trip id from last week gets "لا توجد رحلات مطابقة للبحث" and reasonably concludes the trip does not exist. A tool that lies about absence is worse than one that refuses to answer. | confirmed |
| F-11-04 | S1 | Captain payout requests are unactionable: money leaves the balance into a `pending` row with no endpoint and no screen to approve, settle or reject it | `apps/api/src/routes/wallet.ts:98-135`; no payout handler anywhere in `admin.ts` | Every captain who taps withdraw has their earnings frozen indefinitely. There is no queue for finance to work and no way to reverse it from the product. | confirmed |
| F-11-05 | S1 | The entire B2B line has no console. Companies cannot be created, credit limits cannot be set, and the monthly invoice cron produces invoices no human can see, send, or mark paid | `apps/api/src/routes/companies.ts:68` (9 admin endpoints), `:167-190`; `apps/api/src/index.ts:334-370` (cron writes `status='issued'`, notifies nobody) | A revenue line ships every month into a table nobody can read. There is also no status-change endpoint at all — `status` is hardcoded `'active'` at creation (`companies.ts:77`) and no endpoint marks an invoice paid. | confirmed |
| F-11-06 | S1 | One undifferentiated `admin` role. A junior verification agent can change national pricing and commission | `apps/api/src/middleware/auth.ts:67-74`; `apps/api/src/routes/admin.ts:11` (`requireRole("admin")` blanket) | The highest-volume, lowest-trust role holds the most destructive powers in the platform. `requireRole` is variadic and already supports multiple roles — nothing uses that. | confirmed |
| F-11-07 | S2 | Rider accounts cannot be banned, deleted, merged, or have a phone corrected — no endpoint exists, only captains have lifecycle actions | `apps/api/src/routes/admin.ts:326-331` (users is `SELECT`-only); suspend exists only for captains (`:289-309`) | Abuse response and any GDPR/erasure request require a developer with D1 access. `UsersPage.tsx` is 74 lines because there is nothing for it to do. | confirmed |
| F-11-08 | S2 | Audit entries record the new value only — no before-value is captured, on any change | `apps/api/src/routes/admin.ts:402-409` (`payload: body`), `:522-530`; the prior row *is* read at `:355` and simply not passed | "Who changed the commission rate last Tuesday, and what was it before?" is unanswerable. Reconstruction requires an unbroken chain of prior audit rows, which §F-11-09 shows is not guaranteed. | confirmed |
| F-11-09 | S2 | Audit writes fail silently — the helper swallows every error and the request succeeds anyway | `apps/api/src/lib/audit.ts:33-36` | The audit log is the only record of destructive admin actions, and it is best-effort with no counter. A D1 hiccup during an incident erases exactly the evidence the incident needs. | confirmed |
| F-11-10 | S2 | Pricing has no guardrails against catastrophic-but-in-range values: `base_fare = 0` and `commission_rate = 1.0` (100%) both pass client, Zod and DB | `apps/api/src/lib/schemas.ts:224` (`min(0)`), `:229` (`max(1)`); `apps/admin/src/pages/PricingPage.tsx:419-427` (no `min`/`max` on the fare inputs) | A commission of 1.0 pays captains nothing on every trip in a city; a base fare of 0 undercharges every rider. Both take effect on live traffic with no confirmation step and no delta warning. | confirmed |
| F-11-11 | S2 | Pricing writes are last-write-wins with no optimistic locking | `apps/api/src/routes/admin.ts:355` (read), `:376` (`UPDATE ... WHERE city = ?`, no precondition) | Two operators editing Cairo concurrently: the second silently erases the first, and both see a success toast. Detectable afterwards in the audit log, never prevented. | confirmed |
| F-11-12 | S2 | Switching cities on the pricing page silently discards unsaved edits with no warning | `apps/admin/src/pages/PricingPage.tsx:356`; no `beforeunload` or dirty-state tracking in either config page | An operator halfway through re-pricing Alexandria clicks Cairo to check a number and loses the lot, with no toast and nothing to undo to. | confirmed |
| F-11-13 | S2 | The live map is capped at 200 captains and 200 trips with no indication, so beyond 200 online it shows a silent subset | `apps/api/src/routes/admin.ts:934`, `:53-61`; `apps/admin/src/pages/LiveMapPage.tsx:38-55` | At 500 online captains the operator is looking at 40% of the fleet and believes it is all of it. Supply decisions get made off that picture. | confirmed |
| F-11-14 | S2 | Suspending a captain — an income-ending action — captures no reason, while rejecting a single document requires one | `apps/admin/src/pages/CaptainsPage.tsx:288` (POST with no body); contrast `RejectionReasonModal.tsx:58-75` | The captain is told nothing, the next agent cannot see why, and appeals are unresolvable. The reason-capture UI already exists 400 lines away. | confirmed |
| F-11-15 | S2 | Column sorting sorts only the fetched page, presenting itself as sorting the table | `apps/admin/src/components/ui/DataTable.tsx:87-98`, `:218-231`; no handler accepts a sort parameter (`admin.ts:320` is a fixed `ORDER BY created_at DESC`) | "Sort by highest fare" gives the highest fare *among the last 200 trips*. An operator hunting anomalies is systematically shown the wrong rows. | confirmed |
| F-11-16 | S2 | The audit log cannot be filtered by date, and actor is a raw UUID | `apps/admin/src/pages/AuditLogPage.tsx:57-75` (action + text only, no date input); `:77-129` (columns) | With a 500-row cap and no date bound, any investigation older than the last 500 actions is impossible. Searching by person requires knowing their UUID. | confirmed |
| F-11-17 | S2 | The `payload` column — the only place a change's content is recorded — is fetched but never rendered | `apps/admin/src/pages/AuditLogPage.tsx:139-141` (in CSV export), `:77-129` (absent from columns) | The audit page shows that something changed and hides what it changed to. The data is already on the client. | confirmed |
| F-11-18 | S2 | Bulk approve runs serially and aborts on the first failure without reporting which documents succeeded | `apps/admin/src/pages/CaptainVerificationPage.tsx:541-546` (`for...of` with `await`), `:552` (generic error toast) | N sequential round-trips per captain, and a mid-loop failure leaves a partially approved captain with no indication of where it stopped. | confirmed |
| F-11-19 | S2 | The document-type catalogue has full CRUD and no UI | `apps/api/src/routes/admin.ts:691`, `:698`, `:749`, `:797` | What every captain in the country must upload can only be changed with curl. Adding a document type for a new city is an engineering task. | confirmed |
| F-11-20 | S3 | The verification page omits vehicle details, city, account age and prior-rejection history, forcing a cross-reference to Captains for every captain | `apps/admin/src/pages/CaptainVerificationPage.tsx:35-45` (interface), `apps/api/src/routes/admin.ts:667-677` (query joins `users` only) | The highest-volume task requires two tabs. The join is one line of SQL. | confirmed |
| F-11-21 | S3 | Approving documents and approving a captain are two different code paths with different effects — the document path never sets `users.status='active'` | `apps/api/src/routes/admin.ts:838-852` (document path) vs `:261-287` (captain path) | A captain approved through the verification queue can end up with `approval_status='approved'` and `users.status='pending'`. Which of the two screens the agent used determines the captain's real state. | confirmed |
| F-11-22 | S3 | Nothing notifies a captain of approval or rejection | `apps/api/src/routes/admin.ts:261-287`, `:821-864` — no `pushToUser` in either handler | The captain discovers the outcome by reopening the app and guessing. The platform has FCM wired and used elsewhere. | confirmed |
| F-11-23 | S3 | Dashboard KPIs run unbounded `GROUP BY` scans over `users` and `trips` on an 8-second poll | `apps/api/src/routes/admin.ts:14-16`, `:18-20`; `apps/admin/src/pages/DashboardPage.tsx:49` | Two full table scans every 8 seconds per open dashboard tab, growing linearly with platform history forever. | confirmed |
| F-11-24 | S3 | There is no rejection *history* — only the current `rejection_reason` of a document in `rejected` state | `apps/admin/src/pages/CaptainVerificationPage.tsx:960-967` | A captain on their fourth resubmission looks identical to a first-time applicant. Repeat-fraud patterns are invisible. | confirmed |
| F-11-25 | S3 | `reviewed_by` / `reviewed_at` are stored and never displayed | `apps/api/src/routes/admin.ts:829-836`; absent from the UI columns | No agent can see who last touched a document, so mistakes cannot be traced or coached. | confirmed |
| F-11-26 | S3 | A failed refresh after a successful save leaves a green success banner and a red error banner on screen together | `apps/admin/src/pages/PricingPage.tsx:136-139`, `:165-168` (catch sets `error`, never clears `message`) | The operator cannot tell whether the change landed. It did — but the screen is arguing with itself. | confirmed |
| F-11-27 | S3 | Vehicle-type load failure is swallowed and the fare estimator silently falls back to multiplier 1 | `apps/admin/src/pages/PricingPage.tsx:103-108`, `:187`, `:266` | The estimator quietly shows wrong numbers for every non-economy tier, and the operator prices against them. | confirmed |
| F-11-28 | S3 | RTL tab order is not managed: DOM order drives keyboard traversal against the visual reading direction | `apps/admin/src/pages/PricingPage.tsx:227`, `apps/admin/src/pages/SettingsPage.tsx:193` (`dir="rtl"` with no `tabIndex` strategy) | Keyboard-driven form entry, the fastest way to work these screens all day, moves the focus ring in an order that does not match the layout. | likely |
| F-11-29 | S3 | Tokens and the refresh token live in `localStorage`, readable by any XSS | `apps/admin/src/lib/auth.tsx:46-48`, `:68-70` | An XSS anywhere in the console yields a durable admin session. High blast radius given F-11-06 (one role, all powers). | confirmed |
| F-11-30 | S4 | Strings are hardcoded Arabic inline with no i18n layer | no i18n dependency in `apps/admin/package.json:13-19`; e.g. `AuditLogPage.tsx:217` | Correct default for Egyptian operators, but there is no path to an English fallback for contractors or vendor support, and no string catalogue to review. | confirmed |
| F-11-31 | S4 | The admin auth context can request an OTP with `role: "admin"`, though no screen calls it | `apps/admin/src/lib/auth.tsx:52-57`; `LoginPage.tsx:8`, `:21` use password only | Dead code today, but it is a self-service admin-account path sitting in the shipped bundle. Flagged to T01, which found the OTP routes still mounted. | confirmed |
| F-11-32 | S4 | Neither Dashboard nor Users offers a manual refresh or retry after an error | `apps/admin/src/pages/DashboardPage.tsx:68-72`; `apps/admin/src/pages/UsersPage.tsx:26` | A transient failure means a full page reload. Minor, but it is the dashboard. | confirmed |

### 4.1 What the S1s actually mean

**F-11-01 — the console cannot answer the only question support is ever asked.**

A rider calls: *"I was charged 180 pounds for a trip that never happened."* The agent has
a trip id. Here is everything they can do with it.

They open Trips, paste the id into the search box, and — if the trip is among the 200 most
recent in the entire platform — they get a row. The row shows status, city, pickup and
dropoff addresses, four fare fields, payment method, created-at, and two UUIDs. They click
it. Nothing happens: `DataTable` accepts an `onRowClick` (`DataTable.tsx:27`) and
`TripsPage` does not pass one (`TripsPage.tsx:275-284`).

That is the end of the investigation. Not "harder than it should be" — the end. The
following exist in D1 and are reachable from no admin endpoint:

| What the agent needs | Where it lives | Admin endpoint |
|---|---|---|
| Status timeline (when it went `assigned` → `arrived` → `in_progress`) | `trip_events` | none |
| Which captains were offered it, who bid what | `trip_bids` | none |
| Where the car actually drove | `trip_path_points` | none |
| What rider and captain said to each other | chat table (`safety.ts:150-200`) | none |
| What was charged, refunded, or credited | `wallet_transactions`, `payment_intentions` | none |
| Who the rider and captain *are* — name, phone | `users`, joined nowhere | none |

`GET /admin/trips` is `SELECT * FROM trips` with a status filter and a `LIMIT`
(`admin.ts:312-324`). No joins. So the agent cannot even phone the captain without
copying a UUID into the Ctrl+K search and hoping.

This is the single highest-value missing thing in the product, and the brief already
suspected as much. It is specified in §6 P0.1 with a wireframe, because "add a detail
page" is not a sufficient instruction for a screen this load-bearing.

**F-11-02 — the panic button rings a phone and then nothing.**

`POST /safety/sos` does four things (`safety.ts:15-51`): inserts an `sos_alerts` row with
`status='open'`, the coordinates and the trip id; selects every admin user; sends each one
an FCM push titled *"إنذار طوارئ جديد"*; writes an audit entry.

Now search the 937 lines of `admin.ts` for `sos_alerts`. There are no matches. There is no
`GET /admin/sos`, no page, no counter in the TopBar, no row on the dashboard, nothing on
the live map. The alert has `status='open'` and **no endpoint can ever change it**, so the
column is permanently `'open'` for every alert ever raised.

The operational consequence is worth stating plainly. The entire safety-response
capability of this platform is: an admin happens to be holding an unlocked phone, happens
to have the app installed with notifications granted, and happens not to swipe the
notification away. There is no queue to work, no acknowledgement, no assignment, no
resolution note, and no way to ask "how many SOS alerts did we get last month and how fast
did we answer them?" A dismissed push is an erased emergency.

The product ships `safety-sos` in its advertised feature list (`apps/api/src/index.ts:92`).

**F-11-03 — the tables lie about absence, which is worse than refusing to answer.**

`GET /admin/trips` returns at most 200 rows, always the newest
(`admin.ts:320`). `TripsPage` then applies the agent's text search and date range **in the
browser**, over those 200 rows (`TripsPage.tsx:65-91`).

At any real volume, "the 200 most recent trips" is a window of minutes. So an agent
searching for a trip from yesterday sees the empty-state message *"لا توجد رحلات مطابقة
للبحث"* — "no trips matching the search". The trip exists. The console says it does not.

The same is true of Users (`admin.ts:328-330`, 200 rows, and no search box at all —
`UsersPage.tsx` is 74 lines) and the live map (`admin.ts:934`).

What makes this a finding rather than a known limitation is that **the codebase already
knows how to handle it**. `AuditLogPage` renders a warning banner the moment the result
hits the cap: *"يعرض أحدث ٥٠٠ سجل فقط. السجلات الأقدم غير معروضة."*
(`AuditLogPage.tsx:215-219`). One page tells the truth about its cap. The two pages where
a false negative does real damage do not.

**F-11-04 and F-11-05 — two money flows with no human in the loop.**

*Payouts.* A captain taps withdraw. `POST /captain/wallet/payout`
(`apps/api/src/routes/wallet.ts:98-135`) debits `wallet_balance` immediately and writes a
`wallet_transactions` row with `status='pending'` whose destination account is free text in
a `note` column. Then: there is no admin endpoint that lists pending payouts, none that
approves one, none that rejects one, and no screen for any of it. The row's status can
never change, because nothing can change it. Every payout request is a captain's earnings
moved from "spendable" to "gone", permanently, by design. (T03 and T04 both flagged the
debit itself; the operations finding is that even a correct debit would be unrecoverable
because no queue exists to work it.)

*B2B.* `companies.ts` has nine endpoints behind `requireRole("admin")`
(`companies.ts:68`) — create a company, list them, view one with its employee roster, add
and patch employees with spend limits, generate an invoice, list invoices. None of them
has a screen. Meanwhile a cron fires on the 1st of every month
(`apps/api/src/index.ts:334-370`), sums each active company's billed trips, inserts a
`company_invoices` row with `status='issued'`, and clears `billed_to_company`. It notifies
nobody. There is no endpoint to send that invoice and no endpoint to mark it paid — the
status is written once at creation (`companies.ts:186`) and never updated by anything.

So the B2B business runs like this: a developer inserts a company by hand, employees are
bound by curl, trips accumulate, an invoice materialises in a table on the 1st, and it sits
there. Accounts receivable is a `SELECT` statement somebody has to remember to run.

**F-11-06 — the person most likely to make a mistake has the most dangerous button.**

`requireRole` is variadic and perfectly capable of expressing a role hierarchy:

```ts
// apps/api/src/middleware/auth.ts:67-74
export function requireRole(...roles: AuthUser["role"][]) { ... }
```

It is used exactly once for the admin surface, as a blanket guard on everything:

```ts
// apps/api/src/routes/admin.ts:11
adminRoutes.use("*", authMiddleware, requireRole("admin"));
```

There is one `admin` role. A verification agent hired to look at ID photos all day can
open Pricing and set Cairo's commission to 100%, or Settings and disable auto-assign for
the entire country. The console offers no read-only mode, no per-page gating, and no
second-person approval on anything. Given F-11-10 (no value guardrails), F-11-11 (no
locking) and F-11-08 (no before-values in the audit trail), a single mistyped field by the
newest employee is both catastrophic and hard to reconstruct.

This is the UI half of a finding T02 owns from the API side; §9 hands it over with the
specific affordances a role split would need.

### 4.2 The S2s in one pass

**Audit is the weakest link in a console full of destructive actions.** Three findings
compound: the payload records only the new value (F-11-08), the write is best-effort and
silently swallowed (`audit.ts:33-36`, F-11-09), and the one column that would show *what*
changed is fetched and never rendered (F-11-17). Add no date filter and a UUID for the
actor (F-11-16) and the audit log is, in practice, a list of verbs.

**Pricing has no blast-radius controls.** The Zod bounds are real and sensible —
`baseFare` 0–1000, `commissionRate` 0–1 (`schemas.ts:224`, `:229`) — but the dangerous
values are *inside* the bounds. `commissionRate: 1.0` is valid and pays captains nothing;
`baseFare: 0` is valid and undercharges every rider in the city. The commission input at
least clamps client-side (`PricingPage.tsx:522-528`); the four fare inputs carry no
`min`/`max` at all (`:419-427`, `:440-445`, `:460-467`). Nothing anywhere asks "you are
changing the base fare from 12 to 120 — are you sure?", nothing locks concurrent edits
(F-11-11), and switching city loses your work without a word (F-11-12).

**The verification queue is good but slow in exactly the places volume hurts.** No vehicle
details on the page (F-11-20) means two tabs per captain; the bulk approve is a `for...of`
with an `await` inside (F-11-18) so a 6-document captain costs 6 sequential round-trips and
aborts halfway on any failure; and there is no "next captain" — after every decision
`load()` refetches and the agent hunts for their place again. None of these is hard. Their
combined cost is the throughput of the team doing the platform's highest-volume job.

**Two approve paths that do different things** (F-11-21) is the kind of bug that produces
unreproducible support tickets: `/documents/:id/review` auto-promotes
`captains.approval_status` when the last document is approved (`admin.ts:838-852`) but
never touches `users.status`, while `/captains/:id/approve` sets both (`:261-287`). Which
screen the agent used silently determines whether the captain can actually work.

### 4.3 What is genuinely well built

A review that only lists faults misrepresents this codebase, and three of these are
directly relevant to findings other tracks might otherwise re-raise.

- **CSV export is careful in ways most exports are not.** `escapeCsvField` guards against
  spreadsheet formula injection by prefixing an apostrophe to any field starting with
  `=`, `+`, `-`, `@`, tab or CR (`csv.ts:39-40`) — the brief asked me to check this and it
  is handled. It also prepends a UTF-8 BOM so Excel does not mojibake Arabic
  (`:110-111`), and deliberately exports Latin digits and ISO timestamps rather than the
  `ar-EG` display formatting, because Arabic-Indic numerals do not parse as numbers in a
  spreadsheet (`:80-85`, `:60-78`). The comment explaining the UTC-vs-local timestamp trap
  (`:50-58`) is correct and non-obvious.
- **`escapeHtml` exists for the right reason.** Leaflet's `divIcon({html})` and
  `bindPopup()` do not sanitise, and the map interpolates captain names and plates into
  template strings; `escape.ts:9-16` is applied to those values.
- **Session refresh is textbook.** 401 → single-flight refresh → retry the original
  request → tear down only if the retry also 401s (`api.ts:47-77`, `:99-107`). Worth
  noting because T01 identified refresh single-flighting as an *outstanding* requirement
  for the Flutter clients — the admin console already has it, and it is the reference
  implementation.
- **`usePolling` respects the browser.** Clears on `document.hidden`, refetches
  immediately on visibility restore, clears on unmount (`usePolling.ts:34-43`, `:51-54`).
  No background-tab polling anywhere in the console.
- **The two-step suspend confirm** with a 3-second auto-revert
  (`CaptainsPage.tsx:69-72`, `:282-315`) is a nicer pattern than a modal for a row action.
- **The document viewer** genuinely supports the job (§3.3), and **PR #40's optimistic-UI
  class of bug is fixed** on the verification page — every mutation awaits and refetches.
- **QuickSearch is now live**, wired to Ctrl+K with a visible affordance and a mobile
  fallback (`TopBar.tsx:52-77`, `:177`), against a real backend that searches captains,
  riders and trips with `LIKE ... ESCAPE` (`admin.ts:551-609`). The code comment at
  `admin.ts:546-550` records that both ends were previously dead; that is no longer true
  and should not be re-reported as a gap.

## 5. Benchmark gap

**Uber — the trip timeline is the backbone of support.** Uber's internal tooling is
organised around a single trip view that assembles every event, state change, payment,
and communication for one trip on one page, so that an agent can answer a question without
knowing which subsystem produced the answer. The support workflow is *"paste the trip id,
read the story"*. Marked **confident** on the mechanism (it is visible in how Uber support
resolves disputes and widely described), **assumed** on internal specifics.

Synaptic Go sits at the opposite pole: the data exists in six tables and the console joins
none of them (F-11-01). This is the single largest capability gap in the track, and
closing it is P0.1.

**Careem — role-scoped regional consoles and bulk onboarding.** Careem's operations are
organised by city with role-scoped access, so a Cairo supply agent cannot change Alexandria
pricing and a verification agent cannot change pricing at all; captain onboarding runs as a
pipeline with bulk actions and queue prioritisation. Marked **confident** on
role-scoping-by-region as a pattern in regional ride-hailing ops, **assumed** on specifics.

Synaptic Go has one global `admin` role (F-11-06) and no city scoping anywhere in the
console — `PUT /admin/pricing/:city` is available to every admin for every city. Onboarding
is one captain at a time, with a serial approve loop (F-11-18).

**Generic best practice — every destructive action captures a reason and lands in an
immutable audit log.** Synaptic Go is half-right in an interesting way: rejecting *one
document* requires a reason from a curated list (`RejectionReasonModal.tsx:12-49`), while
*suspending the captain entirely* captures nothing (F-11-14). The pattern is understood and
was applied to the smaller action. The audit log itself is append-only in shape but
best-effort in practice (F-11-09) and records no before-state (F-11-08).

**Where the console is at or above the benchmark:** the CSV hygiene in §4.3 is better than
most internal tools ship, the document viewer with an adjacent identity strip is a genuinely
good verification affordance, and the polling discipline is correct. The gap is not craft.
It is coverage: **~30 operator-relevant endpoints with no screen**, and two business lines
running with no console at all.

## 6. Improvement plan

Ordered. P0 is what the business needs before it can operate on real traffic.

### P0.1 — The unified trip timeline (`/trips/:id`)

- **Goal** — an agent pastes a trip id and can answer any question about that trip in one
  screen, without a developer and without SQL.
- **Design** — one new route, one new aggregate endpoint. `GET /admin/trips/:id/full`
  returns the trip joined to rider and captain identities plus five collections in one
  round-trip: `events`, `bids`, `path` (decimated server-side to ≤200 points),
  `messages`, `ledger` (wallet transactions and payment intentions for the trip). The page
  renders a fixed header, a left timeline rail, and a right context column. Everything is
  read-only in v1 except the three actions in the header — refund, force-complete, and
  contact — each of which is reason-gated and audited (P0.5).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ← الرحلات    trip_9f3a…c21   [مكتملة]   القاهرة   ٢٠٢٦-٠٨-٠١ ١٤:٣٢          │
│ الراكب: منى س. ٠١٠١٢٣٤٥٦٧٨ →  الكابتن: أحمد ر. ٠١٠٩٨٧٦٥٤٣٢ · نيسان صني ٧٨٩ │
│                          [ استرداد ]  [ إنهاء إجباري ]  [ تواصل ]  [ CSV ]   │
├───────────────────────────────┬──────────────────────────────────────────────┤
│  الخط الزمني                  │  المسار                                      │
│                               │  ┌────────────────────────────────────────┐  │
│  ●  ١٤:٣٢:٠٧  إنشاء           │  │           [ خريطة المسار الفعلي ]      │  │
│  │              ١٢٠ ج.م تقدير  │  │   ● التقاط   ▲ الكابتن   ■ الوصول      │  │
│  ●  ١٤:٣٢:٠٩  عرض على ٣ كباتن │  │   ١٤٧ نقطة · ٨٫٢ كم · ٢٣ دقيقة         │  │
│  │              الموجة ١/٤     │  └────────────────────────────────────────┘  │
│  ●  ١٤:٣٢:٤١  مزايدة          │                                              │
│  │              أحمد ر. ١٣٥    │  المال                                       │
│  ●  ١٤:٣٣:٠٢  قبول            │  ┌────────────────────────────────────────┐  │
│  │              ١٣٥ ج.م        │  │ تقدير            ١٢٠٫٠٠                │  │
│  ●  ١٤:٤١:١٨  وصول الكابتن    │  │ سعر متفق عليه    ١٣٥٫٠٠                │  │
│  ●  ١٤:٤٣:٥٠  بدء الرحلة      │  │ نهائي            ١٣٥٫٠٠                │  │
│  ●  ١٥:٠٦:٣٣  اكتمال          │  │ عمولة (٢٠٪)      ٢٧٫٠٠                 │  │
│  │              ١٣٥ ج.م        │  │ صافي الكابتن     ١٠٨٫٠٠                │  │
│  ●  ١٥:٠٦:٣٤  خصم من المحفظة  │  ├────────────────────────────────────────┤  │
│                 ١٣٥ ج.م ✓     │  │ txn_44b1  debit  rider   -١٣٥  ✓      │  │
│                               │  │ txn_44b2  credit captain +١٠٨  ✓      │  │
│  [ عرض الأحداث الخام (JSON) ] │  │ txn_44b3  credit platform  +٢٧  ✓      │  │
│                               │  └────────────────────────────────────────┘  │
│                               │                                              │
│                               │  المحادثة                        ٤ رسائل ⌄  │
│                               │  ١٤:٣٦ كابتن: أنا عند البوابة               │
│                               │  ١٤:٣٧ راكب:  نازلة حالاً                    │
└───────────────────────────────┴──────────────────────────────────────────────┘
```

  Timeline rows are built from `trip_events` and enriched inline with the bid/payment rows
  that share a timestamp, so the agent reads one narrative rather than correlating five
  tables. Every row is expandable to its raw JSON — the escape hatch that stops the next
  "I need a developer" ticket. The money panel is the single place a fare dispute is
  settled, and it shows the ledger rows, not just the trip columns, so a failed debit is
  visible as a failed debit.
- **Files to change** — new `apps/admin/src/pages/TripDetailPage.tsx`; route in
  `apps/admin/src/App.tsx:54`; `onRowClick` in `apps/admin/src/pages/TripsPage.tsx:275-284`;
  new handler in `apps/api/src/routes/admin.ts`.
- **DB** — none. Every table already exists. Add an index on `trip_events(trip_id)` and
  `trip_path_points(trip_id, recorded_at)` if T08 has not (coordinate — T08 owns it).
- **API contract** — `GET /admin/trips/:id/full` →
  `{trip, rider, captain, events[], bids[], path[], messages[], ledger[]}`.
- **Effort** — L (endpoint M, page M–L).
- **Risk** — the aggregate query is heavy on a hot table; bound `path` server-side and
  lazy-load `messages` behind the accordion. Rollback is removing the route.
- **Acceptance criteria** — given only a trip id, an agent can state who drove, the route
  taken, what was charged, whether the rider was actually debited, and what the two parties
  said, without leaving the page or asking anyone.
- **Tests** — a fixture trip exercising every collection; an integration test asserting the
  endpoint returns all five arrays; a smoke test that the page renders with each array empty.

### P0.2 — The SOS console (`/safety`)

- **Goal** — an emergency is a queue item that must be acknowledged and closed, not a
  notification that can be swiped away.
- **Design** — three endpoints (`GET /admin/sos` with a status filter,
  `POST /admin/sos/:id/ack`, `POST /admin/sos/:id/resolve` taking a mandatory outcome note)
  and a page that is the console's only true realtime surface: an unmissable red banner in
  the persistent `Layout` whenever `open` count > 0, so it is visible from every page. Poll
  at 5 s in v1; move to the existing DO infrastructure later (§9, T07). Each alert links
  straight to P0.1's trip timeline.
- **Files to change** — new `apps/admin/src/pages/SafetyPage.tsx`; banner in
  `apps/admin/src/components/layout/Layout.tsx:1-23`; route in `App.tsx`; three handlers in
  `apps/api/src/routes/admin.ts`.
- **DB** — migration adding `acknowledged_at`, `acknowledged_by`, `resolved_at`,
  `resolved_by`, `resolution_note` to `sos_alerts`. The `status` column already exists and
  is currently write-once.
- **API contract** — `GET /admin/sos?status=open|all` → `{alerts:[{id, user, role, trip_id,
  lat, lng, reason, status, created_at, acknowledged_at, ...}]}`; the two POSTs return the
  updated alert.
- **Effort** — M.
- **Risk** — an alert banner that fires spuriously gets ignored, which is worse than none;
  keep the trigger strictly `status='open'`.
- **Acceptance criteria** — an SOS raised in staging appears in the console within 5 s and
  on every page; it cannot leave the list without an operator id and a resolution note; the
  median acknowledge time is measurable (§8).
- **Tests** — an end-to-end test from `POST /safety/sos` to the alert appearing, being
  acknowledged, and being resolved.

### P0.3 — Tell the truth about result caps, then fix them

- **Goal** — the console never reports absence it has not actually verified.
- **Design** — two steps. **(a) Immediately:** copy the AuditLog cap banner
  (`AuditLogPage.tsx:215-219`) to Trips, Users and LiveMap. One component, three usages,
  an afternoon — and it converts a silent lie into a visible limitation. **(b) Properly:**
  move filtering server-side. `GET /admin/trips` gains `q`, `from`, `to`, `city`, `status`,
  `sort`, `dir`, `page`, `pageSize`, returns `{rows, total, page}`; `DataTable` takes an
  optional `serverPagination` prop and delegates sort and page to the caller. Same for
  `/admin/users` (which also needs a search box at all) and `/admin/audit-log` (which needs
  `from`/`to` and an actor join — F-11-16).
- **Files to change** — `apps/api/src/routes/admin.ts:312-331`, `:219-227`;
  `apps/admin/src/components/ui/DataTable.tsx:87-98`, `:218-231`;
  `apps/admin/src/pages/TripsPage.tsx:50-95`; `UsersPage.tsx` (rewrite onto `DataTable`);
  `AuditLogPage.tsx:55-80`.
- **DB** — indices on `trips(created_at)`, `trips(city, status)`, `audit_log(created_at)`,
  `audit_log(actor_id)` — coordinate with T08.
- **API contract** — additive query params; response shape changes from a bare array to
  `{rows, total}`.
- **Effort** — M.
- **Risk** — an unindexed `LIKE '%q%'` over a large `trips` table is slow; require a
  minimum query length and prefer id-prefix and phone-exact matching over free text.
- **Acceptance criteria** — searching a 6-month-old trip id returns it; every capped view
  states its cap; sorting reorders the whole result set, not the page.

### P0.4 — Guardrails on live pricing and config

- **Goal** — a typo cannot reprice a city, and two operators cannot silently overwrite each
  other.
- **Design** — four changes. **(a)** Tighten the schema where the dangerous values live
  inside the valid range: `commissionRate` to `max(0.5)`, `baseFare` to `min(1)`, `perKm`
  to `min(0.5)` — anything beyond needs a deliberate override flag. **(b)** A diff
  confirmation step: on save, show old → new for every changed field and require a typed
  confirmation when any value moves more than ±50%. **(c)** Optimistic locking: return
  `updated_at` from `GET /admin/pricing` and require it on `PUT`; reject with 409 and show
  "another operator changed this — reload" (F-11-11). **(d)** A dirty-state guard on both
  config pages: block city switching and `beforeunload` while the form is dirty (F-11-12).
  Also add `min`/`max` to the four unguarded fare inputs and clear `message` in the catch
  blocks so success and error can never render together (F-11-26).
- **Files to change** — `apps/api/src/lib/schemas.ts:222-230`, `:303-323`;
  `apps/api/src/routes/admin.ts:349-415`, `:488-543`;
  `apps/admin/src/pages/PricingPage.tsx:123-170`, `:356`, `:419-537`;
  `apps/admin/src/pages/SettingsPage.tsx:155-175`.
- **DB** — none (`pricing_rules.updated_at` already exists).
- **API contract** — `PUT /admin/pricing/:city` accepts `expectedUpdatedAt`; returns 409 on
  mismatch.
- **Effort** — M.
- **Risk** — tighter bounds may block a legitimate promotional price; the override flag
  covers it and lands in the audit log.
- **Acceptance criteria** — `commissionRate: 1.0` is rejected; a base-fare change from 12
  to 120 requires typed confirmation; a stale save returns 409; navigating away from a
  dirty form warns.

### P0.5 — Reason capture, before-values, and an audit log that cannot fail quietly

- **Goal** — every destructive action is attributable, explicable and reversible-in-principle.
- **Design** — **(a)** Reuse `RejectionReasonModal` for captain suspend
  (`CaptainsPage.tsx:288`), passing suspension-specific presets, and persist the reason to
  a `suspension_reason` column. **(b)** Change `logAudit` call sites to pass
  `{before, after}` rather than the raw body — the prior row is already fetched at
  `admin.ts:355` and simply discarded. **(c)** Render the payload as a readable before/after
  diff in the audit table (F-11-17); the data is already on the client
  (`AuditLogPage.tsx:139-141`). **(d)** Keep `logAudit`'s catch — a failed audit must not
  fail the request — but increment a `audit.write.failed` counter so the silence is
  measurable (`audit.ts:33-36`).
- **Files to change** — `apps/api/src/lib/audit.ts:33-36`;
  `apps/api/src/routes/admin.ts:273-279`, `:300-309`, `:402-409`, `:522-530`;
  `apps/admin/src/pages/CaptainsPage.tsx:282-315`;
  `apps/admin/src/pages/AuditLogPage.tsx:77-129`.
- **DB** — migration adding `captains.suspension_reason`.
- **Effort** — M.
- **Acceptance criteria** — a suspension cannot be submitted without a reason; the audit row
  for a pricing change shows both old and new commission; the audit page renders the diff.

### P0.6 — Split the admin role

- **Goal** — the verification agent cannot reprice the country.
- **Design** — three roles: `support` (read everything, trip timeline, SOS ack/resolve,
  refunds up to a cap), `ops` (support + captain approve/suspend, document types,
  companies), `superadmin` (everything, including pricing and system config). `requireRole`
  already accepts a variadic list (`auth.ts:67-74`), so the server change is per-route
  guards replacing the blanket at `admin.ts:11`. Client-side, gate the sidebar and the
  action buttons off `user.role` and treat the server as the enforcement point. Coordinate
  the role model with **T02**, which owns authorization.
- **Files to change** — `apps/api/src/routes/admin.ts:11` and each route;
  `apps/api/src/middleware/auth.ts`; `apps/admin/src/components/layout/Sidebar.tsx`;
  `apps/admin/src/lib/auth.tsx:4-9`.
- **DB** — the `users.role` CHECK constraint needs the new values — coordinate with T08.
- **Effort** — M–L (mostly the migration of existing admin accounts).
- **Risk** — locking out real operators on deploy; migrate every existing `admin` to
  `superadmin` and downgrade deliberately afterwards.
- **Acceptance criteria** — a `support` token receives 403 from `PUT /admin/pricing/:city`
  and does not see the Pricing nav item.

### P1.1 — The B2B / companies console (`/companies`)

- **Goal** — the corporate business line can be operated by a human.
- **Design** — a two-level page: a company list, and a detail view with three tabs
  (employees, invoices, trips). Every control maps to an endpoint that already exists in
  `companies.ts`; the only new endpoints needed are a status change and an invoice status
  change, neither of which exists today (F-11-05).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  الشركات                                        [ + شركة جديدة ]   [ CSV ]   │
│  بحث: [_______________]   الحالة: [ الكل ▾ ]                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│  الشركة            الموظفون   حد الائتمان   المستحق    آخر فاتورة   الحالة   │
│  ─────────────────────────────────────────────────────────────────────────── │
│  المقاولون العرب      ٤٢      ٥٠٬٠٠٠      ١٢٬٤٠٠     ٢٠٢٦-٠٧-٠١   نشطة  ›  │
│  فودافون مصر          ١٨      ٣٠٬٠٠٠      ٢٨٬٩٥٠ ⚠   ٢٠٢٦-٠٧-٠١   نشطة  ›  │
│  بنك القاهرة           ٧      ١٠٬٠٠٠           ٠     —            معلّقة ›  │
└──────────────────────────────────────────────────────────────────────────────┘

  ↓ اختيار شركة

┌──────────────────────────────────────────────────────────────────────────────┐
│ ← الشركات   المقاولون العرب   [نشطة ▾]   س.ت ١٢٣٤٥٦٧٨٩                      │
│ التواصل: hr@arabcont.com · ٠٢٢٣٤٥٦٧٨   يوم الفوترة: ١   حد الائتمان: ٥٠٬٠٠٠ │
│ المستحق الحالي: ١٢٬٤٠٠ ج.م  ▓▓▓▓▓░░░░░ ٢٥٪            [ تعديل ] [ إيقاف ]   │
├──────────────────────────────────────────────────────────────────────────────┤
│  [ الموظفون ٤٢ ]   [ الفواتير ٧ ]   [ الرحلات ]                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  الموظف           مركز التكلفة   حد الإنفاق   المستخدم   نشط   إجراء        │
│  ──────────────────────────────────────────────────────────────────────────  │
│  محمد ع.          هندسة          ٢٬٠٠٠        ١٬٢٤٠     ✓     [ تعديل ]     │
│  سارة ح.          مبيعات         ٣٬٠٠٠        ٢٬٩٨٠ ⚠   ✓     [ تعديل ]     │
│                                                    [ + إضافة موظف ]          │
├──────────────────────────────────────────────────────────────────────────────┤
│  (تبويب الفواتير)                                                            │
│  الفاتورة        الفترة              الرحلات   المبلغ     الحالة    إجراء    │
│  ──────────────────────────────────────────────────────────────────────────  │
│  inv_8f21   ٢٠٢٦-٠٧-٠١ → ٠٧-٣١       ١٤٨    ١٢٬٤٠٠   صادرة   [إرسال][سداد]│
│  inv_7b03   ٢٠٢٦-٠٦-٠١ → ٠٦-٣٠       ١٣١    ١١٬٠٥٠   مدفوعة  [ عرض ]       │
│                                          [ توليد فاتورة للشهر الماضي ]       │
└──────────────────────────────────────────────────────────────────────────────┘
```

  The credit-limit bar and the ⚠ markers are the point: the reason to build this screen
  before the intercity one is that B2B is the line where money accrues silently and a
  company can quietly pass its credit limit with nobody watching. The invoices tab is the
  first place those cron-generated rows become visible to a human.
- **Files to change** — new `CompaniesPage.tsx` and `CompanyDetailPage.tsx`; routes in
  `App.tsx`; nav in `Sidebar.tsx`; two new handlers in `companies.ts` (company status,
  invoice status).
- **DB** — none for the UI; `company_invoices.status` already exists and merely needs to
  become writable.
- **API contract** — `PATCH /companies/admin/:id` `{status}`;
  `PATCH /companies/admin/invoice/:id` `{status: 'paid'|'void', note}`.
- **Effort** — L. **Risk** — low; every read endpoint already exists and is admin-guarded.
- **Acceptance criteria** — an operator can create a company, bind an employee with a spend
  limit, see the invoice the cron produced, mark it paid, and suspend a company over its
  credit limit — without a developer.

### P1.2 — Verification throughput

- **Goal** — halve the time to clear the queue.
- **Design** — four small changes, in value order: **(a)** a "next captain" affordance —
  after a decision, auto-advance and expand the next pending captain, with `N` bound to it;
  **(b)** join `captains` into `GET /admin/documents` for vehicle make/model/plate/year and
  city, and show them in the accordion header (F-11-20); **(c)** replace the serial
  `for...of` approve loop with `Promise.allSettled` and report per-document outcomes
  (F-11-18); **(d)** show `reviewed_by`/`reviewed_at` and a prior-rejection count
  (F-11-24, F-11-25). Add a pending-age column and an oldest-first sort so the queue can be
  worked by SLA rather than by recency (`admin.ts:647-655`).
- **Files to change** — `apps/admin/src/pages/CaptainVerificationPage.tsx:541-546`,
  `:640-700`, `:786-830`; `apps/api/src/routes/admin.ts:620-690`.
- **Effort** — M. **Acceptance criteria** — median seconds-per-captain drops ≥40%; no
  cross-referencing to Captains is required to make a decision.

### P1.3 — Close the approve-path divergence and notify the captain

- **Goal** — a captain's state does not depend on which screen approved them, and they find
  out.
- **Design** — extract one `approveCaptain(db, userId)` used by both
  `/documents/:id/review`'s auto-promotion and `/captains/:id/approve`, setting
  `captains.approval_status` and `users.status` together (F-11-21). Add `pushToUser` on
  approve and on reject, carrying the rejection reason (F-11-22).
- **Files to change** — `apps/api/src/routes/admin.ts:261-287`, `:821-864`.
- **Effort** — S. **Acceptance criteria** — both paths leave identical DB state; a captain
  receives a push within seconds of either outcome.

### P1.4 — Operator actions on the live map

- **Goal** — the map becomes a place to act, not only to look.
- **Design** — clicking a captain marker opens a side panel: identity, current trip (linked
  to P0.1), last-seen age, and three actions — call, message, force offline. Add a
  `POST /admin/captains/:id/force-offline` (reason-gated per P0.5). Raise the 200-row cap or
  cluster server-side by geohash and show a count (F-11-13).
- **Files to change** — `apps/admin/src/pages/LiveMapPage.tsx:100-140`;
  `apps/api/src/routes/admin.ts:925-937`.
- **Effort** — M. **Acceptance criteria** — an operator can take a stuck captain offline
  from the map with a reason recorded; the map states how many captains it is not showing.

### P1.5 — Money operations surface

- **Goal** — refunds and payouts have a queue.
- **Design** — a `/finance` page with two tabs: **payouts** (list `pending`
  `wallet_transactions` of type payout, approve/reject with a note — needs
  `POST /admin/payouts/:id/approve|reject`, which do not exist) and **refunds** (issue a
  refund against a trip, reason-gated, from the P0.1 timeline as well). Amounts and ledger
  semantics are **T03/T04's** to define; this item is the surface only.
- **Effort** — L, and blocked on T03/T04 settling the ledger model.
- **Acceptance criteria** — no payout request can sit in `pending` with no owner; every
  refund has an actor, a reason and an audit row.

### P2.1 — Intercity console, document types, and the remaining coverage

- **Design** — an `/intercity` page (routes, schedules, captain assignment, manifests,
  admin cancel/refund — 14 endpoints already exist), and a small document-types admin under
  Settings for the four orphaned CRUD endpoints (F-11-19). Both are mechanical: the API is
  written, only the screens are missing.
- **Effort** — L (intercity), S (document types).

### P2.2 — Operator ergonomics

- **Design** — explicit `tabIndex` ordering for the RTL forms (F-11-28); keyboard shortcuts
  for the high-volume paths (`J`/`K` through queues, `A`/`R` to approve/reject, `/` to
  search); a density toggle; manual refresh on Dashboard and Users (F-11-32); surface the
  vehicle-types load failure instead of silently using multiplier 1 (F-11-27). Detailed
  accessibility work is **T15**; token conformance is **T12**.
- **Effort** — M.

### P2.3 — Extract the strings

- **Design** — introduce a minimal string catalogue and move the inline Arabic into it
  (F-11-30). Not for translation on day one, but so copy can be reviewed in one place and
  an English fallback becomes possible for non-Arabic-speaking staff. Coordinate with
  **T14**, which owns content design.
- **Effort** — M.

### 6.1 Page-by-page verdict

| Page | Verdict | Priority action |
|---|---|---|
| Dashboard | Adequate. Unbounded scans on an 8 s poll (F-11-23). | Bound the KPI queries; add refresh. |
| LiveMap | Read-only and silently capped. | P1.4 — actions + honest cap. |
| Captains | Good confirm pattern, no reason capture. | P0.5 — reason on suspend. |
| Verification | The console's best page; slow at volume. | P1.2 — throughput. |
| Trips | A list with no destination. | **P0.1 — the timeline.** |
| Analytics | Genuinely solid: date-bounded SQL, presets, period deltas. | Leave alone. |
| Pricing | Careful UI, no guardrails. | P0.4 — bounds, diff-confirm, locking. |
| Users | 74 lines because there is nothing to do. | P0.3 + rider lifecycle actions (F-11-07). |
| Audit | Records verbs, not changes. | P0.5 — before/after + date filter. |
| Settings | Fine; promos work end to end. | Fold document types in (P2.1). |
| **Companies** | **Does not exist.** | **P1.1.** |
| **Safety/SOS** | **Does not exist.** | **P0.2.** |
| **Intercity** | **Does not exist.** | P2.1. |
| **Finance** | **Does not exist.** | P1.5. |

## 7. Phasing

| Item | Phase | Effort | Owner type | Gated by |
|---|---|---|---|---|
| P0.1 Unified trip timeline | **P0** | L | backend + admin | — |
| P0.2 SOS console + global banner | **P0** | M | backend + admin | — |
| P0.3 Cap banners (a), then server-side paging (b) | **P0** | S then M | admin + backend | — |
| P0.4 Pricing guardrails, diff-confirm, locking | **P0** | M | backend + admin | — |
| P0.5 Reason capture, before-values, audit counter | **P0** | M | backend + admin | — |
| P0.6 Split the admin role | **P0** | M–L | backend + admin | T02 role model |
| P1.1 Companies / B2B console | P1 | L | admin + backend | — |
| P1.2 Verification throughput | P1 | M | admin + backend | — |
| P1.3 Unified approve path + captain notification | P1 | S | backend | — |
| P1.4 Live-map actions and honest cap | P1 | M | admin + backend | P0.5 |
| P1.5 Finance surface (payouts, refunds) | P1 | L | admin + backend | **T03/T04** |
| P2.1 Intercity console + document types | P2 | L / S | admin | — |
| P2.2 Operator ergonomics | P2 | M | admin | T12, T15 |
| P2.3 String extraction | P2 | M | admin | T14 |

**P0 ≈ 15–20 engineer-days.** Three sequencing notes:

1. **P0.3(a) ships first, on its own.** Three cap banners is an afternoon and it converts
   the most dangerous class of defect — a tool that reports false absence — into a visible
   limitation. Do not wait for the server-side paging work to land.
2. **P0.1 before P1.5.** The refund action belongs on the trip timeline; building a refund
   screen before there is a trip view to launch it from produces a worse workflow.
3. **P0.6 last within P0.** Role splitting touches every route and every nav item; land the
   functional gaps first so the roles are drawn around a console that is actually finished.

## 8. Metrics

Nothing here is instrumented today — the console emits no telemetry of any kind. These are
the numbers that would prove the work landed.

| Metric | How | Today | Target |
|---|---|---|---|
| Trip disputes resolved without a developer | support tagging | **0%** (F-11-01 makes it impossible) | >90% |
| Median time to resolve a fare dispute | support tooling | unmeasured; currently gated on an engineer | <5 min |
| SOS median time-to-acknowledge | new `acknowledged_at` (P0.2) | **unmeasurable — no field, no screen** | <60 s |
| SOS alerts never acknowledged | `status='open'` age | unmeasurable; likely non-zero | 0 |
| Captains verified per agent-hour | count of `documents/:id/review` per actor | unmeasured | +100% after P1.2 |
| Clicks per captain verified | instrument the page | ~12 (§4.2) | <6 |
| Searches returning a false negative | log queries that hit the cap | **unmeasured and silently wrong** | 0 after P0.3 |
| Pricing changes with a recorded before-value | audit rows with `before` | **0%** (F-11-08) | 100% |
| `audit.write.failed` | new counter (P0.5) | unmeasured (silently swallowed) | ~0, alerted |
| Destructive actions with a captured reason | audit payload | document rejection only | 100% |
| Payout requests older than 48 h unactioned | query `wallet_transactions` | **all of them** (F-11-04) | 0 |
| B2B invoices issued vs. sent vs. paid | `company_invoices.status` | issued only; other states unreachable | full lifecycle tracked |
| Admin accounts by role | `users.role` | 1 role for everyone (F-11-06) | ≥3, most on `support` |
| Dashboard p95 response | Cloudflare analytics | unmeasured; two unbounded scans / 8 s | <300 ms |

## 9. Cross-cutting notes

- **T02 — Authorization.** F-11-06 is your finding from the UI side: `requireRole` is
  variadic and capable (`apps/api/src/middleware/auth.ts:67-74`) but `admin.ts:11` applies
  one blanket `requireRole("admin")` to all 24 routes, so a verification agent holds
  national pricing control. My P0.6 sketches `support`/`ops`/`superadmin` and the UI
  affordances each needs; the role model itself should be yours so it stays consistent with
  the object-level work. Also note `apps/admin/src/lib/auth.tsx:41` rejects non-admins
  **client-side** — harmless since the server also guards, but it should not be mistaken
  for a control.
- **T01 — Auth & sessions.** Two things. (1) `apps/admin/src/lib/api.ts:47-77` is a correct
  single-flight refresh with retry — the exact pattern you flagged as *missing* on the
  Flutter clients. Point the mobile work at it rather than designing it twice. (2)
  `apps/admin/src/lib/auth.tsx:52-57` can request an OTP with `role: "admin"`; no screen
  calls it, but it is shipped code and it lines up with your finding that the suspended OTP
  routes are still mounted and can still mint accounts.
- **T03 / T04 — Money.** Both of you found the payout debit; the operations half is that
  **no endpoint or screen can ever action the resulting `pending` row**
  (`apps/api/src/routes/wallet.ts:98-135`), so even a corrected debit strands the captain.
  My P1.5 specifies the queue but deliberately leaves the ledger semantics to you — tell me
  what a refund and a payout approval must write and I will hang the screen off it. Same for
  B2B: the cron at `apps/api/src/index.ts:334-370` issues invoices with no send and no
  paid-state, which is an A/R problem as much as a UI one.
- **T05 — Pricing.** Your track owns whether the fare formula is right; this one owns
  whether an operator can break it. Both are true today: `commissionRate: 1.0` and
  `baseFare: 0` pass every layer (`apps/api/src/lib/schemas.ts:224`, `:229`), there is no
  confirmation on any delta, and pricing writes are last-write-wins (`admin.ts:355`, `:376`).
  Also relevant to you: the admin fare estimator silently falls back to multiplier 1 when
  vehicle types fail to load (`PricingPage.tsx:103-108`, `:187`), so an operator can be
  pricing against numbers that are quietly wrong. And `vehicle_types` multipliers are
  read-only in the console — there is no endpoint to edit them at all.
- **T08 — Data model.** P0.1 and P0.3 both need indices that may not exist:
  `trip_events(trip_id)`, `trip_path_points(trip_id, recorded_at)`, `trips(created_at)`,
  `trips(city, status)`, `audit_log(created_at)`, `audit_log(actor_id)`. Also flagging that
  `sos_alerts.status` is written once and has no lifecycle columns, and
  `company_invoices.status` is written `'issued'` and never updated
  (`apps/api/src/routes/companies.ts:186`) — both need columns before their screens can
  exist. P0.6 needs the `users.role` CHECK widened.
- **T22 — Observability.** The admin console emits no telemetry at all, and two specific
  silences are dangerous: `logAudit` swallows every failure with only a `console.error`
  (`apps/api/src/lib/audit.ts:33-36`), and the Dashboard runs two unbounded `GROUP BY`
  scans every 8 seconds per open tab (`admin.ts:14-20`). The audit log is the platform's
  only record of destructive admin actions and it is best-effort with no counter.
- **T23 — Testing.** `apps/admin/package.json:6-12` has no test runner and there are no
  tests in the app. The two highest-value ones are cheap: a test that a capped list renders
  its cap banner, and a test that a destructive action cannot submit without a reason.
- **T24 — Performance.** Dashboard's unbounded scans (F-11-23), the client-side filtering of
  200-row windows (F-11-03), and the absence of any index strategy behind the admin queries.
- **T17 — Safety & trust.** F-11-02 is really yours as much as mine: SOS has a write path
  and no read path. Whatever response protocol you design needs the console in P0.2 to exist,
  and needs `sos_alerts` to gain acknowledge/resolve columns.
- **T20 — Intercity & B2B.** Both verticals are fully built in the API and completely
  invisible to operators (23 endpoints, zero screens). If either is meant to carry real
  volume, P1.1 and P2.1 are prerequisites, not polish.
- **T27 — Cross-app parity.** The admin console is the third app and it shares nothing with
  the other two — its own token storage, its own fetch wrapper, its own design tokens. That
  is defensible for a React SPA, but the *vocabulary* should still match: check that the
  status labels here (`مكتملة`, `موقوف`, `قيد الانتظار`) are the same words the two Flutter
  apps use for the same states.
- **T14 — Localisation.** No i18n layer; all copy is inline Arabic
  (`apps/admin/package.json:13-19`). Arabic-only is the right default for these operators —
  the issue is that the strings are unreviewable as a set and there is no English fallback
  path. See P2.3 and §10 Q4.
- **T12 / T15 — Design system and accessibility.** RTL tab order is unmanaged across the
  config forms (F-11-28), and information density has never been evaluated for an
  eight-hour shift. Both are noted here and owned by you.

## 10. Open questions

**Q1 — Where does the trip timeline get its data: one aggregate endpoint or several?**
Options: (a) one `GET /admin/trips/:id/full` returning all six collections; (b) the page
fires five parallel requests; (c) a GraphQL-ish field selector. **Recommend (a).** One
round-trip is materially faster on a hosted admin over Egyptian broadband, it is one thing
to cache and one thing to authorize, and the response is small once `path` is decimated
server-side. (b) multiplies auth checks and makes partial-failure states the page's problem.

**Q2 — Should the SOS banner be global, and should it make noise?** Options: (a) a red bar
in `Layout` on every page, silent; (b) global bar plus an audible alert; (c) a badge on the
Safety nav item only. **Recommend (a) now, (b) once there is a staffed desk.** A silent
global bar cannot be missed by someone using the console and cannot cry wolf in an open
office. Audio matters only when someone is specifically on duty, and that is a staffing
decision the operator has to make.

**Q3 — How many admin roles, and is the split by function or by city?** Options: (a)
three functional roles (`support`/`ops`/`superadmin`); (b) functional roles plus city
scoping, so a Cairo ops lead cannot touch Alexandria pricing; (c) keep one role and rely on
the audit log. **Recommend (a) now, design the schema so (b) is additive.** City scoping is
the Careem pattern and the right end state, but Synaptic Go operates one city today
(`DEFAULT_CITY = "cairo"`) and building the scoping before the second city is speculative.
Add a nullable `city_scope` column now, ignore it until it is needed. (c) is not viable
given F-11-08 — the audit log cannot currently reconstruct what changed.

**Q4 — Does the console need English?** Today it is Arabic-only with no i18n layer
(F-11-30). Options: (a) stay Arabic-only, extract strings for reviewability; (b) full
ar/en switching; (c) English-only for a technical subset (audit, settings). **Recommend
(a).** The operators are Egyptian and Arabic is the right default; the real cost today is
that copy cannot be reviewed as a set and vendor or contractor staff cannot be onboarded.
Extraction gets both benefits for a fraction of the cost of (b). Revisit if the ops team
ever includes non-Arabic speakers.

**Q5 — Who is allowed to issue a refund, and up to what amount?** There is no refund
endpoint at all today, so the policy is undefined rather than permissive. Options: (a) any
`support` agent, unlimited; (b) `support` up to a cap (say 500 EGP) with `ops` approval
above it; (c) `ops` only. **Recommend (b).** Most disputes are small and same-day, and
routing all of them through a senior queue is how support backlogs form — but an unbounded
refund button in the hands of the largest and newest role is the classic internal-fraud
vector. The cap belongs in `system_config` so it can be tuned without a deploy.

**Q6 — Does the live map need to show every captain, or is a clustered count enough?**
Today it silently shows at most 200 (F-11-13). Options: (a) raise the cap and render every
marker; (b) server-side geohash clustering with counts, expanding on zoom; (c) keep a cap
but state it honestly. **Recommend (b), with (c) shipped immediately as the stopgap.** Ten
thousand DOM markers will not render usefully anyway, and clustering answers the actual
operational question — *where is supply thin right now* — better than a pin per captain
ever did.
