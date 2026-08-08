# 01 — Auth, Identity & Sessions

> Track: A — Foundation & safety-critical · Reviewer: `chat-20260801-1201-378c` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `dccc2dadf206ffaba4d35b3343d55ff279bacaf4`

---

## 1. Scope

This document audits every way a principal becomes and stays authenticated on Synaptic Go: password login, registration, JWT issuance and verification, refresh-token rotation, logout and server-side revocation, session storage, device binding, bot defence, rate limiting, password hashing, mobile token storage, and the admin privilege boundary.

### 1.1 OTP is out of scope — the flow is suspended

**Operator decision, 2026-08-01: the OTP flow is suspended (`متوقف`) and is excluded from this review.** Brief questions 1 and 2 — OTP entropy, storage, TTL, attempt counters, lockout, replay, `devCode` leakage, and OTP-driven role elevation — are **not** audited here. They are recorded as a deliberate scope exclusion, not as "no issues found". The claim file `board/claims/T01.md` carries the same note.

One narrow OTP-adjacent check was **deliberately retained**: whether the suspended OTP routes remain *mounted and reachable* on the live API. A suspended feature left routable is live attack surface, and excluding it entirely would have been unsafe. That check is a reachability question only (see **F-01-15**) — it is not an audit of OTP correctness.

The suspension has a large second-order consequence that *is* in scope and is arguably the most important product finding in this document: with OTP off, **password is the only way into the platform, and there is no password-reset or account-recovery flow of any kind** (see **F-01-04b**). Section 10 asks the product owner to decide on this before launch.

### 1.2 Explicitly not covered (owned by sibling tracks)

| Area | Owner |
|---|---|
| Object-level authorization / IDOR on trip and wallet resources | **T02** |
| Paymob webhook signature verification | **T04** |
| WebSocket / Durable Object transport semantics beyond token handling | **T07** |
| `refresh_tokens` / `users` schema and index design | **T08** |
| Login screen visual design, copy, RTL | **T12**, **T14** |
| Rider ↔ captain duplication as a systemic problem | **T27** |
| Audit-log retention and privacy/GDPR posture | **T22**, **T25** |

---

## 2. What I actually read

Everything below was read from the pinned commit. Line numbers in this document refer to that commit.

**Read in full, personally:**

| File | Lines | Note |
|---|---|---|
| `apps/api/src/routes/auth.ts` | 483 | Every auth endpoint. The core of this review. |
| `apps/api/src/middleware/auth.ts` | 75 | `authMiddleware`, `requireRole`, the `?token=` allowlist. |
| `apps/api/src/lib/jwt.ts` | 96 | Signing, verification, TTLs, `hashToken`. |
| `apps/api/src/middleware/rateLimit.ts` | 90 | Fixed-window KV limiter + `parseBody`. |
| `apps/api/src/lib/turnstile.ts` | 57 | Bot defence, including its fail-open branch. |
| `apps/api/src/routes/devices.ts` | 41 | FCM device tokens — *not* session device binding. |
| `apps/api/src/lib/utils.ts` | 241 | `hashPassword`, `verifyPassword`, `isLegacyHash`, `otpCode`. |
| `apps/api/wrangler.toml` | 180 | `[vars]`, `[env.prod.vars]`, `[env.staging.vars]`, KV bindings. |
| `apps/api/.dev.vars.example` | 51 | Which values are secrets vs vars. |

**Read in the parts that matter for auth:**

| File | Note |
|---|---|
| `apps/api/src/index.ts` (372) | CORS allowlist, global rate limit, route mounting, both WS upgrade handlers. |
| `apps/api/src/routes/intercity.ts` (463) | Read lines 76–145 closely to test a suspected middleware gap (see §4.1). |
| `migrations/0001_init.sql`, `0002_enhancements.sql`, `0003_global_transport.sql` | `users`, `refresh_tokens`, `device_tokens`, `turnstile_verifications` DDL. |
| `apps/api/src/lib/cleanup.ts` | Expired `refresh_tokens` deletion. |
| All 14 files in `apps/api/src/routes/` | Grepped route-by-route for middleware coverage; read handlers where coverage was ambiguous. |

**Read by delegated subagents under my direction — citations then re-verified by me against the files on disk:**

| File | Lines | Note |
|---|---|---|
| `apps/rider/lib/services/app_state.dart` | 696 | Rider token storage, refresh, logout. |
| `apps/captain/lib/services/captain_state.dart` | 1189 | Captain equivalent. Diverges from rider. |
| `apps/admin/src/lib/auth.tsx` | 93 | Admin console auth context. |
| `apps/admin/src/lib/api.ts` | 114 | Admin HTTP client + token helpers. |
| `apps/rider/lib/screens/login_screen.dart` | 1044 | UI only; delegates to `AppState`. |
| `apps/captain/lib/screens/login_screen.dart` | 830 | UI only; delegates to `CaptainState`. |
| `packages/flutter_shared/lib/services/api_client.dart` | 36 | Shared client with no interceptor; unused by auth. |
| `apps/rider/lib/services/trip_ws.dart`, `apps/captain/lib/services/{offers,trip}_ws.dart` | 117/114/132 | WebSocket auth handshake. |
| `apps/api/src/routes/admin.ts` | 937 | Full route inventory for the role gate. |
| `apps/api/src/routes/user.ts` | 328 | Confirmed absence of a password-change route. |

I personally re-read and confirmed the specific lines behind every finding marked `confirmed` below, including the Dart and TSX ones. Where I did not verify something myself, it is marked `likely` or `needs-check` and says so.

**Not read:** the bulk of `trips.ts` (1371), `captain.ts` (700), `payments.ts` (313) beyond their middleware registration lines — they belong to T02/T04/T06.

---

## 3. How it works today

### 3.1 The shape of a session

There are **two** live ways to obtain a token pair (`/auth/register`, `/auth/login`), one suspended way still mounted (`/auth/verify-otp`), one bootstrap (`/auth/admin/setup`), and one renewal (`/auth/refresh`).

`issueTokens()` (`apps/api/src/routes/auth.ts:24-50`) is the single issuance helper:

1. Signs an **access token** — HS256, `typ:"access"`, claims `sub`, `email`, `role`, `name`, `iss`, TTL **15 minutes** (`apps/api/src/lib/jwt.ts:8`, `11-28`).
2. Mints a `jti` (`rt_<uuid>`), signs a **refresh token** — HS256, `typ:"refresh"`, TTL **30 days** (`apps/api/src/lib/jwt.ts:9`, `50-68`).
3. SHA-256-hashes the refresh token (`apps/api/src/lib/jwt.ts:87-91`) and inserts `(jti, user_id, token_hash, expires_at)` into D1 `refresh_tokens` (`apps/api/src/routes/auth.ts:43-47`).

`POST /auth/login` (`apps/api/src/routes/auth.ts:386-421`) does not call `issueTokens()` — it **re-implements the same 12 lines inline** (`:408-414`). Two copies of the issuance path is a maintenance hazard: a fix to one will silently miss the other.

### 3.2 Where sessions actually live — the brief's premise is wrong

The T01 brief asks about "session storage in the `SESSIONS` KV namespace" and the 60-second staleness of KV reads for revocation. **`SESSIONS` KV stores no sessions.** Every use in the codebase:

| Key | Purpose | Cite |
|---|---|---|
| `rl:{prefix}:{ip}:{bucket}` | rate-limit counters | `apps/api/src/middleware/rateLimit.ts:50` |
| `otp-name:{ident}` | transient name during OTP signup (600s) | `apps/api/src/routes/auth.ts:98`, `:192` |
| geocode cache | reverse-geocode / place search | `apps/api/src/routes/geocode.ts:21`, `:34` |
| route cache | trip routing | `apps/api/src/routes/trips.ts:276`, `:305` |
| `cleanup:last-run` | cron guard | `apps/api/src/index.ts:273-276` |

Session state is in **D1** (`refresh_tokens`), which is strongly consistent. So the specific risk the brief anticipated — a revoked refresh token living on for 60 seconds because of KV staleness — **does not exist**. Refresh revocation is immediate.

The real revocation problem is different and worse: **access tokens are not revocable at all** (§4, F-01-06). There is no blocklist, no token version, no `jti` check on access tokens — I grepped the entire API for `blocklist|blacklist|denylist|token_version` and found nothing.

### 3.3 Request authentication

`authMiddleware` (`apps/api/src/middleware/auth.ts:29-65`) takes the bearer token, or — for an allowlisted set of paths — a `?token=` query parameter (`:21-27`: `/ws/*` and `/admin/documents/:id/file`). It calls `verifyToken`, rejects `typ === "refresh"` (`:52-54`), and puts `{id, email, role, name}` on the context.

`verifyToken` (`apps/api/src/lib/jwt.ts:70-85`) calls `jwtVerify(token, key, { issuer })`. It checks **issuer only** — no `audience`, no explicit `algorithms` allowlist, no `clockTolerance` override.

Route coverage, verified file by file:

| Route file | Gate | Cite |
|---|---|---|
| `admin.ts` | `use("*", authMiddleware, requireRole("admin"))` | `apps/api/src/routes/admin.ts:11` |
| `captain.ts` | `use("*", authMiddleware, requireRole("captain","admin"))` | `apps/api/src/routes/captain.ts:24` |
| `trips.ts` | `use("*", authMiddleware)` | `apps/api/src/routes/trips.ts:346` |
| `user.ts` | `use("*", authMiddleware)` | `apps/api/src/routes/user.ts:18` |
| `wallet.ts` | `use("*", authMiddleware)` | `apps/api/src/routes/wallet.ts:10` |
| `devices.ts` | `use("*", authMiddleware)` | `apps/api/src/routes/devices.ts:9` |
| `safety.ts` | `use("*", authMiddleware)` | `apps/api/src/routes/safety.ts:11` |
| `companies.ts` | `use("*", authMiddleware)` | `apps/api/src/routes/companies.ts:11` |
| `search.ts` | `use('*', authMiddleware)` | `apps/api/src/routes/search.ts:6` |
| `promo.ts` | per-handler | `apps/api/src/routes/promo.ts:10,53,60,94` |
| `payments.ts` | per-handler; webhook public by design | `apps/api/src/routes/payments.ts:23,97` |
| `intercity.ts` | mixed: public catalogue, `/bookings/*`, `/admin/*` | `apps/api/src/routes/intercity.ts:79,326,394` |
| `geocode.ts` | **none — fully public** | `apps/api/src/routes/geocode.ts:8,26` |
| `auth.ts` | per-handler (`/logout`, `/me` only) | `apps/api/src/routes/auth.ts:320,461` |

### 3.4 The auth endpoint table

Rate limits are **fixed-window, per source IP**, on top of a global 120 req/60s (`apps/api/src/index.ts:59-66`).

| Method | Path | Who may call | Returns | Rate limit |
|---|---|---|---|---|
| POST | `/auth/request-otp` | public | `{ok, expiresAt, channel}` (+`devCode` iff `DEV_OTP`) | `otp` 5/60s | 
| POST | `/auth/verify-otp` | public | token pair + user + captain; **creates the user if absent** | `otp-verify` 10/60s |
| POST | `/auth/register` | public | token pair + user | `register` 10/60s |
| POST | `/auth/login` | public | token pair + user + captain | `login` 15/60s |
| POST | `/auth/refresh` | bearer of a refresh token | new token pair + user | `refresh` 20/60s |
| POST | `/auth/logout` | authenticated | `{ok}`; revokes **all** the user's refresh tokens | global only |
| POST | `/auth/admin/setup` | public, but needs `ADMIN_SETUP_SECRET` **and** zero existing admins | access token + user | `admin-setup` 3/300s |
| GET | `/auth/me` | authenticated | user (`password_hash` stripped) + captain | global only |

The first two rows are the **suspended** OTP surface. They are still mounted and still fully functional.

### 3.5 Password handling

`hashPassword` (`apps/api/src/lib/utils.ts:21-47`): PBKDF2-SHA256, **100,000 iterations**, 16-byte random salt, 256-bit output, stored as `$pbkdf2$100000$<salt>$<hash>`. That is a sound construction.

`verifyPassword` (`apps/api/src/lib/utils.ts:59-99`) parses the iteration count **out of the stored string** (`:63`) and, for any hash not starting with `$pbkdf2$`, **falls back to a bare unsalted SHA-256 comparison** (`:93-98`). `/auth/login` re-hashes legacy hashes to PBKDF2 after a successful verify (`apps/api/src/routes/auth.ts:402-407`).

### 3.6 What the clients do

Both apps store both tokens in `FlutterSecureStorage` (Keychain / Android Keystore) — rider `apps/rider/lib/services/app_state.dart:49-52`, captain `apps/captain/lib/services/captain_state.dart:339-340`. `SharedPreferences` holds only the display profile, theme and search radius. **This is correct and is the strongest part of the client-side auth story.** No token is logged anywhere; the only `print` calls are `kDebugMode`-gated FCM status lines.

The admin console does the opposite: access token, refresh token and user blob all go to `localStorage` (`apps/admin/src/lib/auth.tsx:46-48`).

All three WebSocket clients have migrated off `?token=` to a first-message `{"type":"auth","token":...}` handshake (`apps/rider/lib/services/trip_ws.dart:57`, `apps/captain/lib/services/offers_ws.dart:55`, `apps/captain/lib/services/trip_ws.dart:73`). The server still accepts the old query form.

---

## 4. Findings

### 4.1 One thing I suspected and disproved

`apps/api/src/routes/intercity.ts:79` registers `intercityRoutes.use("/bookings/*", authMiddleware)` and then defines `post("/bookings", ...)` at `:82`, whose handler calls `c.get("user")` at `:83`. If Hono's `/bookings/*` did not match the bare path `/bookings`, that would be an unauthenticated write that dereferences a null user — an S1.

**It is not a bug.** I installed Hono 4.7.11 (the pinned version from `apps/api/package.json`) and ran the exact route shape against the default SmartRouter. The middleware executes for `POST /intercity/bookings`, `GET /intercity/bookings` and `POST /intercity/bookings/:id/cancel`. Hono's trie router does this deliberately — `src/router/trie-router/node.ts:134` carries the comment `'/hello/*' => match '/hello'`.

Recorded here so no later reviewer re-raises it.

### 4.2 Findings table

| ID | Sev | Finding | Evidence | Impact | Confidence |
|---|---|---|---|---|---|
| F-01-01 | **S1** | Refresh rotation is non-atomic and has no reuse detection | `apps/api/src/routes/auth.ts:279-295` | Stolen refresh token = silent, permanent parallel session | confirmed |
| F-01-02 | **S1** | Logout is client-only; no app ever calls `POST /auth/logout` | `apps/rider/lib/services/app_state.dart:452-455`; `apps/captain/lib/services/captain_state.dart:1141-1173`; endpoint at `apps/api/src/routes/auth.ts:320-345` | "Log out" leaves a live 30-day session | confirmed |
| F-01-03 | **S1** | Bot defence protects only the suspended OTP route; `/login` and `/register` have none, and Turnstile fails open | `apps/api/src/routes/auth.ts:71`; `apps/api/src/lib/turnstile.ts:17-27`; `apps/api/wrangler.toml:149` | Unimpeded credential stuffing and mass fake signup | confirmed |
| F-01-04 | **S2** | No password policy; `/register` bypasses Zod entirely | `apps/api/src/routes/auth.ts:348-357` | `"1"` is a valid password | confirmed |
| F-01-04b | **S2** | No password-change and no account-recovery flow exists anywhere | `apps/api/src/routes/user.ts` (whole file) | With OTP suspended, a forgotten password is unrecoverable | confirmed |
| F-01-05 | **S2** | Rate limiter is fail-open, racy, and per-IP only; no per-account lockout | `apps/api/src/middleware/rateLimit.ts:27-53` | Stated limits are advisory, not enforced | confirmed |
| F-01-06 | **S2** | Access tokens are not revocable; ban and logout leave a ≤15-min live window | `apps/api/src/routes/admin.ts:289-309`; `apps/api/src/lib/jwt.ts:8` | Suspended captain keeps operating | confirmed |
| F-01-07 | **S2** | Admin bearer + 30-day refresh token in `localStorage` | `apps/admin/src/lib/auth.tsx:46-48` | Any admin-console XSS = full platform takeover | confirmed |
| F-01-08 | **S2** | CORS trusts every `*.synapticstudio.tech` subdomain | `apps/api/src/index.ts:46-47` | Subdomain takeover ⇒ credentialed cross-origin admin calls | confirmed |
| F-01-09 | **S2** | No device binding on sessions at all | `apps/api/src/routes/devices.ts:1-42` | Stolen token replays from anywhere, undetected | confirmed |
| F-01-10 | **S2** | Legacy unsalted SHA-256 password hashes still authenticate | `apps/api/src/lib/utils.ts:93-98` | Dormant accounts stay rainbow-table crackable | confirmed |
| F-01-11 | **S2** | Captain app discards rotated refresh tokens (rider does not) | `apps/captain/lib/services/captain_state.dart:262-268`, `:372-380` vs `apps/rider/lib/services/app_state.dart:205-209`, `:435-439` | Captains get logged out once rotation is enforced | confirmed |
| F-01-12 | **S2** | No single-flight guard on client refresh | `apps/rider/lib/services/app_state.dart:294-306`; `apps/captain/lib/services/captain_state.dart:249-276` | Concurrent 401s ⇒ mass logout under rotation | confirmed |
| F-01-13 | **S2** | Suspended OTP surface still mounted; still mints users and 30-day sessions | `apps/api/src/routes/auth.ts:52`, `:131`, `:191-219` | Live account-creation path outside the intended flow | confirmed |
| F-01-14 | S3 | JWT has no `audience`; one secret and one issuer for all three roles; no explicit `algorithms` allowlist | `apps/api/src/lib/jwt.ts:76` | Blast radius of a secret leak is total | confirmed |
| F-01-15 | S3 | `?token=` still accepted for `/ws/*` and admin document files | `apps/api/src/middleware/auth.ts:21-27`; `apps/api/src/index.ts:144` | JWTs in access logs and `Referer` | confirmed |
| F-01-16 | S3 | `/auth/logout` is all-or-nothing — no per-session logout | `apps/api/src/routes/auth.ts:338-342` | Signing out a phone kills the tablet too | confirmed |
| F-01-17 | S3 | User enumeration by timing on `/auth/login` | `apps/api/src/routes/auth.ts:393-395` | Unknown email returns before any PBKDF2 work | confirmed |
| F-01-18 | S3 | PBKDF2 cost is read from the stored hash; 100k is below current guidance | `apps/api/src/lib/utils.ts:63`, `:38` | Silent cost downgrade; weaker offline resistance | confirmed |
| F-01-19 | S3 | No audit entry for identity-document access or bulk user export | `apps/api/src/routes/admin.ts:894-921` | Admin can read every national ID untraced | confirmed |
| F-01-20 | S3 | `/geocode/*` is entirely unauthenticated | `apps/api/src/routes/geocode.ts:8`, `:26` | Free upstream-quota burn | confirmed |
| F-01-21 | S3 | No TLS certificate pinning in either app | `apps/rider/pubspec.yaml`; `apps/captain/pubspec.yaml` | MitM on hostile Wi-Fi | confirmed |
| F-01-22 | S4 | `/auth/login` duplicates `issueTokens()` inline | `apps/api/src/routes/auth.ts:408-414` vs `:24-50` | Fixes will miss one copy | confirmed |
| F-01-23 | S4 | `/auth/admin/setup` returns an access token but no refresh token and writes no `refresh_tokens` row | `apps/api/src/routes/auth.ts:457-458` | First admin is silently logged out after 15 min | confirmed |
| F-01-24 | S4 | Non-constant-time hash comparison | `apps/api/src/lib/utils.ts:90`, `:98` | Not remotely exploitable; hygiene | confirmed |

### 4.3 What is already right

Worth stating plainly, because a review that only lists defects misleads: mobile secure-storage usage is correct and deliberate; `/auth/me` strips `password_hash` before serialising (`apps/api/src/routes/auth.ts:480`); public registration hard-caps the role at rider/captain (`:367`); `/auth/admin/setup` **fails closed** when `ADMIN_SETUP_SECRET` is unset (`:441-443`); `requireRole("admin")` is applied as a single wildcard across every admin route with no per-handler gaps (`apps/api/src/routes/admin.ts:11`); refresh tokens are stored hashed, never in plaintext (`apps/api/src/routes/auth.ts:40`); and the CORS handler explicitly refuses to trust all of `*.pages.dev`, with a comment explaining why (`apps/api/src/index.ts:47-49`).

### 4.4 The S1s and S2s in prose

**F-01-01 — Refresh rotation is non-atomic and has no reuse detection.**
`/auth/refresh` reads the stored row, checks `revoked_at`, then revokes:

```ts
// apps/api/src/routes/auth.ts:293-295
await c.env.DB.prepare(`UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?`)
  .bind(nowIso(), stored.id)
  .run();
```

Two problems.

*Non-atomic.* The `SELECT` at `:279-283` and this `UPDATE` are separate statements with no transaction and no conditional predicate. The `UPDATE` does not say `AND revoked_at IS NULL`, and nothing inspects `meta.changes`. Two concurrent requests bearing the same refresh token both pass the `revoked_at` check and both receive a fresh, valid token pair. One refresh token becomes two independent 30-day session families. The same file uses the correct conditional-update pattern elsewhere (`apps/api/src/routes/intercity.ts:116-124` guards seat claims with `WHERE ... AND seats_booked + ? <= seats_total` and then checks `claim.meta.changes === 0`), so the idiom is understood in this codebase — it simply was not applied here.

*No reuse detection.* When an already-revoked token is presented, the server returns 401 `REFRESH_REVOKED` (`:285-287`) and does nothing else. It does not revoke the token family, does not flag the account, does not audit the event. This is precisely the signal that a refresh token has been stolen, and it is discarded. The attack: steal a refresh token, redeem it once. The victim's next refresh fails, their app calls `logout()` and shows "session expired". They log in again and think nothing of it. The attacker now holds an independent 30-day family that rotates forever. Nobody is alerted, and no record of the event exists.

This is the single most valuable thing to fix in this document.

**F-01-02 — Logout does not log you out.**
The server does the right thing. `POST /auth/logout` revokes the presented refresh token and then every other outstanding refresh token for that user (`apps/api/src/routes/auth.ts:327-342`). But **no client ever calls it.** I grepped the entire `apps/` and `packages/` tree for `auth/logout` and got zero hits. Rider:

```dart
// apps/rider/lib/services/app_state.dart:452-455
Future<void> logout() async {
  await _clearSession();
  notifyListeners();
}
```

Captain is the same (`apps/captain/lib/services/captain_state.dart:1141-1173`). Both delete local storage and return. The refresh token remains valid in D1 for its full 30 days.

Concretely: a captain sells their phone, taps "log out" first, and the buyer's forensic recovery of the app sandbox — or anyone who had already copied the token — retains a working session for a month. Worse, `_executeWithAuthInterceptor` calls the same local-only `logout()` when a refresh fails (`apps/rider/lib/services/app_state.dart:302`), so the app's own reaction to a suspicious auth failure is to discard its evidence and leave the server session alive.

The fix is small — the endpoint already exists and already does a hard revoke. This is a wiring gap, not a design gap, which is what makes it worth doing first.

**F-01-03 — Bot defence guards the one door nobody uses.**
`verifyTurnstile` is called in exactly one place in the entire API:

```ts
// apps/api/src/routes/auth.ts:71 — inside POST /auth/request-otp
const ts = await verifyTurnstile({ token: body.turnstileToken, ... });
```

That is the OTP request route — the suspended flow. `POST /auth/login` (`:386`) and `POST /auth/register` (`:347`) call it nowhere. So with OTP off, **the platform's entire bot defence is attached to a disabled feature**, and the two live entry points have none.

There is a comment at `:63-69` explaining, correctly, that gating Turnstile behind `if (body.turnstileToken)` had let bots bypass it by omitting the field — a real fix, applied to the wrong route to be useful now.

It compounds. `verifyTurnstile` fails **open** when the secret is missing:

```ts
// apps/api/src/lib/turnstile.ts:17-27
const secret = env.TURNSTILE_SECRET_KEY;
if (!secret) {
  // ... inserts a row with verified = 1 and error = "no_secret_skip"
  return { ok: true };
}
```

It returns `ok: true` *and* writes a `turnstile_verifications` row with `verified = 1`. The audit trail will show verified traffic that was never verified. `TURNSTILE_SECRET_KEY` is a `wrangler secret` and therefore not visible in the repo, but `wrangler.toml:149` carries `TURNSTILE_SITE_KEY = "0x4AAAAAAA" # placeholder — set your site key` for production, which strongly suggests the pair was never configured. **Verify this against the deployed secret before launch** — if it is unset, bot defence is absent platform-wide and the dashboard says otherwise (`needs-check` on the deployed value; the fail-open code path itself is `confirmed`).

Together with F-01-04 (any password accepted) and F-01-05 (advisory rate limits, no account lockout), there is no meaningful obstacle to credential stuffing against `/auth/login`.

**F-01-04 / F-01-04b — No password policy, and no way to recover one.**
`/auth/register` does not use the `parseBody` + Zod path that the OTP routes use. It reads raw JSON:

```ts
// apps/api/src/routes/auth.ts:348-357
const body = await c.req.json().catch(() => ({})) as { ... };
if (!body.email || !body.password) {
  return c.json({ error: "email and password required", ... }, 400);
}
```

Presence is the only check. No minimum length, no complexity, no breach-list check, and no email format validation either. `apps/api/src/lib/schemas.ts` contains no password schema at all. `"1"` is an acceptable password for an account that will hold a wallet balance.

And there is no way to change or recover it. `apps/api/src/routes/user.ts` has no password-change route — `PATCH /user/profile` accepts `name` and `phone` only (`:20-23`). There is no forgot-password endpoint anywhere in the API. While OTP was live this was survivable, because OTP was a de facto recovery channel. **With OTP suspended, a user who forgets their password is permanently locked out and support has no self-serve remedy.** For the Egyptian market specifically — where the brief notes users change SIMs frequently — this will generate support load from day one. This is a launch blocker in product terms even though it is not a vulnerability, and it is a direct consequence of the OTP suspension. See §10, Q1.

**F-01-05 — The rate limiter is advisory.**
Three defects in `apps/api/src/middleware/rateLimit.ts`:

*Fails open.* If the KV read throws, the request is allowed through (`:31-34`).

*Racy.* The read (`:29`) and the increment (`:49-53`) are not atomic, and the write is deferred via `waitUntil`, so it does not even complete before the handler runs. Under concurrency, N simultaneous requests all read the same count and all pass. KV's eventual consistency across edge locations widens this further.

*Per-IP only.* The key is the client IP (`:18-22`). There is no per-account counter and no lockout after repeated failed passwords. A credential-stuffing run spread across a modest proxy pool is unconstrained, and a single account can be attacked indefinitely as long as each IP stays under 15/60s.

The published `X-RateLimit-*` headers (`:55-56`) therefore describe a limit that is not reliably enforced.

**F-01-06 — Access tokens cannot be revoked.**
`POST /admin/captains/:id/suspend` sets `users.status` and `captains.approval_status` (`apps/api/src/routes/admin.ts:289-309`) and touches no token state. `/auth/refresh` does block suspended users (`apps/api/src/routes/auth.ts:301-303`), so the session dies at the next rotation — but the *current* access token stays valid for up to its remaining 15 minutes, and no code path anywhere can shorten that. There is no blocklist (grepped: none). A captain suspended for a safety incident can keep accepting trips for a quarter of an hour. The 15-minute TTL is what keeps this at S2 rather than S1.

**F-01-07 / F-01-08 — The admin console is the softest target.**
The admin token, its 30-day refresh token, and the user object all go to `localStorage`:

```tsx
// apps/admin/src/lib/auth.tsx:46-48
localStorage.setItem(TOKEN_KEY, tok);
if (res.refreshToken) localStorage.setItem(REFRESH_KEY, res.refreshToken);
localStorage.setItem(USER_KEY, JSON.stringify(res.user));
```

Any script execution on the console origin reads all three. Because the admin JWT is structurally identical to a rider's apart from `role:"admin"` (F-01-14), that stolen token is full platform authority — approve captains, change pricing, read identity documents.

The CORS policy widens the aperture: `apps/api/src/index.ts:46-47` returns the caller's origin for **any** `*.synapticstudio.tech` host. The same handler pointedly refuses to blanket-trust `*.pages.dev` with a comment explaining that anyone can deploy there — the same reasoning applies to any subdomain the org does not tightly control (marketing pages, staging, a vendor CNAME). One neglected subdomain plus one XSS equals a persistent admin session.

**F-01-09 — Nothing binds a session to a device.**
`routes/devices.ts` is FCM push-token registration; it has no relationship to session identity. `refresh_tokens` stores `(id, user_id, token_hash, expires_at, revoked_at)` and no device, IP, or user-agent column. A refresh token exfiltrated from Cairo works from anywhere in the world, on any device, and the platform cannot tell — there is no signal to detect on and nothing to show the user. Combined with F-01-01 (no reuse detection) there is no mechanism by which token theft is ever discovered.

**F-01-10 — Legacy hashes still work.**
`verifyPassword` falls through to `sha256(password) === storedHash` for anything not prefixed `$pbkdf2$` (`apps/api/src/lib/utils.ts:93-98`). Login transparently upgrades on success (`apps/api/src/routes/auth.ts:402-407`), which is a good migration design — but it only fires when the user logs in. Every dormant account keeps an unsalted, uniterated SHA-256 hash, which is trivially reversed from a database leak using commodity rainbow tables. There is no migration job and no telemetry on how many such rows remain (`needs-check`: the count in production).

**F-01-11 / F-01-12 — Client refresh is where captains will feel it.**
The captain app writes only the access token when refreshing after a 401:

```dart
// apps/captain/lib/services/captain_state.dart:262-268
if (refreshRes.statusCode < 400) {
  final data = jsonDecode(refreshRes.body);
  token = (data['accessToken'] ?? data['token']) as String?;
  if (token != null) {
    await _secureStorage.write(key: 'token', value: token!);
    return await reqFn();
  }
```

The rider app handles the rotation the server actually performs:

```dart
// apps/rider/lib/services/app_state.dart:205-209
// Some backends rotate the refresh token on each use; persist if sent.
final rotated = data['refreshToken'] as String?;
if (rotated != null && rotated.isNotEmpty) {
  await _secureStorage.write(key: _kRefreshToken, value: rotated);
}
```

The server *does* rotate on every refresh (`apps/api/src/routes/auth.ts:293-305`). So a captain's stored refresh token is consumed and its replacement thrown away: the next refresh presents a revoked token and the captain is logged out. `registerWithEmail` has the same defect — it never persists a refresh token at all (`apps/captain/lib/services/captain_state.dart:372-380`), so a newly registered captain is logged out 15 minutes after signup.

Neither app has a single-flight guard on refresh. The captain app runs offer polling and GPS pushes on timers, so several requests reliably hit 401 in the same instant when the access token expires; each fires its own refresh. Today that is masked by the non-atomic rotation in F-01-01 — every concurrent refresh succeeds. **Fixing F-01-01 without fixing F-01-12 first will convert a silent security hole into a visible mass-logout incident for captains.** The ordering in §7 reflects this.

**F-01-13 — The suspended flow is still armed.**
`/auth/request-otp` and `/auth/verify-otp` remain mounted (`apps/api/src/routes/auth.ts:52`, `:131`), and `verify-otp` still creates users and captain rows on the fly (`:191-219`) and issues a full 30-day session. Whatever the reason for suspending OTP, the route is live and can mint accounts today. `DEV_OTP` is `"false"` in base, prod and staging vars (`apps/api/wrangler.toml:85`, `:145`, `:173`), so `devCode` is not returned in production — that specific risk is closed. The reachability itself is the finding: a feature the business considers off should not be able to create principals. Per §1.1 this is a reachability observation, not an OTP audit.

---

## 5. Benchmark gap

| Mechanism | Uber / Careem | inDrive | Synaptic Go |
|---|---|---|---|
| Refresh reuse detection + family revocation | Yes — industry standard, RFC 6819 / OAuth BCP | Yes (assumed) | **None** (F-01-01) |
| Server-side logout invoked by the app | Yes | Yes | Endpoint exists, **never called** (F-01-02) |
| Device binding / attestation | Play Integrity + DeviceCheck, session pinned to device | Device fingerprint on session (assumed) | **None** (F-01-09) |
| Step-up auth for sensitive actions | Yes — payouts, bank details re-authenticate | Partial (assumed) | None |
| Bot defence on login | Yes, on every credential endpoint | Yes | Only on the suspended OTP route (F-01-03) |
| Per-account lockout / velocity | Yes | Yes | Per-IP fixed window only (F-01-05) |
| Access-token revocation | Short TTL + server-side session invalidation | Short TTL | 15-min TTL, **no revocation** (F-01-06) |
| Account recovery surviving SIM change | Multi-channel: email, backup codes, support KYC | Phone-first with support fallback | **No recovery at all** (F-01-04b) |
| Admin console token storage | httpOnly, `Secure`, `SameSite` cookies | n/a | `localStorage` (F-01-07) |
| Password policy | Enforced, breach-list checked | Enforced | **None** (F-01-04) |

Claims marked *(assumed)* are inference from public product behaviour, not verified. The Uber/Careem refresh-rotation-with-reuse-detection pattern and the httpOnly-cookie norm for admin surfaces are stated with confidence.

The honest summary: the **cryptographic primitives here are fine** — PBKDF2 with a proper salt, hashed refresh tokens at rest, HS256 via `jose`, secure storage on mobile. What is missing is the **session lifecycle**: detecting theft, ending a session on demand, binding it to a device, and recovering an account. That is the gap against every benchmark, and it is a design gap rather than a coding one.

Market-specific: the Egyptian reality named in the brief — frequent SIM changes, low-end Android, WhatsApp as the primary channel — collides directly with F-01-04b. Competitors survive SIM changes because they have multi-channel recovery. With OTP suspended, Synaptic Go has none.

---

## 6. Improvement plan

### P0.1 — Wire the clients to the existing logout endpoint
- **Goal** — "Log out" ends the session on the server, not just on the handset.
- **Design** — In both apps, `logout()` calls `POST /auth/logout` with the stored refresh token, awaits it with a short timeout, then clears local storage **regardless of the outcome** (never trap a user in a broken session). Fire-and-forget on network failure, with a retry on next launch if a "pending logout" flag is set.
- **Files** — `apps/rider/lib/services/app_state.dart:452-455`, `apps/captain/lib/services/captain_state.dart:1141-1173`. Ideally lift the shared implementation into `packages/flutter_shared/lib/services/` (see T27).
- **DB** — none. **API** — none; endpoint exists.
- **Effort** — S. **Risk** — very low; failure path already ends in local clear.
- **Acceptance** — after logout, the prior refresh token returns 401 `REFRESH_REVOKED`; `refresh_tokens.revoked_at` is set for every row of that user.
- **Tests** — integration: login → logout → refresh must 401. Widget test: airplane-mode logout still clears local state.

### P0.2 — Make refresh rotation atomic and add reuse detection
- **Goal** — A refresh token is redeemable exactly once, and a second attempt is treated as theft.
- **Design** — Add `family_id` to `refresh_tokens`; every token minted by rotating token *T* inherits *T*'s family. Replace the read-then-write with a single conditional update and check the row count:
  ```sql
  UPDATE refresh_tokens SET revoked_at = ?1
   WHERE id = ?2 AND token_hash = ?3 AND revoked_at IS NULL;
  -- proceed only when meta.changes === 1
  ```
  When `changes === 0` **and** a row with that `id` exists with `revoked_at` set, that is a replay: revoke the entire family, write an `auth.refresh.reuse_detected` audit row, and return 401. Mirrors the seat-claim idiom already used at `apps/api/src/routes/intercity.ts:116-124`.
- **Files** — `apps/api/src/routes/auth.ts:279-305`; new migration.
- **DB** — `migrations/0020_refresh_token_family.sql`:
  ```sql
  ALTER TABLE refresh_tokens ADD COLUMN family_id TEXT;
  ALTER TABLE refresh_tokens ADD COLUMN replaced_by TEXT;
  UPDATE refresh_tokens SET family_id = id WHERE family_id IS NULL;
  CREATE INDEX IF NOT EXISTS idx_refresh_family ON refresh_tokens(family_id);
  ```
- **API** — unchanged shape; `/auth/refresh` gains 401 `REFRESH_REUSE_DETECTED`.
- **Effort** — M. **Risk** — a client that mishandles rotation now gets logged out for real. **P0.3 must ship in the apps before this is enabled.** Roll out behind a `STRICT_REFRESH_ROTATION` flag; rollback is flipping it off.
- **Acceptance** — replaying a used refresh token 401s *and* revokes the family; two concurrent refreshes with the same token yield exactly one success.
- **Tests** — concurrency test firing 10 parallel refreshes with one token, asserting exactly one 200; replay test asserting family revocation and the audit row.

### P0.3 — Single-flight refresh, and fix the captain's rotation handling
- **Goal** — One in-flight refresh per app; rotated tokens always persisted.
- **Design** — Guard refresh with a shared `Completer`/mutex: concurrent 401s await the same future and retry with its result. Persist `refreshToken` from every refresh response and from registration.
- **Files** — `apps/captain/lib/services/captain_state.dart:249-276` and `:372-380` (add persistence, matching `apps/rider/lib/services/app_state.dart:205-209`, `:435-439`); add the mutex to both apps. Best done once in `packages/flutter_shared`.
- **DB / API** — none.
- **Effort** — S–M. **Risk** — low. **Prerequisite for P0.2.**
- **Acceptance** — 10 concurrent 401s produce exactly one `/auth/refresh` call; a rotated token is present in secure storage after every refresh; a freshly registered captain survives access-token expiry.
- **Tests** — unit test on the mutex; integration test asserting one refresh call under fan-out.

### P0.4 — Put bot defence and a password policy on the live credential routes
- **Goal** — Credential stuffing and scripted signup stop being free.
- **Design** — (a) Call `verifyTurnstile` in `/auth/login` and `/auth/register`. (b) Make it **fail closed** in production: if `TURNSTILE_SECRET_KEY` is absent and `ENVIRONMENT === "production"`, reject rather than return `ok:true`, and stop writing `verified = 1` for skipped checks. (c) Route `/register` and `/login` through `parseBody` with real Zod schemas — email format, password ≥ 10 chars, and a top-10k-breached-password denylist. (d) Confirm the production Turnstile secret is actually set.
- **Files** — `apps/api/src/routes/auth.ts:347-357`, `:386-397`; `apps/api/src/lib/turnstile.ts:17-27`; `apps/api/src/lib/schemas.ts` (add `registerSchema`, `loginSchema`).
- **DB** — none. **API** — `/register` and `/login` gain optional `turnstileToken`; new 400 `TURNSTILE_FAILED`, 400 `WEAK_PASSWORD`.
- **Effort** — M. **Risk** — existing weak-password accounts must not be locked out: enforce the policy on set, not on verify, and prompt at next login.
- **Acceptance** — login without a Turnstile token fails in production; `"password"` is rejected at registration; the synthetic `no_secret_skip` row no longer appears in production.
- **Tests** — endpoint tests for each rejection; a config test asserting fail-closed when the secret is unset.

### P0.5 — Per-account lockout and an atomic limiter
- **Goal** — Enforced limits, and a brute force that cannot be spread across IPs.
- **Design** — Add a per-account failure counter keyed on the email, independent of IP: exponential backoff from 5 consecutive failures, reset on success. Move the counter to a Durable Object (or D1 with a conditional update) so increments are atomic — `CaptainInbox`/`GeoCell` already establish the DO pattern here. Keep the KV limiter as a cheap first pass but stop treating it as the control. Make KV failure **fail closed** on credential routes specifically.
- **Files** — `apps/api/src/middleware/rateLimit.ts:27-53`; new `apps/api/src/durable-objects/RateLimiter.ts`; `apps/api/wrangler.toml` DO binding.
- **DB** — none if DO-backed. **API** — 429 gains `retryAfterSec`.
- **Effort** — M. **Risk** — a lockout is a DoS vector against a known email; use backoff rather than hard lock, and never reveal lockout state differently from a bad password.
- **Acceptance** — 20 parallel bad logins from 20 IPs against one account trip the account counter; KV outage does not open the login route.
- **Tests** — distributed brute-force simulation; KV-failure injection.

### P0.6 — Ship a password-change and account-recovery flow
- **Goal** — A user who forgets a password can get back in without a developer.
- **Design** — `POST /user/password` (authenticated, requires current password, revokes all other sessions on success). Recovery: with OTP suspended, use an emailed single-use signed token, 15-minute TTL, stored hashed, invalidated on use, rate-limited per account. **This decision belongs to the product owner — see §10 Q1**; the design above is my recommendation, not an assumption.
- **Files** — `apps/api/src/routes/user.ts`, `apps/api/src/routes/auth.ts`, `apps/api/src/lib/notifications.ts`, both apps' login screens.
- **DB** — `migrations/0021_password_reset_tokens.sql`:
  ```sql
  CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL, token_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL, consumed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id)
  );
  CREATE INDEX IF NOT EXISTS idx_prt_user ON password_reset_tokens(user_id);
  ```
- **API** — `POST /auth/forgot-password {email}` → always 200 (no enumeration); `POST /auth/reset-password {token,newPassword}`; `POST /user/password {currentPassword,newPassword}`.
- **Effort** — L. **Risk** — a reset flow is itself an account-takeover surface: constant-time responses, strict rate limits, single use, and revoke all sessions on completion.
- **Acceptance** — full forgot→reset→login cycle works; the reset token is single-use; all prior sessions die on reset.
- **Tests** — token replay, expiry, enumeration-timing, session-revocation-on-reset.

### P1.1 — Access-token revocation
- **Goal** — Ban and logout take effect immediately.
- **Design** — Add `users.token_epoch INTEGER NOT NULL DEFAULT 0`; include `epc` in the access token; `authMiddleware` rejects when `epc` ≠ the user's current epoch. Requires a user lookup per request, so cache the epoch in KV with a short TTL (staleness here is bounded and acceptable, unlike the refresh path). Bump the epoch on suspend, password change, and hard logout.
- **Files** — `apps/api/src/lib/jwt.ts`, `apps/api/src/middleware/auth.ts:49-64`, `apps/api/src/routes/admin.ts:289-309`.
- **DB** — `migrations/0022_user_token_epoch.sql`. **Effort** — M. **Risk** — a per-request read on the hot path; measure before enabling.
- **Acceptance** — a suspended captain's next request 401s within one second.

### P1.2 — Device binding on sessions
- **Goal** — Sessions carry identity; anomalous reuse is visible.
- **Design** — Client sends a stable install ID; store `device_id`, `first_ip`, `user_agent` on `refresh_tokens`. A refresh from a new device is allowed but audited and push-notified ("new sign-in on <device>"), and surfaces in a "your sessions" screen with per-session revoke.
- **DB** — `migrations/0023_refresh_token_device.sql`. **API** — `GET /user/sessions`, `DELETE /user/sessions/:id`. **Effort** — L.
- **Acceptance** — a refresh from a new device produces an audit row and a push; per-session revoke works.

### P1.3 — Move the admin console off `localStorage`
- **Goal** — An XSS on the console stops being a full platform compromise.
- **Design** — Issue the admin refresh token as an httpOnly, `Secure`, `SameSite=Strict` cookie scoped to the admin origin; keep only the short-lived access token in memory (never `localStorage`). Requires a credentialed CORS path for the admin origin specifically.
- **Files** — `apps/admin/src/lib/auth.tsx:46-48`, `apps/admin/src/lib/api.ts`, `apps/api/src/routes/auth.ts`, `apps/api/src/index.ts:40-56`. **Effort** — M. **Risk** — CSRF becomes relevant once cookies are used; pair with a double-submit token.

### P1.4 — Tighten the CORS allowlist
- **Goal** — A forgotten subdomain is not a platform credential.
- **Design** — Replace the `*.synapticstudio.tech` suffix match (`apps/api/src/index.ts:46-47`) with an explicit host list. **Effort** — S. **Risk** — a legitimate subdomain breaks; inventory first.

### P1.5 — Retire the legacy SHA-256 password path
- **Design** — Report how many `users` rows still lack a `$pbkdf2$` prefix; email those users to re-authenticate; after a deadline, null the hash and require reset (needs P0.6). Then delete the fallback at `apps/api/src/lib/utils.ts:93-98`. **Effort** — M.

### P1.6 — Bind the JWT audience and pin the algorithm
- **Design** — `setAudience()` per client (`rider|captain|admin`); verify with `{ issuer, audience, algorithms: ["HS256"] }` (`apps/api/src/lib/jwt.ts:76`); admin tokens get a 30-minute refresh TTL rather than 30 days. **Effort** — S. **Risk** — all clients must be updated together; accept both during rollout.

### P2.1 — Remove the `?token=` query path
Serve admin documents via short-lived signed R2 URLs, then delete the allowlist at `apps/api/src/middleware/auth.ts:21-27` and the query fallback at `apps/api/src/index.ts:144`. **Effort** — M.

### P2.2 — Per-session logout
Once P1.2 lands, `/auth/logout` should revoke only the presented session by default, with "sign out everywhere" as an explicit action (`apps/api/src/routes/auth.ts:338-342`). **Effort** — S.

### P2.3 — Raise PBKDF2 cost and stop trusting the stored iteration count
Move to 600,000 iterations, clamp the parsed count to a floor at `apps/api/src/lib/utils.ts:63`, upgrade on login. Measure Worker CPU first. **Effort** — S.

### P2.4 — Close the audit gaps
`logAudit` on identity-document reads, bulk user export, and audit-log reads (`apps/api/src/routes/admin.ts:894-921`). Hand to **T22**/**T25**. **Effort** — S.

### P2.5 — Housekeeping
Collapse the duplicated issuance in `/auth/login` into `issueTokens()` (F-01-22); return a refresh token from `/auth/admin/setup` (F-01-23); constant-time hash comparison (F-01-24); authenticate or key-limit `/geocode/*` (F-01-20); evaluate certificate pinning (F-01-21). **Effort** — S each.

### P2.6 — Decide the fate of the suspended OTP surface
If OTP stays off, unmount `/auth/request-otp` and `/auth/verify-otp` rather than leaving them routable (`apps/api/src/routes/auth.ts:52`, `:131`). If it returns, it needs its own review — this document did not audit it. See §10 Q2.

---

## 7. Phasing

**Order matters within P0.** P0.3 (client single-flight + captain rotation) must ship and be adopted *before* P0.2 (atomic rotation) is enabled, or fixing the security hole will log captains out en masse.

| # | Item | Phase | Effort | Owner type |
|---|---|---|---|---|
| P0.1 | Wire clients to `/auth/logout` | **P0** | S | Flutter |
| P0.3 | Single-flight refresh + captain rotation fix | **P0** (before P0.2) | S–M | Flutter |
| P0.2 | Atomic rotation + reuse detection | **P0** | M | Backend + DB |
| P0.4 | Turnstile on live routes, fail closed, password policy | **P0** | M | Backend |
| P0.5 | Per-account lockout, atomic limiter | **P0** | M | Backend |
| P0.6 | Password change + account recovery | **P0** | L | Backend + Flutter |
| P1.1 | Access-token revocation (`token_epoch`) | P1 | M | Backend + DB |
| P1.2 | Device binding + sessions screen | P1 | L | Backend + Flutter |
| P1.3 | Admin console off `localStorage` | P1 | M | Admin + Backend |
| P1.4 | Explicit CORS allowlist | P1 | S | Backend |
| P1.5 | Retire legacy SHA-256 hashes | P1 | M | Backend + ops |
| P1.6 | JWT audience + algorithm pinning | P1 | S | Backend |
| P2.1 | Remove `?token=` | P2 | M | Backend |
| P2.2 | Per-session logout | P2 | S | Backend |
| P2.3 | PBKDF2 cost | P2 | S | Backend |
| P2.4 | Audit gaps | P2 | S | Backend |
| P2.5 | Housekeeping bundle | P2 | S each | Backend |
| P2.6 | Unmount or re-review OTP | P2 | S | Backend + product |

**P0 is the gate for production traffic.** Nothing in P0 is optional: without it a stolen token is permanent and undetectable, "log out" is cosmetic, and there is no obstacle to credential stuffing.

---

## 8. Metrics

| Metric | How | Current | Target |
|---|---|---|---|
| `auth.refresh.reuse_detected` rate | audit rows from P0.2 | not measurable | tracked; every event investigated |
| Server-side logout coverage | `POST /auth/logout` calls ÷ client logout events | **0%** (confirmed: no client calls it) | > 98% |
| Concurrent-refresh collisions | count of `changes === 0` on the conditional update | unknown | ≈ 0 after P0.3 |
| Captain unexpected-logout rate | logouts not user-initiated ÷ DAU | unknown, suspected material | < 0.5% |
| Failed-login ratio | 401 `INVALID_CREDENTIALS` ÷ login attempts | unmeasured | baseline, then alert on 3× spikes |
| Turnstile skip rate | `turnstile_verifications` with `error = 'no_secret_skip'` | suspected 100% in prod | **0** in production |
| Legacy hash population | `users` rows without `$pbkdf2$` prefix | unknown | 0 after P1.5 |
| Ban-to-effect latency | suspend → first 401 | up to 15 min | < 1 s after P1.1 |
| Password-reset completion | resets completed ÷ started | n/a (no flow) | > 80% after P0.6 |
| p95 `/auth/login` latency | Workers analytics | unmeasured | < 400 ms with PBKDF2 at target cost |

The Turnstile skip-rate metric is the cheapest early win: one query over `turnstile_verifications` answers today whether bot defence is live in production.

---

## 9. Cross-cutting notes

- **T27 (cross-app parity)** — the strongest evidence in this review. Rider and captain each carry a private copy of session handling that has drifted: rider persists rotated refresh tokens and checks expiry at bootstrap; captain does neither (`apps/captain/lib/services/captain_state.dart:262-268`, `:372-380`, `:231-239` vs `apps/rider/lib/services/app_state.dart:205-209`, `:435-439`, `:156-166`). `packages/flutter_shared/lib/services/api_client.dart` exists but has no interceptor and is unused by either auth path — the shared package is a shell while the real logic is duplicated and divergent. **Recommend T27 own the extraction of a single `SessionManager` into `flutter_shared`**; the fixes in P0.1 and P0.3 should land there rather than being written twice.
- **T02 (authz/IDOR)** — `requireRole` reads the role from the JWT with no per-object check (`apps/api/src/middleware/auth.ts:67-74`). Object-level ownership is yours; note that the WS upgrade at `apps/api/src/index.ts:157-164` *does* check trip membership inline, which is a good pattern worth generalising.
- **T04 (payments)** — `POST /payments/paymob/webhook` is unauthenticated by design (`apps/api/src/routes/payments.ts:97`). I did not verify HMAC signature validation; if it is missing, that is an S1 on your axis.
- **T07 (realtime)** — the dual auth on WS upgrades (header/query, else first-message with a 10s timeout and 4401 close) is documented at `apps/api/src/index.ts:124-182`. Clients have migrated off `?token=`; the server has not dropped it (F-01-15).
- **T08 (data model)** — `refresh_tokens` has no `family_id`, `device_id` or `revoked_reason` (`migrations/0002_enhancements.sql:3-12`). P0.2/P1.2 add columns; please fold them into your schema plan. Also note `otp_codes.email` stores a phone *or* an email (`apps/api/src/routes/auth.ts:194-195`) — an overloaded column worth normalising.
- **T18 (fraud/risk)** — reuse detection (P0.2) and device binding (P1.2) are the raw signals your risk engine will want; please consume the `auth.refresh.reuse_detected` audit event.
- **T22 / T25 (observability, privacy)** — identity-document reads are unaudited (`apps/api/src/routes/admin.ts:894-921`). An admin can view every captain's national ID with no trace. That is a compliance problem more than a security one.
- **T24 (cost)** — `/geocode/*` is unauthenticated (`apps/api/src/routes/geocode.ts:8`, `:26`) and proxies a paid upstream behind only the global 120/min IP limit.
- **T11 (admin console)** — `localStorage` token storage and the client-only role check (`apps/admin/src/lib/auth.tsx:41`, `:63`) are yours to fix in the UI; the server gate itself is sound.

---

## 10. Open questions

**Q1 — Account recovery, now that OTP is suspended. (Blocking.)**
With OTP off, password is the only entry and there is no reset flow (F-01-04b). Options: **(a)** email-based reset link; **(b)** re-enable OTP for recovery only, leaving it off for login; **(c)** support-mediated manual reset; **(d)** ship without recovery.
*Recommendation:* **(a)** for launch — it is self-serve and does not depend on the suspended channel. **(d)** is not viable: it guarantees permanent lockouts from week one in a market where users change SIMs often. If the OTP suspension is temporary, **(b)** becomes the better long-term answer.

**Q2 — What happens to the mounted OTP routes?**
They are live and can still create accounts (F-01-13). Options: unmount them; leave them mounted but feature-flagged off; leave as is.
*Recommendation:* unmount now and restore deliberately if OTP returns. A suspended feature that can mint principals is not a neutral state. Whoever re-enables it should commission the OTP review this document deliberately did not perform.

**Q3 — How strictly do we bind sessions to devices?**
Full binding (a refresh from a new device is rejected) is the strongest control but will hurt on cheap Android where reinstalls are common. Soft binding (allow, audit, notify) is gentler and still yields the detection signal.
*Recommendation:* soft binding (P1.2). Revisit after 90 days of data.

**Q4 — Admin session lifetime.**
Admin refresh tokens currently live 30 days, identical to riders' (`apps/api/src/lib/jwt.ts:9`).
*Recommendation:* 8-hour refresh TTL for admins plus mandatory re-auth for destructive actions. Ship with P1.6.

**Q5 — Enforcing a password policy on existing accounts.**
Some live accounts have trivial passwords (F-01-04).
*Recommendation:* enforce on set immediately; prompt existing users at next login with a grace period; never hard-lock, which would strand users while Q1 is unresolved.

**Q6 — Is Turnstile actually configured in production?**
`TURNSTILE_SECRET_KEY` is a Worker secret and not visible in the repo; `wrangler.toml:149` shows a placeholder site key. This is the one `needs-check` item in this document that changes a severity: if the secret is unset, F-01-03 is unambiguously S1 today.
*Recommendation:* run `wrangler secret list --env prod` and query `turnstile_verifications` for `error = 'no_secret_skip'` before the next deploy. This takes five minutes and should happen before anything else in P0.
