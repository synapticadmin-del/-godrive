# 02 — Authorization, RBAC & Object-Level Access

> Track: A — Foundation & safety-critical · Reviewer: chat-20260801-1214-a0bd · Date: 2026-08-01 (UTC)
> Base commit reviewed: `dccc2dadf206ffaba4d35b3343d55ff279bacaf4`

## 1. Scope

This document answers one question: **given a valid token, what can it reach?**

It covers the complete authorization surface of the API worker — the route-mounting
order in `apps/api/src/index.ts`, the two guards in `apps/api/src/middleware/auth.ts`,
and every endpoint in all 14 route files. For each endpoint it establishes which roles
may call it, where that is enforced in code, and — the part that matters most — whether
an object id accepted in the path or body is bound to the caller (BOLA / IDOR).

It also covers: the admin privilege boundary and the absence of admin sub-roles, audit
coverage of state-changing admin actions, cross-tenant isolation in the B2B company
surface, trip-participant scoping for chat / path / share tokens, and R2 object access
for captain identity documents and avatars.

**Explicitly out of scope**, with the sibling track that owns it:

| Not covered here | Owner |
|---|---|
| OTP mechanics, password hashing, JWT signing/rotation, refresh reuse detection, `SESSIONS` KV semantics, Turnstile | **T01** |
| Ledger correctness, commission math, double-spend, payout reconciliation | **T03** |
| PSP integration depth, Paymob webhook retry/settlement semantics | **T04** |
| Dispatch fairness and offer fan-out logic | **T06** |
| Durable Object internal message authorization (`TripRoom`, `CaptainInbox` handlers) | **T07** |
| Schema/index/migration integrity | **T08** |
| PII retention, data-subject rights, lawful basis | **T25** |

Where this review touches those areas it is only through the authorization lens — for
example, F-02-02 is filed here because a payment intention is not bound to its trip's
owner, not because of how the ledger records it.

A note on method: three claims in this document are counter-intuitive enough that I
verified them by executing real Hono 4.7.11 (the version pinned in
`apps/api/package.json`) rather than reasoning from the source. Those are marked
`confirmed (empirical)` and the test is described in §3.1. One of them **overturned a
finding I had initially written up as a blocker** — see §4.1 "Verified non-findings".

## 2. What I actually read

Every file below was downloaded at commit `dccc2da` and read with real line numbers.
Line citations throughout this document were re-checked against these files.

**Core authorization primitives — read in full, line by line**

| File | Lines | Note |
|---|---|---|
| `apps/api/src/middleware/auth.ts` | 75 | `authMiddleware` + `requireRole`; the `queryTokenAllowed` allowlist |
| `apps/api/src/index.ts` | 372 | Route mounting order, CORS, global rate limit, WS upgrade auth, cron |
| `apps/api/src/lib/jwt.ts` | 96 | Claim set for access/refresh tokens; `verifyToken` |
| `apps/api/src/lib/types.ts` | 102 | `AuthUser`, `DbUser`, `DbTrip`, `DbCaptain` shapes |
| `apps/api/src/lib/audit.ts` | 37 | `logAudit` — including its swallow-all catch block |
| `apps/api/src/middleware/rateLimit.ts` | 90 | `parseBody` / `isResponse` helpers, rate-limit keying |

**All 14 route files — read in full**

| File | Lines | Endpoints | Note |
|---|---|---|---|
| `routes/trips.ts` | 1371 | 16 | The core object. One route sits above the auth middleware |
| `routes/admin.ts` | 937 | 24 | Entire admin surface; single blanket guard at line 11 |
| `routes/captain.ts` | 700 | 14 | Profile, documents, R2 upload/serve |
| `routes/auth.ts` | 483 | 8 | Read for privilege aspects only (role assignment, admin bootstrap) |
| `routes/intercity.ts` | 463 | 15 | Public catalogue + booking + captain manifest + admin |
| `routes/user.ts` | 328 | 9 | Profile, avatar, saved places |
| `routes/payments.ts` | 313 | 2 | Intention + unauthenticated Paymob webhook |
| `routes/safety.ts` | 291 | 7 | SOS, share tokens, trip chat |
| `routes/companies.ts` | 239 | 9 | B2B tenancy surface |
| `routes/wallet.ts` | 142 | 4 | Balances and captain payout |
| `routes/promo.ts` | 108 | 4 | Validation + admin CRUD |
| `routes/search.ts` | 48 | 1 | Declares `/admin/search` but is mounted at root |
| `routes/devices.ts` | 41 | 2 | FCM token registration |
| `routes/geocode.ts` | 37 | 2 | Unauthenticated geocoding proxy |

**Supporting files — read for specific questions**

- `lib/schemas.ts` (331) — every zod schema, to settle the mass-assignment question per endpoint.
- `lib/utils.ts` (241) — `id()` generator, to settle share-token entropy.
- `lib/nearby.ts` (105) — `NearbyCaptain` shape, to establish exactly what the unauthenticated estimate endpoint leaks.
- `lib/paymob.ts` (235) — skimmed for HMAC verification entry point only; depth belongs to T04.
- `apps/admin/src/lib/auth.tsx` (92), `apps/admin/src/lib/api.ts` (114) — how the console stores the token and fetches document images.
- All 19 files in `migrations/` (836 lines total) — read for the `users.role` CHECK constraint, `audit_log`, `trip_share_tokens`, `company_employees`, `driver_documents`, `payment_intentions` shapes. `0016_system_config.sql` read in full as the brief requires.

**Skimmed rather than read** (named for honesty): `lib/notifications.ts`, `lib/routing.ts`,
`lib/geocode.ts`, `lib/pricing.ts`, `lib/cleanup.ts`, `apps/admin/src/lib/{csv,escape,usePolling,utils}.ts`.
I did **not** read the four Durable Object implementations — `TripRoom`, `GeoCell`,
`CaptainInbox`, `OfferScheduler` — so every statement about authorization *inside* a DO
is marked `needs-check` and handed to **T07**.

## 3. How it works today

### 3.0 The two guards, and the shape of a request

There are exactly two authorization primitives in the codebase.

**`authMiddleware`** (`middleware/auth.ts:29`) extracts a bearer token, falls back to a
`?token=` query parameter only for an allowlisted path set (`middleware/auth.ts:21-27` —
WebSocket upgrades and admin document images), verifies it with `jose`, rejects refresh
tokens on protected routes (`middleware/auth.ts:52`), and puts an `AuthUser` on the
context (`middleware/auth.ts:55-60`).

**`requireRole(...roles)`** (`middleware/auth.ts:67`) checks `roles.includes(user.role)`
against the role **as carried in the token** and returns 403 otherwise.

That is the whole system. There is no permission model, no policy layer, no
object-level helper. **Every ownership check in this codebase is hand-written inline in
its handler**, which is why the results vary so much from route to route: `trips.ts`
does it well and consistently, `payments.ts` does not do it at all.

Critically, `index.ts` applies **no global `authMiddleware`**. CORS (`index.ts:40`) and a
120 req/min per-IP rate limit (`index.ts:59`) are global; authentication is delegated
entirely to each route file. Fourteen files each decide their own posture, and the
posture is expressed through *registration order*.

### 3.1 Hono registration order is the security boundary — and I tested it

In Hono, `.use()` middleware applies only to routes registered **after** it on the same
router instance. Three consequences in this codebase looked severe enough on inspection
that I verified them against real Hono `4.7.11` (matching `apps/api/package.json`,
`"hono": "^4.7.11"`), obtained as a self-contained bundle and driven through
`app.request()`.

**Test A — a route registered above `.use("*")`.** Replicating `trips.ts` exactly
(`POST /estimate` at line 315, `use("*", authMiddleware)` at line 346):

```
POST /trips/estimate   -> 200  middleware chain: []                 ← UNAUTHENTICATED
POST /trips/           -> 200  middleware chain: ["authMiddleware"]
```

Confirmed: `POST /trips/estimate` executes with no authentication whatsoever. This is
finding **F-02-01**.

**Test B — does `/admin/*` match the bare path `/admin`?** This is the question that
decides whether `companies.ts` leaks the entire B2B tenant list. Replicating
`companies.ts` exactly (`use("*", authMiddleware)` at 11, `use("/admin/*", requireRole("admin"))`
at 68, `POST /admin` at 70, `GET /admin` at 99):

```
POST /companies/admin          -> ["authMiddleware","requireRole(admin)"]  GUARDED
GET  /companies/admin          -> ["authMiddleware","requireRole(admin)"]  GUARDED
GET  /companies/admin/cmp_123  -> ["authMiddleware","requireRole(admin)"]  GUARDED
POST /companies/trip           -> ["authMiddleware"]                       (correct)
```

In Hono 4, a trailing `/*` **does** match the bare parent path. `POST /companies/admin`
and `GET /companies/admin` are properly admin-guarded. I had written this up as an S1
cross-tenant breach before testing; it is not one. See §4.1.

**Test C — `/admin/search` is served by which router?** `index.ts:111` mounts
`adminRoutes` at `/admin`; `index.ts:116` mounts `searchRoutes` at `/`. Both declare a
handler for that path (`admin.ts:551` and `search.ts:8`):

```
GET /admin/search -> "admin.ts:551 GUARDED handler"  chain: ["authMiddleware+requireRole(admin)"]
```

The admin-guarded handler wins on registration order. `search.ts`'s handler is dead
code today — a latent trap rather than a live hole (F-02-14).

### 3.2 Where the role lives, and when it is trusted

The role is stored in D1 — `users.role`, constrained by
`CHECK (role IN ('rider','captain','admin'))` (`migrations/0001_init.sql:9`) — and
**copied into the JWT** at sign time (`lib/jwt.ts:19`, and for refresh tokens
`lib/jwt.ts:59`).

The good news, and it is genuinely good: **a client cannot influence its own role at any
issuance point.**

- `POST /auth/register` clamps it: `const assignedRole = body.role === "captain" ? "captain" : "rider"` (`routes/auth.ts:367`). Sending `role: "admin"` yields `rider`.
- `POST /auth/login` reads the role from the D1 row (`routes/auth.ts:392`, used at `:408`) and refuses suspended accounts (`routes/auth.ts:398`).
- `POST /auth/refresh` re-reads the whole user from D1 (`routes/auth.ts:297`) and re-checks suspension (`routes/auth.ts:301`) before minting a new pair — the new token's role comes from the fresh row, never copied from the presented token.
- `GET /auth/me` re-reads from D1 (`routes/auth.ts:463`) rather than echoing claims.
- Self-service writes cannot touch privilege columns: `PATCH /user/profile` accepts only `name` and `phone` (`routes/user.ts:20-23`, UPDATE at `:97-100`), and `POST /captain/profile` hardcodes `approval_status` to `'pending'` on insert (`routes/captain.ts:45-47`) and omits it from the update entirely (`routes/captain.ts:59-66`).

The gap is **between** issuance points. On every protected request the role is taken
from the token (`middleware/auth.ts:57`) and never revalidated against D1, and
`users.status` is **never consulted at all** by `authMiddleware`. An admin demoted in
D1, or a captain suspended via `POST /admin/captains/:id/suspend` (`admin.ts:289`),
continues to hold full privileges until their 15-minute access token
(`lib/jwt.ts:8`) expires. There is no server-side kill switch for an access token that
is already in the wild. This is F-02-02.

### 3.3 There is no `company` role

The brief asks for a matrix over `{anonymous, rider, captain, admin, company}`. There
is no `company` principal in this system. `UserRole` admits exactly three values
(`migrations/0001_init.sql:9`), and a "company employee" is an ordinary `rider` who
happens to have an active row in `company_employees`. That binding is resolved
per-request by query, not by claim — `routes/companies.ts:26-35` for the booking
authorization check and `routes/companies.ts:221` for the invoice portal.

The consequence is that the company column in the matrix below is *identical to the
rider column* everywhere except the two portal endpoints, and there is no such thing as
a company administrator: any active employee of a company can read that company's
invoices and trip list. Cross-tenant isolation itself holds — the portal query is scoped
through the caller's own employee row — but there is no privilege gradient inside a
tenant.

### 3.4 The trip is a three-party object, and `trips.ts` mostly gets it right

The dominant object is `trips`, with `rider_id`, `captain_id` and an admin override. The
established pattern in `trips.ts` is a three-party predicate evaluated after loading the
row, for example at `routes/trips.ts:654-659` (`GET /:id`):

```
if (user.role !== "admin" && trip.rider_id !== user.id && trip.captain_id !== user.id)
  return 403
```

The same shape recurs at `:690-695` (`/:id/path`), `:719-721` (`/:id/cancel`),
`:1104-1107` (`/:id/rate`), and — narrowed to rider-or-admin, correctly — at `:1225`
(`/:id/bids`) and `:1275` (`/:id/accept-bid`). Captain-only transitions bind to the
assigned captain: `:903` inside the shared `advanceStatus` helper used by `/arrived` and
`/start`, and `:959` for `/complete`.

`safety.ts` follows the same discipline for chat and share creation (`:67`, `:160`,
`:224`, `:268`), and `intercity.ts` binds the captain manifest to the schedule's owner
(`:350`) and boarding to the booking's captain (`:380`).

This is worth stating plainly because it changes what the remediation looks like: **the
codebase already knows how to do object-level authorization.** The failures are not a
missing concept; they are specific routes that skipped an established pattern. That is a
much cheaper problem to fix than an architectural one.

### 3.5 R2 object access

Two routes serve R2 objects to end users and one serves them to admins.

- `GET /captain/file/*` (`captain.ts:673`) derives the key from the URL path (`:675`) — user-controlled — but enforces a folder prefix check: non-admins must request a key under `docs/<their own id>/` (`captain.ts:679-682`). Captain A cannot read captain B's national ID. Upload keys are `docs/<userId>/<timestamp>_<uuid>.<ext>` (`captain.ts:664`) and registration refuses a key outside the caller's own folder (`captain.ts:544-545`).
- `GET /user/avatar/*` (`user.ts:202`) pins the key inside the `avatars/` namespace and rejects `..` (`user.ts:48-53`), then serves it to any authenticated user. That is deliberate and documented (`user.ts:197-200`) — a rider must see their captain's face.
- `GET /admin/documents/:id/file` (`admin.ts:894`) resolves `r2_key` from the database by document id (`admin.ts:896-898`), never from user input, and sets `Cache-Control: private, no-store` plus `X-Content-Type-Options: nosniff` (`admin.ts:912`, `:919`). The authorization is correct. The problem is the credential used to reach it — see F-02-07.

### 3.6 Audit

`logAudit` (`lib/audit.ts:3`) writes one row to `audit_log`. Coverage of state-changing
admin endpoints is **complete** — all nine mutating routes in `admin.ts` call it
(`:273`, `:301`, `:402`, `:522`, `:736`, `:782`, `:810`, `:854`, `:880`), and
`companies.ts` logs company creation (`:90`) and invoice issue (`:199`). `GET /admin/audit-log`
(`admin.ts:219`) is read-only and there is no DELETE against `audit_log` anywhere in the
codebase.

The defect is not coverage, it is durability: the entire write is wrapped in a
catch that swallows the error (`lib/audit.ts:33-36`) and no call site inspects a result.
A mutation whose audit insert fails still returns 200 to the operator, silently. See
F-02-06.

### 3.7 The authorization matrix

All 117 endpoints, at commit `dccc2da`. Legend:
**✓** allowed · **✗** denied (403/401) · **⚠** reachable but the access is flawed — see the linked finding.
The *company* column means "authenticated user holding an active `company_employees` row";
as established in §3.3 it is not a distinct role.

#### `auth.ts` → `/auth` (no blanket middleware)

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| POST /auth/otp/request | ✓ | ✓ | ✓ | ✓ | ✓ | rate limit only — mechanics owned by T01 |
| POST /auth/otp/verify | ✓ | ✓ | ✓ | ✓ | ✓ | T01; routes confirmed still mounted (`auth.ts:131`) |
| POST /auth/refresh | ✓ | ✓ | ✓ | ✓ | ✓ | token in body; D1 re-read `auth.ts:297`, suspended `:301` |
| POST /auth/logout | ✗ | ✓ | ✓ | ✓ | ✓ | `authMiddleware` inline `auth.ts:320` |
| POST /auth/register | ✓ | ✓ | ✓ | ✓ | ✓ | role clamped `auth.ts:367` |
| POST /auth/login | ✓ | ✓ | ✓ | ✓ | ✓ | role from D1 `auth.ts:392/:408`; suspended `:398` |
| POST /auth/admin/setup | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | no-admin-exists `auth.ts:427-430` + secret `:438-443` → F-02-11 |
| GET /auth/me | ✗ | ✓ | ✓ | ✓ | ✓ | `authMiddleware` inline `auth.ts:461`; D1 re-read `:463` |

#### `trips.ts` → `/trips` (`use("*", authMiddleware)` at line 346)

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| POST /trips/estimate | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | **none** — registered at `:315`, above the guard → **F-02-01** |
| POST /trips | ✗ | ✓ | ✗ | ✓ | ✓ | `requireRole("rider","admin")` `:350`; `rider_id` forced to caller `:454` |
| GET /trips/history | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE rider_id = ?` `:609` |
| GET /trips | ✗ | ✓ | ⚠ | ✓ | ✓ | rider `:640`; captain sees `SELECT *` of all open city trips `:635` → F-02-09 |
| GET /trips/:id | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `:654-659`; exposes `captain_phone` `:136` → F-02-10 |
| GET /trips/:id/path | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `:690-695` |
| POST /trips/:id/cancel | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `:719-721` |
| POST /trips/:id/accept | ✗ | ✗ | ✓ | ✓ | ✗ | `requireRole` `:829`; atomic CAS `WHERE status IN (...)` `:862` |
| POST /trips/:id/arrived | ✗ | ✗ | ✓ | ✓ | ✗ | `advanceStatus` captain check `:903` → TOCTOU F-02-15 |
| POST /trips/:id/start | ✗ | ✗ | ✓ | ✓ | ✗ | as above `:903` |
| POST /trips/:id/complete | ✗ | ✗ | ✓ | ✓ | ✗ | assigned-captain check `:959`; CAS `:974` |
| POST /trips/:id/rate | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `:1104-1107` |
| POST /trips/:id/bid | ✗ | ✗ | ⚠ | ✓ | ✗ | `requireRole` `:1144`; no dispatch binding → **F-02-08** |
| GET /trips/:id/bids | ✗ | ✓ | ✗ | ✓ | ✓ | rider-or-admin `:1225` — correct auction isolation |
| POST /trips/:id/accept-bid | ✗ | ✓ | ✗ | ✓ | ✓ | `requireRole` `:1262`; owner check `:1275`; bid tied to trip `:1283` |

#### `captain.ts` → `/captain` (`use("*", authMiddleware, requireRole("captain","admin"))` at line 24)

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| POST /captain/profile | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE user_id = ?` `:35/:40/:66`; `approval_status` not writable `:45-47`, `:59-66` |
| GET /captain/profile | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE c.user_id = ?` `:125` |
| POST /captain/online | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE user_id = ?` `:168` |
| POST /captain/location | ✗ | ✗ | ✓ | ✓ | ✗ | UPDATE bound `:208`; trip re-verified `captain_id = ?` `:226` |
| GET /captain/earnings | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE captain_id = ?` `:285` |
| POST /captain/search-radius | ✗ | ✗ | ✓ | ✓ | ✗ | bound `:318`; clamped 1–100 `schemas.ts:193-194` |
| GET /captain/nearby-requests | ✗ | ✗ | ✓ | ✓ | ✗ | captain row by caller `:334`; city-scoped browse (by design) |
| GET /captain/offers | ✗ | ✗ | ✓ | ✓ | ✗ | captain row by caller `:443` |
| GET /captain/document-types | ✗ | ✗ | ✓ | ✓ | ✗ | reference data |
| GET /captain/documents | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE d.captain_id = ?` `:523` |
| POST /captain/documents | ✗ | ✗ | ✓ | ✓ | ✗ | key prefix enforced `:544-545`; insert bound `:579` |
| DELETE /captain/documents/:type | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE captain_id = ? AND type = ?` `:606` |
| POST /captain/upload | ✗ | ✗ | ✓ | ✓ | ✗ | key derived from caller `:664`; byte-sniffed type `:637-659`; 10 MB cap `:631` |
| GET /captain/file/* | ✗ | ✗ | ✓ | ✓ | ✗ | own-folder prefix check `:679-682`; no `..` guard → F-02-16 |

#### `admin.ts` → `/admin` (`use("*", authMiddleware, requireRole("admin"))` at line 11)

Every one of the 24 routes is registered after line 11 (first `:13`, last `:925`), so the
blanket guard covers the file with no gaps. All 24 are therefore **anon ✗ · rider ✗ ·
captain ✗ · admin ✓ · company ✗**. The column that matters for this file is not *who*
but *which admin* — and there is only one kind (F-02-05) — and whether the action is
audited.

| Endpoint | Line | Mutating | Audited at |
|---|---|:--:|---|
| GET /admin/stats | 13 | | — |
| GET /admin/live-trips | 52 | | — |
| GET /admin/analytics | 64 | | — |
| GET /admin/audit-log | 219 | | read-only; no DELETE path exists |
| GET /admin/captains | 229 | | — |
| POST /admin/captains/:id/approve | 261 | ✓ | `:273` |
| POST /admin/captains/:id/suspend | 289 | ✓ | `:301` |
| GET /admin/trips | 312 | | — |
| GET /admin/users | 326 | | — |
| GET /admin/pricing | 333 | | — |
| GET /admin/vehicle-types | 342 | | — |
| PUT /admin/pricing/:city | 349 | ✓ | `:402` — whitelisted via `pricingUpdateSchema` |
| GET /admin/system-config | 463 | | — |
| PUT /admin/system-config | 488 | ✓ | `:522` — keys filtered through const map `:426-434` |
| GET /admin/search | 551 | | wins over `search.ts:8` on mount order (§3.1 Test C) |
| GET /admin/documents | 620 | | — |
| GET /admin/document-types | 691 | | — |
| POST /admin/document-types | 698 | ✓ | `:736` |
| PUT /admin/document-types/:id | 749 | ✓ | `:782` |
| DELETE /admin/document-types/:id | 797 | ✓ | `:810` |
| POST /admin/documents/:id/review | 821 | ✓ | `:854` |
| POST /admin/captains/:id/documents/:docId/reject | 867 | ✓ | `:880` |
| GET /admin/documents/:id/file | 894 | | r2_key from DB `:896`; `?token=` allowed → **F-02-07** |
| GET /admin/online-captains | 925 | | — |

#### `user.ts` → `/user` · `wallet.ts` → `/` · `devices.ts` → `/user`

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| GET /user/profile | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE id = ?` `user.ts:77` |
| PATCH /user/profile | ✗ | ✓ | ✓ | ✓ | ✓ | only `name`/`phone` `user.ts:20-23`, `:97-100` |
| POST /user/avatar | ✗ | ✓ | ✓ | ✓ | ✓ | key + UPDATE bound `user.ts:163-164`, `:177` |
| GET /user/avatar/* | ✗ | ✓ | ✓ | ✓ | ✓ | namespace-pinned, `..` rejected `user.ts:48-53`; cross-user by design |
| DELETE /user/avatar | ✗ | ✓ | ✓ | ✓ | ✓ | bound `user.ts:224`, `:228` |
| GET /user/saved-places | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE user_id = ?` `user.ts:250` |
| POST /user/saved-places | ✗ | ✓ | ✓ | ✓ | ✓ | insert bound `user.ts:266` |
| PATCH /user/saved-places/:id | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE id = ? AND user_id = ?` `user.ts:286`, `:309` |
| DELETE /user/saved-places/:id | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE id = ? AND user_id = ?` `user.ts:323` |
| GET /user/wallet | ✗ | ✓ | ✓ | ✓ | ✓ | bound `wallet.ts:21`, `:30` |
| GET /user/wallet/transactions | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE user_id = ?` `wallet.ts:49` |
| GET /captain/wallet | ✗ | ✗ | ✓ | ✓ | ✗ | `requireRole` inline `wallet.ts:56`; bound `:63/:68/:81` |
| POST /captain/wallet/payout | ✗ | ✗ | ✓ | ✓ | ✗ | `requireRole` `wallet.ts:98`; CAS `WHERE id = ? AND wallet_balance >= ?` `:114` |
| POST /user/device | ✗ | ⚠ | ⚠ | ⚠ | ⚠ | UPSERT reassigns `user_id` on token conflict `devices.ts:21-25` → F-02-12 |
| DELETE /user/device | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE token = ? AND user_id = ?` `devices.ts:38` |

#### `safety.ts` → `/safety` (`use("*", authMiddleware)` at line 11)

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| POST /safety/sos | ✗ | ⚠ | ⚠ | ⚠ | ⚠ | **no participant check** on `tripId` `safety.ts:25` → **F-02-03** |
| POST /safety/share | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `safety.ts:67`; token = `randomUUID` `utils.ts:9-12` |
| GET /safety/track/:token | ⚠ | ✓ | ✓ | ✓ | ✓ | **requires JWT** (guard at `:11` covers `:90`) → **F-02-04**; expiry `:99`, revocation `:98` |
| DELETE /safety/share/:token | ✗ | ✓ | ✓ | ✓ | ✓ | `AND created_by = ?` `safety.ts:130` |
| POST /safety/chat/:tripId | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `safety.ts:160` |
| GET /safety/chat/:tripId | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `safety.ts:224` |
| POST /safety/chat/:tripId/typing | ✗ | ✓ | ✓ | ✓ | ✓ | three-party check `safety.ts:268` |

#### `companies.ts` → `/companies` · `intercity.ts` → `/intercity`

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| POST /companies/trip | ✗ | ✗ | ✗ | ✗ | ✓ | active-employee join `companies.ts:26-36` |
| POST /companies/admin | ✗ | ✗ | ✗ | ✓ | ✗ | `/admin/*` **does** cover `/admin` — verified §3.1 Test B |
| GET /companies/admin | ✗ | ✗ | ✗ | ✓ | ✗ | as above |
| GET /companies/admin/:id | ✗ | ✗ | ✗ | ✓ | ✗ | `companies.ts:68` |
| POST /companies/admin/employee | ✗ | ✗ | ✗ | ✓ | ✗ | `companies.ts:68` |
| PATCH /companies/admin/employee/:id | ✗ | ✗ | ✗ | ⚠ | ✗ | no company scope on `empId`, not audited `companies.ts:149-151` → F-02-17 |
| POST /companies/admin/:id/invoice | ✗ | ✗ | ✗ | ✓ | ✗ | audited `companies.ts:199` |
| GET /companies/admin/:id/invoices | ✗ | ✗ | ✗ | ✓ | ✗ | `companies.ts:68` |
| GET /companies/portal/invoices | ✗ | ✗ | ✗ | ✗ | ✓ | scoped via caller's employee row `companies.ts:221`, `:229` |
| GET /intercity/routes | ✓ | ✓ | ✓ | ✓ | ✓ | public catalogue by design `intercity.ts:16` |
| GET /intercity/routes/:id | ✓ | ✓ | ✓ | ✓ | ✓ | `intercity.ts:34` |
| GET /intercity/schedules | ✓ | ✓ | ✓ | ✓ | ✓ | `intercity.ts:43` |
| GET /intercity/schedules/:id | ✓ | ✓ | ✓ | ✓ | ✓ | `intercity.ts:65` |
| POST /intercity/bookings | ✗ | ✓ | ✓ | ✓ | ✓ | guard `:79`; booking stored under caller |
| GET /intercity/bookings | ✗ | ✓ | ✓ | ✓ | ✓ | `WHERE b.rider_id = ?` `intercity.ts:212` |
| POST /intercity/bookings/:id/cancel | ✗ | ✓ | ✓ | ✓ | ✓ | owner-or-admin `intercity.ts:243` |
| GET /intercity/captain/schedules | ✗ | ✗ | ✓ | ✓ | ✗ | `WHERE s.captain_id = ?` `intercity.ts:332` |
| GET /intercity/captain/schedules/:id/passengers | ✗ | ✗ | ✓ | ✓ | ✗ | schedule-owner check `intercity.ts:350` — correct |
| POST /intercity/captain/board/:bookingId | ✗ | ✗ | ✓ | ✓ | ✗ | booking-captain check `intercity.ts:380` |
| POST /intercity/admin/routes | ✗ | ✗ | ✗ | ✓ | ✗ | `intercity.ts:394` |
| PATCH /intercity/admin/routes/:id | ✗ | ✗ | ✗ | ✓ | ✗ | `intercity.ts:394` |
| POST /intercity/admin/schedules | ✗ | ✗ | ✗ | ✓ | ✗ | `intercity.ts:394` |
| POST /intercity/admin/schedules/:id/assign | ✗ | ✗ | ✗ | ✓ | ✗ | `intercity.ts:394` |

#### `payments.ts` → `/payments` · `promo.ts` → `/promos` · `search.ts` → `/` · `geocode.ts` → `/geocode`

| Endpoint | anon | rider | captain | admin | company | Enforced at |
|---|:--:|:--:|:--:|:--:|:--:|---|
| POST /payments/paymob/intention | ✗ | ⚠ | ⚠ | ⚠ | ⚠ | `authMiddleware` `payments.ts:23`; **amount and `tripId` unbound** `:13/:17/:46/:74` → **F-02-05** |
| POST /payments/paymob/webhook | ✓ | ✓ | ✓ | ✓ | ✓ | unauthenticated by design; HMAC verified before any write `payments.ts:104-114` |
| POST /promos/validate | ✗ | ✓ | ✓ | ✓ | ✓ | `authMiddleware` `promo.ts:10`; existence oracle → F-02-13 |
| GET /promos | ✗ | ✗ | ✗ | ✓ | ✗ | `requireRole` inline `promo.ts:53` |
| POST /promos | ✗ | ✗ | ✗ | ✓ | ✗ | `requireRole` inline `promo.ts:60` |
| POST /promos/:code/deactivate | ✗ | ✗ | ✗ | ✓ | ✗ | `requireRole` inline `promo.ts:94` |
| GET /admin/search *(search.ts)* | — | — | — | — | — | unreachable; shadowed by `admin.ts:551` → F-02-14 |
| GET /geocode/reverse | ✓ | ✓ | ✓ | ✓ | ✓ | **no auth** — rate limit only `geocode.ts:8-10` → F-02-18 |
| GET /geocode/search | ✓ | ✓ | ✓ | ✓ | ✓ | **no auth** — rate limit only `geocode.ts:26` → F-02-18 |

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-02-01 | S1 | `POST /trips/estimate` is registered above the auth middleware and runs unauthenticated, returning live captain identities and positions | `apps/api/src/routes/trips.ts:315`, guard at `:346`, response at `:342`, shape at `lib/nearby.ts:55-58` | Anonymous enumeration of every online captain's user id, display name and distance from arbitrary coordinates; trilateration yields live positions. Also a free pricing oracle | confirmed (empirical) |
| F-02-02 | S1 | Payment intention accepts a caller-chosen `amount` and an unvalidated `tripId`; the webhook then marks that trip paid | `routes/payments.ts:13`, `:17`, `:46`, `:71`, `:74`; settlement at `:200-205`; tamper check at `:148` | A rider pays 1 EGP and any trip — including another rider's — is set `payment_status='paid'`. Direct revenue loss | confirmed |
| F-02-03 | S1 | The public trip-tracking link requires a JWT and points at a path that does not exist, so trip sharing is non-functional for the family member it exists for | `routes/safety.ts:11` (guard) covering `:90` (route); URL built at `:83` | A safety feature that reports success to the rider while delivering nothing. Worse than absent: riders believe they are being watched | confirmed (empirical) |
| F-02-04 | S2 | `role` is trusted from the JWT for the life of the access token and `users.status` is never checked on protected requests | `middleware/auth.ts:55-60`; role claim `lib/jwt.ts:19`; TTL `lib/jwt.ts:8`; suspend writes D1 only `routes/admin.ts:289` | A suspended captain keeps accepting trips, and a demoted admin keeps admin rights, for up to 15 minutes after the D1 change | confirmed |
| F-02-05 | S2 | There is no admin sub-role. Every admin is omnipotent | `middleware/auth.ts:67`; `requireRole("admin")` `routes/admin.ts:11`; role CHECK `migrations/0001_init.sql:9` | A support agent inherits pricing writes (`admin.ts:349`), system config (`:488`), KYC approval (`:821`) and captain suspension (`:289`). One phished console session is total platform compromise | confirmed |
| F-02-06 | S2 | Audit writes fail silently — the insert is wrapped in a swallow-all catch and no call site checks a result | `lib/audit.ts:33-36`; all nine call sites e.g. `routes/admin.ts:273`, `:402`, `:522` | A privileged mutation can succeed with no audit row and return 200. The trail is unreliable exactly when D1 is under stress | confirmed |
| F-02-07 | S2 | Admin document images may authenticate via `?token=`, and the token accepted is a full admin JWT, not a scoped one | allowlist `middleware/auth.ts:21-27`, entry at `:25`; route `routes/admin.ts:894` | A URL carrying live admin credentials for every admin endpoint lands in access logs, proxy logs, browser history and `Referer`. Console currently uses the safe blob path (`apps/admin/src/lib/api.ts:28-33`), so this is latent | confirmed |
| F-02-08 | S2 | Any online captain can bid on any open trip; there is no check that they were dispatched or offered it | `routes/trips.ts:1144`; status check `:1157`; online check `:1165`; insert `:1170-1174` | Captains outside the dispatch set — including other cities — inject themselves into the rider's bid list and can be selected | confirmed |
| F-02-09 | S2 | The captain trip list returns `SELECT *` for every open trip in the city, not only dispatched ones | `routes/trips.ts:634-637` | Every captain sees rider ids, promo codes, discounts, B2B billing flags, offered price and full coordinates for all open rides in their city | confirmed |
| F-02-10 | S2 | `POST /safety/sos` accepts an arbitrary `tripId` with no participant check | `routes/safety.ts:15`, insert at `:22-25`; admin fan-out at `:29-38` | Any authenticated user raises emergency alerts against trips they are unrelated to, pushing to every admin. Poisons the one channel that must stay trustworthy | confirmed |
| F-02-11 | S3 | The captain's raw phone number is returned on trip reads and embedded in the Durable Object broadcast payload | `routes/trips.ts:136` (`u.phone AS captain_phone`), used at `:676` and `:164`; also `:1238` | Riders harvest captain phone numbers across trips; no proxy/masked-number layer exists | confirmed |
| F-02-12 | S3 | The device-token UPSERT reassigns `user_id` to the caller on token conflict | `routes/devices.ts:19-27` (`ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id`) | A party who learns another user's FCM token registers it to their own account and receives that user's trip notifications | likely |
| F-02-13 | S3 | `POST /promos/validate` is an existence-and-value oracle for any authenticated user | `routes/promo.ts:10`, lookup at `:14-17` | Full promo namespace enumeration; discount type, value, `max_uses` and `uses_count` exposed, enabling timed exploitation of near-exhausted codes | confirmed |
| F-02-14 | S3 | Share tokens are never revoked when the trip completes or is cancelled | insert `routes/safety.ts:73-78`; TTL up to 7 days `lib/schemas.ts:99`; no revocation anywhere in `routes/trips.ts` | A shared link keeps returning pickup and dropoff addresses — often a home address — for up to a week after the trip ended | confirmed |
| F-02-15 | S3 | Both geocoding endpoints are unauthenticated, guarded only by a per-IP rate limit | `routes/geocode.ts:8-10`, `:26` | Anonymous callers drive metered upstream geocoding spend; IP rotation defeats the only control | confirmed |
| F-02-16 | S3 | `search.ts` declares `/admin/search` with `authMiddleware` but no `requireRole`, relying on an inline check, and is mounted at root | `routes/search.ts:6`, `:8`; mounts `index.ts:111` vs `:116` | Dead today — the guarded `admin.ts:551` handler wins. Becomes an admin-data leak the moment mount order changes or a second route is added to that router | confirmed (empirical) |
| F-02-17 | S3 | `advanceStatus` reads, validates, then writes without a status predicate in the UPDATE | `routes/trips.ts:899` read, `:903` captain check, `:906` transition check, `:913` UPDATE | Concurrent `/arrived` or `/start` calls both commit, producing duplicate trip events and double notifications. Contrast `:974` and `:862`, which do use a CAS | confirmed |
| F-02-18 | S3 | `GET /captain/file/*` builds the R2 key from the raw request path with no `..` rejection | `routes/captain.ts:675`, prefix check `:679-682` | Cross-captain reads are blocked by the prefix check, so impact is limited to the caller's own folder. The sibling avatar route already rejects `..` (`routes/user.ts:51`) — this one should match | confirmed |
| F-02-19 | S4 | `PATCH /companies/admin/employee/:id` neither scopes the employee to a company nor writes an audit row | `routes/companies.ts:144`, UPDATE at `:149-151` | Admin-only, so no tenant breach — but the one company mutation with no trail, while creation (`:90`) and invoicing (`:199`) are both logged | confirmed |
| F-02-20 | S4 | The admin bootstrap secret may be supplied in the request body as well as a header | `routes/auth.ts:438-439` | Bodies are logged by WAFs and proxies far more often than headers; a leaked `ADMIN_SETUP_SECRET` is permanent until rotated | confirmed |

### 4.1 Verified non-findings

These are patterns that look dangerous and are not. They are recorded because a reader
scanning this codebase will reach for each of them, and because two of them nearly
became findings in this document.

| Pattern | Why it is safe | Evidence |
|---|---|---|
| `use("/admin/*")` appearing to miss the bare `/admin` path in `companies.ts` | In Hono 4.7.11 a trailing `/*` **does** match the parent path. I wrote this up as an S1 cross-tenant breach, then executed it against real Hono and deleted the finding | §3.1 Test B; `routes/companies.ts:68`, `:70`, `:99` |
| Share tokens looking guessable | `id()` is `crypto.randomUUID()` with dashes stripped — 122 bits | `lib/utils.ts:9-12`, used at `routes/safety.ts:71` |
| `GET /captain/file/*` taking its key from the URL | Own-folder prefix check blocks cross-captain reads; upload keys are pinned to the caller | `routes/captain.ts:679-682`, `:664`, `:544-545` |
| `POST /auth/admin/setup` being unauthenticated | Two guards in series, both fail-closed: "no admin exists" then a required `ADMIN_SETUP_SECRET`. An unset secret **denies** rather than allows | `routes/auth.ts:427-430`, `:438-443` |
| Self-registration choosing a role | Clamped by ternary — anything that is not `"captain"` becomes `"rider"` | `routes/auth.ts:367` |
| Mass assignment | No handler spreads a body into SQL. Every write uses an explicit column list with positional binds, and bodies pass a zod schema first | `lib/schemas.ts` throughout; e.g. `routes/user.ts:97-100`, `routes/trips.ts:441-481` |
| SQL injection | Every user value is bound with `?`. The three interpolated fragments are hardcoded literals chosen by a ternary, never user data | `routes/admin.ts:91`, `:104`, `:665-673` |
| Audit log deletion | No DELETE or UPDATE against `audit_log` exists anywhere; the only endpoint is a read | `routes/admin.ts:219-227` |
| Auction leakage between captains | `GET /:id/bids` is rider-or-admin only, so a captain cannot read competitors' prices | `routes/trips.ts:1225` |
| Captain payout draining a wallet | The UPDATE carries `AND wallet_balance >= ?` and a zero-rows result returns 409 | `routes/wallet.ts:113-121` |
| Intercity passenger manifest | Bound to the schedule's assigned captain before the PII query runs | `routes/intercity.ts:344-352` |
| Paymob webhook forgery | HMAC verified, and rejected before any state change, with an audit row on rejection | `routes/payments.ts:104-114` |

### 4.2 The S1 findings in detail

**F-02-01 — the fleet is readable without an account.**

`tripRoutes.post("/estimate", ...)` is registered at `routes/trips.ts:315`.
`tripRoutes.use("*", authMiddleware)` is registered at `routes/trips.ts:346`. Hono applies
`.use()` middleware only to routes registered after it, so the estimate handler executes
with an empty middleware chain — verified by execution, not inference (§3.1 Test A).

The handler is not a pure fare calculator. At `routes/trips.ts:336` it calls
`findNearbyCaptains(c.env, city, body.pickupLat, body.pickupLng, 15)` and at `:342`
returns the result to the caller verbatim. `NearbyCaptain` is
`{ userId, distanceKm, name }` (`lib/nearby.ts:55-58`).

So an anonymous caller supplying any coordinate pair receives the internal user id, the
display name, and the precise distance of every online captain in the surrounding
geohash cells. Three probes around a target give a position by trilateration. Sweeping a
grid over Cairo enumerates the entire active fleet, continuously, with no account and no
attribution. The harvested `userId` values are the same identifiers the rest of the API
uses in paths, which makes this a staging step for any object-level attack elsewhere.

The only control is `rateLimit({ prefix: "estimate", limit: 30, windowSec: 60 })` at
`:317` with no `keyFn`, so it buckets by `cf-connecting-ip` — 30 requests per minute per
address, trivially parallelised across a proxy pool.

The comment at `:326-329` explains why the probe exists: the rider app calls this
endpoint with a zero-length route purely to draw nearby cars on the map before login. The
feature is legitimate. Its placement above the auth guard, and the decision to return
identities rather than anonymous positions, are not.

**F-02-02 — a trip can be marked paid for one pound, including someone else's trip.**

`intentionSchema` (`routes/payments.ts:12-18`) takes `amount: z.number().min(1)` and
`tripId: z.string().optional()` straight from the request body. Neither is validated
against anything. At `:46` the caller's amount is passed to Paymob, and at `:71` and
`:74` it is written to the `payment_intentions` row as
`Math.round(body.amount * 100)` alongside the unvalidated `trip_id`.

The webhook does check for tampering — `if (amountCents !== intention.amount_piastres)`
at `:148` — but both sides of that comparison descend from the same number the attacker
chose. The check catches a dishonest PSP; it cannot catch a dishonest client, because
the client defined the expected value.

On success with `purpose === "trip_payment"` the webhook executes
`UPDATE trips SET payment_status = 'paid' WHERE id = ?` bound to `intention.trip_id`
(`:200-205`), with no comparison against the trip's `final_fare` or `estimated_fare`, and
no check that the intention's `user_id` is that trip's `rider_id`.

Two exploits follow. A rider creates an intention for their own 500 EGP trip with
`amount: 1`, pays one pound through the real Paymob flow, and the trip settles as paid.
Or a rider supplies **another** rider's `tripId` and settles a stranger's fare for one
pound — the trip id being obtainable from F-02-01's identifier harvest or simple
enumeration. Both paths produce a genuine, HMAC-valid webhook; nothing downstream is
suspicious.

The fix is one lookup: derive the amount server-side from the trip row and reject an
intention whose `tripId` is not owned by the caller. The trip fare is already in D1 at
the moment the intention is created.

**F-02-03 — the trip-sharing safety feature does not work.**

`safetyRoutes.use("*", authMiddleware)` at `routes/safety.ts:11` covers every route
registered after it, including `GET /track/:token` at `:90`. That path is not in
`queryTokenAllowed` (`middleware/auth.ts:21-27`), so a recipient without a bearer token
receives 401 before the handler runs. The endpoint's own comment at `:88-89` describes it
as "public read-only view for shared trips" — the intent is unambiguous and the
implementation contradicts it.

Independently, the URL handed back to the sharing rider is
`https://api.synapticstudio.tech/track/${token}` (`:83`), while the route is mounted
under `/safety` (`index.ts:120`) and therefore lives at `/safety/track/:token`. Even with
the auth issue resolved, the emitted link 404s.

Everything else about the feature is correct: creation is participant-checked (`:67`),
the token is 122-bit random (`lib/utils.ts:9-12`), expiry is enforced at read time
(`:99`), revocation is honoured (`:98`), owner-scoped deletion works (`:130`), and the
payload is deliberately minimal — status, addresses and last known point, no phone
numbers. The plumbing was built properly and then wired to nothing.

I have graded this S1 rather than S2 because of what the rider is told. `POST /safety/share`
returns `ok: true` with a URL and an expiry. The app can reasonably render "your trip is
being shared". A passenger in a car at night, who believes their sister is watching their
dot move across a map, is not being protected. A safety feature that fails silently is
worse than one that is absent, because it displaces the behaviour that would have kept
the person safe.

### 4.3 The S2 findings in detail

**F-02-04 — privilege changes do not take effect until the token expires.**

`authMiddleware` sets the request principal directly from verified claims
(`middleware/auth.ts:55-60`). There is no D1 read on the hot path, and `users.status` is
never consulted. Access tokens live 15 minutes (`lib/jwt.ts:8`).

Issuance is handled correctly — login and refresh both re-read the row and reject
suspended users (`routes/auth.ts:392`/`:398`, `:297`/`:301`) — so this is bounded, not
unbounded. But `POST /admin/captains/:id/suspend` (`routes/admin.ts:289`) writes D1 and
nothing else, which means an admin suspending a captain for a safety incident has not
actually stopped them: that captain can keep accepting and running trips for the
remainder of their token's life. For the fifteen minutes after a decision to remove
someone from the platform, the platform still trusts them.

The general fix is a revocation check on the hot path. `SESSIONS` KV is already bound and
already used for rate limiting and ETA caching, and a KV read is a few milliseconds — a
`revoked:<userId>` or `revoked:<jti>` key checked in `authMiddleware` closes this. The
session/refresh semantics of that mechanism belong to **T01**; what this track asserts is
the requirement: an authorization decision must be revocable inside seconds, not minutes.

**F-02-05 — one admin tier for every job.**

`requireRole` compares against a flat role string (`middleware/auth.ts:67`) and
`routes/admin.ts:11` applies `requireRole("admin")` to the whole file. `users.role` admits
three values and no more (`migrations/0001_init.sql:9`); no migration adds a permission,
scope, or tier column.

So the account used to answer "where is my driver" also holds: rewriting fare rules for a
city (`admin.ts:349`), changing commission and cancellation fees platform-wide
(`admin.ts:488`), approving a captain onto the road (`admin.ts:261`), viewing every
captain's national ID scan (`admin.ts:894`), and reading the full user table
(`admin.ts:326`). The blast radius of one phished support login is the entire business.

Uber and Careem both solve this with scoped internal roles; Careem additionally scopes by
city so an ops agent in Alexandria cannot act on Cairo. That regional dimension matters
here because `pricing_rules` is already keyed by city (`admin.ts:349` takes `:city`), so
the data model is ready for it before the authorization model is.

**F-02-06 — the audit trail is best-effort.**

`logAudit` catches everything and logs to `console.error` (`lib/audit.ts:33-36`). The
comment — "Never break the main request because of audit failures" — is a defensible
default for low-value telemetry and the wrong default for a compliance trail attached to
KYC approvals and pricing changes.

Coverage is complete, which makes this more frustrating: someone did the work to
instrument all nine mutating endpoints, and the guarantee is undermined by the helper. A
D1 write failure — quota, timeout, contention during an incident — produces a successful
privileged mutation with no record, and nobody learns this until they go looking for the
row and it is not there. Note the correlation: audit inserts are most likely to fail
precisely when the database is under stress, which is when incidents happen.

The mutation and its audit row should be one transaction where the operation is
reversible, or the failure should surface. At minimum a failed audit write must increment
a counter that alerts.

**F-02-07 — a full admin token in a URL.**

`queryTokenAllowed` (`middleware/auth.ts:21-27`) permits `?token=` for exactly two path
shapes: WebSocket upgrades, and `/admin/documents/<id>/file` (`:25`). The reasoning in the
comment is sound — an `<img>` tag cannot set an Authorization header.

The problem is the credential. The token accepted is an ordinary admin access token
carrying `role: "admin"`, valid against every endpoint in `admin.ts`. Nothing scopes it to
this document, this path, or this operation. Any URL constructed this way puts complete
admin authority into the query string, which is the single most log-prone place to put a
secret.

Today this is latent rather than live: the console fetches with a bearer header and
creates a blob URL (`apps/admin/src/lib/api.ts:28-33`), so the leaky path is not exercised.
That is exactly why it should be closed now — the allowlist entry is an invitation for the
next developer who reaches for `<img src>` and finds that it works.

The right shape is a short-lived, single-document capability: a signed URL scoped to one
`r2_key` with a sixty-second expiry, which grants nothing else even if it leaks.

**F-02-08 — bidding is open to captains who were never offered the trip.**

`POST /trips/:id/bid` (`routes/trips.ts:1144`) checks role (`:1144`), trip status
(`:1157`) and that the captain is online (`:1165`). It never checks that this captain is
in the trip's dispatch set. The insert at `:1170-1174` binds `user.id` with no membership
predicate.

Given a trip id, any online approved captain — in any city, at any distance — can place a
bid that appears in the rider's list. This defeats the search-radius contract that
`DbCaptain.search_radius_km` documents as gating "the browsable queue, the pushed offers
inbox AND the dispatch fanout" (`lib/types.ts:40-47`): a captain excluded from all three
can still bid directly. It also interacts badly with F-02-09, which hands every captain
in the city the ids of all open trips.

**F-02-09 — every captain sees every open trip in the city, in full.**

`routes/trips.ts:634-637` runs
`SELECT * FROM trips WHERE captain_id = ? OR (status IN ('searching','offered') AND city = ?)`.
The comment above it (`:621-626`) records that this was already tightened once, from
nationwide to city-scoped. It is still `SELECT *` over a table that carries `rider_id`,
`promo_code`, `discount`, `company_id`, `cost_center`, `billed_to_company`,
`accepted_price`, `route_geometry` and both coordinate pairs (`lib/types.ts:50-91`).

A captain does not need a rider's promo code or their employer's billing arrangement to
decide whether to take a job. The row should be projected to the fields the offer card
renders, and the open-trip branch should respect the same radius the dispatch path uses.

**F-02-10 — anyone can raise an emergency on anyone's trip.**

`POST /safety/sos` (`routes/safety.ts:15`) takes an optional `tripId` and inserts it
directly (`:22-25`) with no check that the caller is on that trip. It then pushes to every
admin (`:29-38`).

The direct harm is modest — no data is returned to the caller — but the target is the one
channel that must never be noisy. An operator who learns that SOS alerts are frequently
bogus will start triaging them slowly, and that is the actual risk: not the false alert,
but the real one behind it. The same three-party predicate used four times elsewhere in
this very file (`:67`, `:160`, `:224`, `:268`) is all that is needed.

## 5. Benchmark gap

Two OWASP API Security categories define this axis. **API1:2023 — Broken Object Level
Authorization (BOLA)** is the discipline of binding every id to its caller. **API5:2023 —
Broken Function Level Authorization (BFLA)** is the discipline of ensuring a role cannot
reach a function meant for another role.

**On BFLA, Synaptic Go is in reasonable shape.** Role gates are present and, with the two
exceptions in this document, correctly placed. `requireRole` is applied at the router
level in `admin.ts`, `captain.ts` and the intercity/companies admin sub-trees, and inline
where the file mixes audiences. There is no endpoint where a rider can invoke a captain
function or vice versa.

**On BOLA the picture is uneven.** `trips.ts` and `safety.ts` apply a consistent
three-party predicate; `user.ts`, `wallet.ts` and `captain.ts` scope every query to the
caller. Then `payments.ts` accepts a `tripId` from the body and never looks at who owns
it (F-02-02). One file's discipline did not reach another's, because the discipline lives
in convention rather than in a shared helper.

| Mechanism | Uber | Careem | inDrive | Synaptic Go |
|---|---|---|---|---|
| Media access (ID scans, licences) | Short-lived signed URLs scoped to one object | Signed URLs | Signed URLs (assumed) | Authenticated proxy route, correct authorization, but `?token=` accepts a full admin JWT (F-02-07) |
| Internal admin roles | Fine-grained scopes with just-in-time elevation and per-action audit | Regional scoping — an ops agent in one city cannot act on another | Tiered support roles (assumed) | One omnipotent `admin` (F-02-05) |
| Credential revocation | Central session service; revocation effective immediately | Immediate (assumed) | Immediate (assumed) | None on the hot path; up to 15 min lag (F-02-04) |
| Driver contact | Masked/proxy numbers for both parties | Masked numbers | In-app contact | Raw `captain_phone` in trip payloads (F-02-11) |
| Pre-auth surface | Anonymous supply view returns positions only, never identities | Same | Same | Returns `userId` and `name` (F-02-01) |
| Payment amount authority | Server-derived from the trip; client never proposes | Server-derived | Server-derived | Client-supplied (F-02-02) |
| Trip sharing | Unauthenticated tokenised link, revoked at trip end | Unauthenticated link | Unauthenticated link | Requires a JWT; link 404s (F-02-03) |

Confidence on competitor behaviour: Uber's signed-media and scoped-internal-roles model
and Careem's regional admin scoping are **confident** — both are publicly documented in
engineering and security material, and the regional model is visible in Careem's ops
tooling. The inDrive column and the "immediate revocation" claims for Careem/inDrive are
**assumed** from general industry practice and should not be cited as fact.

The gap that matters is not any single row. It is that **the anonymous supply view returns
identities**, and that **the client is trusted to state what it owes**. Both are decisions
no mature ride-hailing backend makes, and both are cheap to reverse now and expensive to
reverse after launch.

## 6. Improvement plan

### P0.1 — Move `POST /trips/estimate` under the auth guard and stop returning identities

- **Goal** — The anonymous fleet roster stops being downloadable; the rider app keeps its pre-login map of nearby cars.
- **Design** — Two independent changes. (a) Move the `tripRoutes.use("*", authMiddleware)` call from `trips.ts:346` to immediately after the router is constructed at `:22`, so the file has no pre-auth region at all; keep the estimate route's own rate limit. (b) Change the estimate response to return anonymised supply: replace each `NearbyCaptain` with `{ lat, lng }` snapped to a ~100 m grid, dropping `userId` and `name` entirely — the map only draws dots. If a genuinely pre-login estimate is a product requirement, add a separate `POST /public/estimate` that returns fare and a `nearbyCount: number` with no per-captain array.
- **Files to change** — `apps/api/src/routes/trips.ts` (guard placement, response shape at `:342`), `apps/api/src/lib/nearby.ts` (add an anonymised projection alongside `NearbyCaptain`), `apps/rider` map widget for the new shape.
- **DB** — none.
- **API contract** — `POST /trips/estimate` now requires `Authorization`. Response `nearbyCaptains: Array<{userId,distanceKm,name}>` → `nearbyCars: Array<{lat,lng}>`. Optional new `POST /public/estimate` → `{ city, fare…, nearbyCount }`.
- **Effort** — S.
- **Risk** — The rider app's pre-login map breaks if it calls this before a token exists. Mitigate by shipping `/public/estimate` in the same change and pointing the pre-login map at it. Rollback is a one-line revert of the guard move.
- **Acceptance criteria** — `curl -X POST /trips/estimate` with no Authorization header returns 401. No response body anywhere in the API contains a captain `userId` for a captain the caller is not matched with. A grid sweep of 1,000 coordinates yields zero identifiers.
- **Tests** — Integration test asserting 401 unauthenticated. Contract test asserting the estimate response has no `userId` key. A regression test that fails if any route in `trips.ts` is registered before the guard (see P0.5).

### P0.2 — Derive payment amounts server-side and bind the intention to its trip

- **Goal** — A trip can only be settled for what it actually costs, and only by its rider.
- **Design** — In `POST /paymob/intention`, branch on `purpose`. For `trip_payment`: require `tripId`, load the trip, reject with 403 unless `trip.rider_id === user.id`, reject unless status is `completed`, and compute `amount` from `COALESCE(final_fare, estimated_fare)` — ignore any client-supplied `amount` entirely. For `intercity_booking`: same treatment against `intercity_bookings.fare` with `rider_id` ownership. Only `wallet_topup` may keep a client-chosen amount, bounded by a configured maximum. In the webhook, before `UPDATE trips SET payment_status='paid'`, re-assert `intention.amount_piastres` equals the trip's fare in piastres and that the trip is not already paid.
- **Files to change** — `apps/api/src/routes/payments.ts` (`:12-18` schema, `:43-77` handler, `:197-212` settlement branch).
- **DB** — none required. Optionally add `CHECK (amount_piastres > 0)` on `payment_intentions` in a new migration `0020_payment_intention_guards.sql`, plus a partial unique index preventing two settled intentions for the same `trip_id`.
- **API contract** — `POST /payments/paymob/intention` — `amount` becomes ignored (and later removed) for `trip_payment` and `intercity_booking`; `tripId` becomes required for `trip_payment`. New errors: `403 NOT_TRIP_OWNER`, `409 TRIP_ALREADY_PAID`, `400 TRIP_NOT_COMPLETED`. Response continues to return the server-computed `amount` so the client can display it.
- **Effort** — S.
- **Risk** — A client that renders its own amount before opening the iframe will show a mismatch if it disagrees with the server; the response already returns the authoritative figure, so the app should display that. Rollback is safe — the change only narrows what is accepted.
- **Acceptance criteria** — An intention for `purpose:"trip_payment"` with `amount:1` on a 500 EGP trip is created for 50000 piastres, not 100. An intention naming another rider's `tripId` returns 403. A second settlement for an already-paid trip returns 409 and does not write.
- **Tests** — Unit tests for each `purpose` branch. An end-to-end test replaying a real webhook body against a tampered intention. A test asserting a foreign `tripId` is rejected at intention time.

### P0.3 — Make trip sharing actually work

- **Goal** — A family member without an account can open the link and watch the trip.
- **Design** — Register `GET /track/:token` **before** the `authMiddleware` line in `safety.ts` — moving the route above `:11` is the minimal change and mirrors the pattern the codebase already uses. Better: mount a tiny `publicRoutes` router in `index.ts` that carries no auth middleware at all and owns this one endpoint, so the exemption is explicit rather than order-dependent. Fix the emitted URL at `:83` to point at the real path, sourced from an env var rather than hardcoded. Add revocation on trip end: in the `/complete` and `/cancel` handlers, `UPDATE trip_share_tokens SET revoked_at = ? WHERE trip_id = ? AND revoked_at IS NULL`, with a short grace period (5 minutes) so the recipient sees the arrival.
- **Files to change** — `apps/api/src/routes/safety.ts` (`:11`, `:83`, `:90`), `apps/api/src/index.ts` (public router mount), `apps/api/src/routes/trips.ts` (revocation in `/complete` `:951` and `/cancel` `:709`).
- **DB** — none; `revoked_at` already exists on `trip_share_tokens`.
- **API contract** — `GET /safety/track/:token` becomes genuinely unauthenticated. Response unchanged. `POST /safety/share` returns a correct absolute URL.
- **Effort** — S.
- **Risk** — Deliberately exposing an endpoint. Bounded by the 122-bit token, expiry enforcement at `:99`, revocation at `:98`, and the minimal payload. Add a per-token rate limit to prevent a leaked link being used as a polling firehose.
- **Acceptance criteria** — `curl` with no Authorization header against a fresh share URL returns 200 and trip status. The URL returned by `POST /safety/share` resolves without editing. Five minutes after `/complete`, the same URL returns 410.
- **Tests** — Integration test for the unauthenticated fetch. Test that expired, revoked, and post-completion tokens all return 410. Test that the returned URL string matches the mounted route.

### P0.4 — Bind SOS to trip participation

- **Goal** — The emergency channel stays credible.
- **Design** — Apply the same three-party predicate already used at `safety.ts:67`: when `tripId` is present, load the trip and reject unless the caller is its rider, its captain, or an admin. Keep accepting an SOS with no `tripId` — a user in danger outside a trip must still be able to raise one.
- **Files to change** — `apps/api/src/routes/safety.ts:15-26`.
- **DB** — none.
- **API contract** — `POST /safety/sos` gains `403 NOT_TRIP_PARTICIPANT`.
- **Effort** — S.
- **Risk** — Very low. Guard against over-tightening: do not require an active trip status, since an SOS may legitimately arrive just after completion.
- **Acceptance criteria** — An SOS naming a trip the caller is not on returns 403 and writes no row. An SOS with no `tripId` still succeeds.
- **Tests** — Two integration tests, one per branch.

### P0.5 — A structural test that makes ordering bugs impossible to reintroduce

- **Goal** — F-02-01 can never recur silently, in any route file.
- **Design** — A test that imports each router and asserts its authentication posture rather than trusting review. Build a table of every mounted path and its expected minimum principal (anonymous / authenticated / role). For each, issue a request through `app.request()` with no credentials and assert 401 for everything not explicitly allowlisted as public. The allowlist is short and should be reviewed as a unit: `/`, `/health`, `/auth/*` (bar `/auth/me` and `/auth/logout`), `/intercity/routes*`, `/intercity/schedules*`, `/geocode/*` (until P1.4 lands), `/payments/paymob/webhook`, and `/safety/track/:token` (after P0.3).
- **Files to change** — new `apps/api/test/auth-posture.test.ts`; proposed CI YAML goes in `docs/plan/assets/02-auth-posture-ci.yml.txt` rather than `.github/workflows/**`.
- **DB** — none.
- **API contract** — none.
- **Effort** — M.
- **Risk** — None to production. The main cost is keeping the table current; make adding a route without a table entry a test failure.
- **Acceptance criteria** — Deleting the `use("*", authMiddleware)` line from any route file fails the suite. Adding a new route without an entry fails the suite.
- **Tests** — This item is the test.

### P1.1 — Admin sub-roles

- **Goal** — A support agent cannot change pricing, approve KYC, or read the full user table.
- **Design** — Add `admin_role` to `users`, constrained to `support | ops | finance | superadmin`, defaulting existing admins to `superadmin` so nothing breaks on deploy. Extend `requireRole` with a companion `requireAdminRole(...tiers)` reading the tier from D1 rather than the token — this avoids widening the JWT and sidesteps F-02-04 for the highest-value decisions. Map endpoints: pricing and system-config → `finance` + `superadmin`; captain approval, suspension and document review → `ops` + `superadmin`; read-only stats, trips and live-trips → all tiers; the full user table and document file access → `ops` + `superadmin`. Given `pricing_rules` is already city-keyed, add an optional `admin_city` column now to allow Careem-style regional scoping later without a second migration.
- **Files to change** — `apps/api/src/middleware/auth.ts` (new guard), `apps/api/src/routes/admin.ts` (per-endpoint tiers), `apps/admin/src/lib/auth.tsx` (surface the tier so the console hides what it cannot use).
- **DB** — `0021_admin_sub_roles.sql`: `ALTER TABLE users ADD COLUMN admin_role TEXT;` `ALTER TABLE users ADD COLUMN admin_city TEXT;` plus `UPDATE users SET admin_role='superadmin' WHERE role='admin';`
- **API contract** — Existing endpoints gain `403 INSUFFICIENT_ADMIN_ROLE`. `GET /auth/me` returns `adminRole` for console UI gating.
- **Effort** — M.
- **Risk** — Locking out a live operator. Mitigate with the default-to-`superadmin` migration and a staged rollout: ship the column and the guard reading it, verify tiers in staging, then demote real accounts deliberately.
- **Acceptance criteria** — An account with `admin_role='support'` receives 403 on `PUT /admin/pricing/:city` and 200 on `GET /admin/stats`. Every admin endpoint has an explicit tier.
- **Tests** — A matrix test over {support, ops, finance, superadmin} × every admin endpoint, asserted against a checked-in expectation table.

### P1.2 — Revocation on the hot path

- **Goal** — Suspending a captain or demoting an admin takes effect in seconds.
- **Design** — On suspend/demote, write `revoked:<userId>` to `SESSIONS` KV with a TTL matching the access-token lifetime. In `authMiddleware`, after signature verification, read that key and reject with 401 `SESSION_REVOKED` if present. One KV read per request, single-digit milliseconds, and self-cleaning. Coordinate with **T01**, which owns refresh rotation and logout semantics — this item is only the authorization-side requirement.
- **Files to change** — `apps/api/src/middleware/auth.ts:49-64`, `apps/api/src/routes/admin.ts:289` (suspend writes the key).
- **DB** — none; KV only.
- **API contract** — New `401 SESSION_REVOKED`.
- **Effort** — S.
- **Risk** — A KV outage would fail-open or fail-closed depending on implementation; choose fail-open for availability and alert on read errors, since the D1 state remains the source of truth at next refresh.
- **Acceptance criteria** — A captain suspended at T+0 receives 401 on their next request, verified with a token minted before the suspension.
- **Tests** — Integration test: mint token, suspend, assert next call is 401.

### P1.3 — Scoped, short-lived document URLs

- **Goal** — No admin JWT ever appears in a URL.
- **Design** — Add `POST /admin/documents/:id/file-url` returning a 60-second capability token scoped to that single `r2_key` — an HMAC over `{r2_key, exp}` with a dedicated secret, not the session JWT. `GET /admin/documents/:id/file` accepts that capability *instead of* the admin JWT via query, and the `/admin/documents/.../file` entry is removed from `queryTokenAllowed`.
- **Files to change** — `apps/api/src/middleware/auth.ts:21-27`, `apps/api/src/routes/admin.ts:894`, `apps/admin/src/lib/api.ts:28-33`.
- **DB** — none.
- **API contract** — New `POST /admin/documents/:id/file-url` → `{ url, expiresAt }`.
- **Effort** — M.
- **Risk** — Breaks any admin UI still using the query-token form; the console's blob path is unaffected.
- **Acceptance criteria** — A request to the file endpoint carrying a valid admin JWT in `?token=` is rejected. A capability token for document A cannot fetch document B, and expires in 60 s.
- **Tests** — Unit tests for capability signing/expiry; integration test asserting the JWT query path now 401s.

### P1.4 — Close the remaining leaks

Grouped because each is small and independently shippable.

- **Bid dispatch binding** (F-02-08) — require a row proving this captain was offered the trip, or that the trip is within their `search_radius_km`, before inserting into `trip_bids`. `routes/trips.ts:1144-1174`. Effort S.
- **Project the captain trip list** (F-02-09) — replace `SELECT *` at `routes/trips.ts:635` with the explicit column set the offer card needs; drop `promo_code`, `discount`, `company_id`, `cost_center`, `billed_to_company`, `rider_id`. Effort S.
- **Mask captain phone** (F-02-11) — remove `u.phone` from `withCaptain` (`routes/trips.ts:136`) and from `routes/trips.ts:1238`; route contact through a masked-number provider or in-app chat, which already exists. Effort M — coordinate with **T17**.
- **Device token conflict** (F-02-12) — change the UPSERT at `routes/devices.ts:21-25` to update only when `user_id` already matches, else insert a fresh row and let the old one expire. Effort S.
- **Promo enumeration** (F-02-13) — per-user rate limit on `/promos/validate` and a uniform error shape so invalid, expired and exhausted are indistinguishable. `routes/promo.ts:10`. Effort S.
- **Geocode auth** (F-02-15) — require `authMiddleware` on both endpoints, or an app-attestation header for the pre-login address picker. `routes/geocode.ts:8`, `:26`. Effort S.
- **Delete the shadowed route** (F-02-16) — remove `routes/search.ts` and its mount, since `admin.ts:551` serves the path. Effort S.
- **CAS in `advanceStatus`** (F-02-17) — add `AND status = ?` with the expected prior status to the UPDATE at `routes/trips.ts:913`, matching `:974` and `:862`, and return 409 on zero rows. Effort S.
- **Traversal guard** (F-02-18) — reject keys containing `..` at `routes/captain.ts:675`, mirroring `routes/user.ts:51`. Effort S.
- **Company employee scope + audit** (F-02-19) — add `AND company_id = ?` to `routes/companies.ts:149-151` and a `logAudit` call. Effort S.
- **Header-only setup secret** (F-02-20) — drop the `body.setupSecret` branch at `routes/auth.ts:439`. Effort S.

### P2.1 — Extract authorization into a shared, testable layer

- **Goal** — Ownership checks stop being a convention that a new file can forget.
- **Design** — Introduce `lib/authz.ts` exposing the predicates this codebase already writes by hand: `assertTripParticipant(env, tripId, user)`, `assertTripOwner`, `assertCompanyMember`, `assertOwnsResource(table, column, id, user)`. Each returns the loaded row so the handler does not query twice. Migrate the existing correct call sites to it — they are already the right shape — so the helper is proven before it is mandated. Then make it the reviewable rule: a handler that takes an id from the path or body and does not call an `assert*` is a review failure.
- **Files to change** — new `apps/api/src/lib/authz.ts`; call sites across `trips.ts`, `safety.ts`, `intercity.ts`, `companies.ts`, `payments.ts`.
- **DB** — none.
- **API contract** — none; error shapes preserved.
- **Effort** — L.
- **Risk** — A large diff across the hottest file in the codebase. Do it after P0, one file per PR, with the P0.5 posture suite as the safety net.
- **Acceptance criteria** — No handler contains an inline three-party predicate. Every id-accepting endpoint calls an `assert*`.
- **Tests** — Unit tests per predicate; the existing endpoint tests must pass unchanged.

## 7. Phasing

**P0 — before any production traffic.** The three S1s plus the two cheapest S2 mitigations
and the structural test that prevents regression.

| Item | Addresses | Phase | Effort | Owner type |
|---|---|---|---|---|
| P0.1 Estimate under auth + anonymised supply | F-02-01 | P0 | S | backend + Flutter |
| P0.2 Server-derived payment amount + trip ownership | F-02-02 | P0 | S | backend |
| P0.3 Public tracking route + correct URL + revoke on end | F-02-03, F-02-14 | P0 | S | backend |
| P0.4 SOS participant binding | F-02-10 | P0 | S | backend |
| P0.5 Auth-posture regression suite | F-02-01, F-02-16 | P0 | M | backend |
| P1.1 Admin sub-roles | F-02-05 | P1 | M | backend + admin |
| P1.2 KV revocation on hot path | F-02-04 | P1 | S | backend |
| P1.3 Scoped document URLs | F-02-07 | P1 | M | backend + admin |
| P1.4a Bid dispatch binding | F-02-08 | P1 | S | backend |
| P1.4b Project captain trip list | F-02-09 | P1 | S | backend |
| P1.4c Audit durability + alert on failure | F-02-06 | P1 | S | backend + ops |
| P1.4d Device token conflict | F-02-12 | P1 | S | backend |
| P1.4e Promo rate limit + uniform errors | F-02-13 | P1 | S | backend |
| P1.4f Geocode auth | F-02-15 | P1 | S | backend + Flutter |
| P1.4g Delete shadowed search route | F-02-16 | P1 | S | backend |
| P1.4h CAS in `advanceStatus` | F-02-17 | P1 | S | backend |
| P1.4i Traversal guard on file key | F-02-18 | P1 | S | backend |
| P1.4j Company employee scope + audit | F-02-19 | P1 | S | backend |
| P1.4k Header-only setup secret | F-02-20 | P1 | S | backend |
| P1.4l Mask captain phone | F-02-11 | P2 | M | backend + Flutter |
| P2.1 Shared authorization layer | all | P2 | L | backend |

Audit durability (F-02-06) sits in P1 rather than P0 deliberately: nothing is currently
lost, and the fix is worth doing properly — surfacing failures and alerting — rather than
hastily.

## 8. Metrics

Instrument these before P0 ships, so the change is provable rather than asserted.

| Metric | How | Current | Target |
|---|---|---|---|
| Unauthenticated requests reaching a handler | Count requests with no principal, by route, excluding the public allowlist | Unknown; at least all `/trips/estimate` traffic | 0 outside the allowlist |
| Captain identifiers in anonymous responses | Contract test scanning estimate responses for `userId` | >0 | 0 |
| 403 rate on object-level checks, by route | Counter in each `assert*` predicate after P2.1 | not instrumented | Baseline, then alert on any spike — a rising rate is enumeration |
| Payment settlement variance | `abs(intention.amount_piastres − trip fare)` at settlement | unmeasured | 0 for every `trip_payment` |
| Share-link success rate | 200 vs 401/404 on `/safety/track/:token` | ~0% for non-app recipients | >95% |
| Median lag from suspend to first 401 | Timestamp of suspend vs next rejected request for that user | up to 15 min | <5 s |
| Audit write failures | Counter incremented in `logAudit`'s catch | silently discarded | 0, alert on ≥1 |
| Admin actions by tier | `audit_log` grouped by actor's `admin_role` after P1.1 | not distinguishable | Every privileged action attributable to a tier |
| Endpoints with an explicit posture assertion | P0.5 table size ÷ mounted route count | 0 / 117 | 117 / 117 |

## 9. Cross-cutting notes

Findings outside this axis, addressed to the track that owns them. Not fixed here.

- **T01 — Auth & Sessions.** (a) There is no revocation check on the request path; `SESSIONS` KV is bound and used for rate limiting but never consulted for session validity (`middleware/auth.ts:49-64`). P1.2 above proposes the authorization-side requirement; the session model is yours. (b) The OTP routes remain **mounted and reachable** at `routes/auth.ts:52` and `:131` — your claim file records OTP as descoped but retains the reachability check, so noting it here as confirmed-reachable at commit `dccc2da`. (c) `POST /auth/admin/setup` accepts the bootstrap secret in the request body as well as a header (`routes/auth.ts:438-439`).
- **T03 — Money Integrity.** `payoutSchema` sets no maximum (`routes/wallet.ts` schema, `min(1)` only), so a single payout is bounded only by the balance. The balance CAS itself is correct (`wallet.ts:113-121`).
- **T04 — Payments/PSP.** The webhook's legacy fallback branch for pre-migration-0011 intentions credits a wallet using the amount from the webhook body with no comparison against an intended amount (`routes/payments.ts:248-265`). HMAC gates entry so it is not externally forgeable, but a PSP-side anomaly would be absorbed silently. Also: F-02-02 changes the intention contract you own.
- **T06 — Dispatch.** F-02-08 (bidding without dispatch membership) and F-02-09 (`SELECT *` over all open city trips) both let a captain act outside the `search_radius_km` contract that `lib/types.ts:40-47` says gates the queue, the inbox and the fanout. The authorization fix is in P1.4; whether the radius contract is the right matching rule is yours.
- **T07 — Realtime/DO.** The WebSocket upgrade at `index.ts:129` performs a proper trip-participant check before handing off (`:157-164`), and `/ws/captain/offers` checks role (`:209-211`). But both support a `pendingAuth` handoff (`:171-177`, `:226-229`) where the DO authenticates the first message — I did not read the DO implementations, so **whether `TripRoom` and `CaptainInbox` actually enforce membership after that handoff is `needs-check` and yours**. Also note `withCaptain`'s payload, including `captain_phone`, is pushed into DO broadcast state (`routes/trips.ts:164`).
- **T08 — Data Model.** `users.role` is a three-value CHECK (`migrations/0001_init.sql:9`) with no tier column; P1.1 proposes `admin_role` and `admin_city` in `0021`. `payment_intentions` would benefit from a partial unique index preventing two settled intentions per `trip_id`.
- **T11 — Admin Console.** The console fetches document images via a bearer header and a blob URL (`apps/admin/src/lib/api.ts:28-33`) — the safe pattern; keep it that way when P1.3 lands. After P1.1 the console should hide controls the operator's tier cannot use rather than letting them 403.
- **T17 — Safety & Trust.** F-02-03 is a safety-feature failure, not just an auth bug — the sharing flow reports success while delivering nothing. F-02-10 lets anyone raise an SOS on any trip. F-02-11 (raw captain phone) is the authorization face of a masked-numbers decision that is really yours.
- **T18 — Fraud & Risk.** F-02-01 is a ready-made supply-intelligence feed for a competitor, and its `userId` harvest is the reconnaissance step for object-level attacks. F-02-13 turns `/promos/validate` into a promo-code scanner.
- **T22 — Observability.** Audit writes fail silently (`lib/audit.ts:33-36`) with no counter and no alert. The metrics in §8 need somewhere to land.
- **T24 — Performance & Cost.** F-02-15: two unauthenticated endpoints proxy a metered geocoding provider behind a per-IP limit only (`routes/geocode.ts:8`, `:26`). F-02-01's estimate endpoint also triggers OSRM routing and nine GeoCell DO reads per anonymous call.
- **T25 — Privacy.** Cross-user avatar reads are by design (`routes/user.ts:197-200`) but make user ids an enumeration oracle. Share tokens expose pickup and dropoff addresses for up to 7 days past trip end (F-02-14). Raw captain phone numbers are distributed to every rider they carry (F-02-11).
- **T27 — Cross-App Parity.** This track is API-side, so parity findings are limited but real. The API exposes `captain_phone` to the rider app while the captain app has no equivalent rider-phone field — contact is asymmetric, and the two apps will diverge in how they offer "call the other party". Both apps consume `POST /safety/share`, whose URL is broken (`routes/safety.ts:83`), so whatever each app renders for sharing is broken in the same way and should be fixed once, centrally. `POST /user/device` takes an `appRole` defaulting to the caller's role (`routes/devices.ts:27`), which is the only place the API distinguishes the two apps — worth confirming both send it consistently, since notification routing depends on it.

## 10. Open questions

Decisions for the product owner. Each with options and a recommendation.

1. **Should a pre-login fare estimate exist at all?**
   The estimate endpoint is unauthenticated because the rider app draws nearby cars before login (`routes/trips.ts:326-329`).
   *Options:* (a) require auth and show the map only after login; (b) keep a public endpoint returning fare plus an anonymous car count and coarse positions, no identifiers; (c) keep it public but gate with app attestation.
   *Recommendation:* **(b).** It preserves the acquisition moment — an empty map converts worse — while removing every identifier. (c) is the stronger control but adds a mobile-attestation dependency this team does not need yet.

2. **How many admin tiers, and does regional scoping matter at launch?**
   *Options:* (a) two tiers — support and superadmin; (b) four — support, ops, finance, superadmin; (c) four plus city scoping.
   *Recommendation:* **(b) now, with the `admin_city` column added in the same migration but unused.** Four tiers match the real job functions. City scoping matters when there is a second city operations team; adding the column now makes that a config change rather than a migration under time pressure.

3. **Masked phone numbers, or in-app contact only?**
   Raw `captain_phone` reaches every rider (`routes/trips.ts:136`), and trip chat already exists (`routes/safety.ts:140`).
   *Options:* (a) status quo; (b) masked numbers via a telephony provider; (c) in-app chat and VoIP only, no numbers.
   *Recommendation:* **(b).** (c) is cleanest and cheapest but fails exactly when it matters — poor connectivity at a pickup — and Egyptian riders and captains expect a phone call. (b) costs per-minute but removes a permanent PII leak in both directions.

4. **What is the share link's lifetime policy?**
   Tokens last up to 7 days (`lib/schemas.ts:99`) and are never revoked at trip end (F-02-14).
   *Options:* (a) revoke at trip end; (b) revoke at trip end plus a 5-minute grace; (c) keep long-lived links as a trip-history feature.
   *Recommendation:* **(b).** The grace period covers the recipient checking that the person arrived, which is the actual purpose. (c) turns a safety feature into a data-retention liability.

5. **Should captains see open trips they were not dispatched?**
   Today they see all of them, in full (F-02-09), and can bid on any (F-02-08).
   *Options:* (a) dispatched offers only; (b) a browsable radius-limited queue with projected fields; (c) status quo.
   *Recommendation:* **(b).** A browsable queue suits the inDrive-style negotiation model this product wants, and `search_radius_km` already exists to bound it (`lib/types.ts:40-47`). But the row must be projected — no rider ids, promo codes, or B2B billing flags.

6. **Fail-open or fail-closed if the revocation store is unreachable?**
   P1.2 adds a KV read to every authenticated request.
   *Options:* (a) fail-open — KV error allows the request; (b) fail-closed — KV error rejects.
   *Recommendation:* **(a), with alerting.** D1 remains the source of truth at the next refresh (≤15 min), so fail-open bounds the exposure while a fail-closed KV incident would take the whole platform down.
