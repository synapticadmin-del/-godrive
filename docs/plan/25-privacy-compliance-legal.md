# 25 — Privacy, Compliance & Legal Readiness

> Track: D — Engineering excellence & production readiness · Reviewer: `chat-20260801-1417-b177` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `0f432702a3755f7bd738b8b7ee15230cf05c4686` (`main`)

---

## 1. Scope

This document audits how Synaptic Go collects, stores, shares, retains and deletes the personal data of Egyptian citizens, and what must exist before the platform can lawfully carry production traffic.

**In scope**

- The complete inventory of personal data held in D1, KV, R2, Durable Objects and Cloudflare Queues.
- Retention and deletion: what is purged, what is kept forever, and what the code claims versus what it does.
- Cross-border transfers to Meta, Resend, Google FCM, Nominatim/OSM, OSRM, Paymob and Cloudflare.
- Identity-document handling (national ID scans, driving licences) end to end: upload, storage, staff access, deletion.
- Consent capture, transparency surfaces and data-subject rights in both Flutter apps.
- Staff access to PII in the admin console, and whether that access is auditable.
- PII leakage into logs, error responses, URLs and audit rows.
- Egypt's Personal Data Protection Law 151/2020 mapped obligation-by-obligation to what the product must build.
- Adjacent legal regimes (labour, tax, transport licensing, insurance) — flagged, scoped, and handed to counsel.

**Explicitly out of scope** — owned by sibling tracks:

| Area | Owner |
|---|---|
| Authentication mechanics, session lifetime, token rotation | T01 |
| RBAC design, IDOR classes, object-level authorization | T02 |
| Wallet/ledger correctness and money integrity | T03 |
| PSP integration correctness and payout mechanics | T04 |
| Logging/metrics infrastructure and incident tooling | T22 |
| CI/CD, secret scanning, release gating | T23 |
| Store listing metadata and data-safety form mechanics | T26 |
| Cross-app duplication and vocabulary drift | T27 |

Where this document touches those axes it does so **only** through the privacy lens — for example, the single `admin` role is T02's design problem, but "no operator can be tied to the national ID they opened" is a privacy finding and it is mine. Anything I found outside my axis is in §9.

**A note on the legal content.** I am not counsel. Statutory obligations below are marked `confident` where the requirement is well-established in the text of Law 151/2020, and `needs-legal-review` where the answer depends on the executive regulations, on the Personal Data Protection Center's current licensing practice, or on facts about the company I cannot read from a repository. Every such item is listed again in §10. **The status and final text of the executive regulations must be confirmed by Egyptian counsel before any of the deadlines in this document are treated as authoritative** — `needs-check`.

---

## 2. What I actually read

Everything below was fetched at commit `0f43270` and read from disk with real line numbers. Citations elsewhere in this document point at these files.

**Backend — libraries**

| File | Note |
|---|---|
| `apps/api/src/lib/audit.ts` | 37 lines, read fully. The entire audit facility: one `INSERT` into `audit_log`, swallows its own errors. |
| `apps/api/src/lib/cleanup.ts` | 75 lines, read fully. The whole of the platform's automated retention. Two tables. |
| `apps/api/src/lib/notifications.ts` | 408 lines, read for provider calls and payload construction. WhatsApp/Meta, Resend, FCM. |
| `apps/api/src/lib/geocode.ts` | 130 lines. Nominatim forward + reverse, KV caching, coordinate rounding. |
| `apps/api/src/lib/routing.ts` | 173 lines. OSRM `/route` and `/table` calls. |
| `apps/api/src/lib/paymob.ts` | 235 lines. Auth token, order, payment key with full billing struct, iframe URL. |
| `apps/api/src/lib/turnstile.ts` | 57 lines. `remoteip` forwarding and the verification row write. |
| `apps/api/src/lib/utils.ts` | 241 lines, read for `id()` entropy and hashing helpers. |
| `apps/api/src/lib/jwt.ts` | 96 lines, skimmed — claim contents only (id, email, name, role). |
| `apps/api/src/lib/nearby.ts` | 105 lines, read for the cell-key logging line. |
| `apps/api/src/lib/types.ts`, `schemas.ts`, `pricing.ts` | Skimmed for PII-bearing field definitions. |

**Backend — routes and middleware**

| File | Note |
|---|---|
| `apps/api/src/index.ts` | 372 lines. Global error handler, WebSocket auth, cron wiring. |
| `apps/api/src/middleware/auth.ts` | 75 lines, read fully. The `?token=` carve-out and `requireRole`. |
| `apps/api/src/middleware/rateLimit.ts` | 90 lines. KV key construction from IP. |
| `apps/api/src/routes/admin.ts` | 937 lines. Every PII-returning endpoint and every `logAudit` call site. |
| `apps/api/src/routes/captain.ts` | 700 lines. Document upload, R2 key format, location ping, path sampling, document delete. |
| `apps/api/src/routes/auth.ts` | 483 lines. OTP issue/verify, `DEV_OTP`, the KV name key, login audit rows. |
| `apps/api/src/routes/user.ts` | 328 lines. Avatar R2 lifecycle, saved places. Searched exhaustively for account deletion. |
| `apps/api/src/routes/wallet.ts` | 142 lines. Payout request — the `account_info` write path. |
| `apps/api/src/routes/safety.ts` | 291 lines. SOS, share-token creation, the public `/track/:token` view. |
| `apps/api/src/routes/trips.ts` | 1371 lines, read selectively: path-point reads, chat, FCM error logging. |
| `apps/api/src/routes/payments.ts` | 313 lines. Webhook audit rows and the error echo at line 91. |
| `apps/api/src/routes/devices.ts`, `geocode.ts`, `search.ts`, `promo.ts`, `intercity.ts`, `companies.ts` | Read for PII in parameters and responses. |

**Schema** — all 19 migrations downloaded; `0001`, `0002`, `0003`, `0011`, `0012`, `0014`, `0015`, `0016` read line by line for DDL, the rest scanned for `ADD COLUMN` and index changes.

**Configuration** — `apps/api/wrangler.toml` (180 lines) read fully: bindings, queue + DLQ, crons, `[vars]`, `[env.prod]`, `[observability]`.

**Admin console** — `apps/admin/src/pages/UsersPage.tsx` (74 lines) and `CaptainVerificationPage.tsx` (1050 lines), read for rendered PII and masking.

**Mobile** — `apps/rider/lib/screens/profile/settings_screen.dart` (117), `help_screen.dart` (75), rider and captain `login_screen.dart`, captain `profile/settings_screen.dart`, both `AndroidManifest.xml`, both `ios/Runner/Info.plist`, `packages/flutter_shared/lib/l10n/app_strings.dart`.

**Repository root** — `README.md` (91 lines) and `LICENSE` (1 line).

**Repo-wide searches run** (negative evidence matters as much as positive):

- `github__search_code` for `privacy` across the repository → exactly **3** hits: a CSS/localStorage comment in `apps/admin/src/design/ThemeContext.tsx`, the string getter `privacyPolicy` in `packages/flutter_shared/lib/l10n/app_strings.dart`, and the dead settings row in `apps/captain/lib/screens/profile/settings_screen.dart`. **No privacy policy document exists in this repository.**
- `grep -rn "DELETE FROM" apps/api/src/` → 7 statements, enumerated in §3.
- `grep -rn "FILES\." apps/api/src/` → 7 call sites, enumerated in §3.
- `grep -rn "logAudit" apps/api/src/` → every call site classified as read or write.
- Case-insensitive grep for `terms`, `consent`, `agree`, `سياسة`, `الخصوصية`, `الشروط`, `موافقة` across both Flutter apps and the shared package.

**Honest limitations.** Durable Object source files were read only where they log (`OfferScheduler.ts`); I did not audit DO storage lifetimes in depth — flagged `needs-check` in §4 (F-25-27). I did not read the full 1371 lines of `trips.ts`, only the sections reachable from location, chat and notification paths. I did not verify Cloudflare's platform behaviour (encryption at rest, D1 replica geography, Queue DLQ retention) against Cloudflare documentation — those are marked `likely` or `needs-check` throughout and never asserted as configured facts. No runtime testing was possible; this is a static review.

---

## 3. How it works today

### 3.1 The shape of the data

Synaptic Go holds, for every Egyptian citizen who uses it, some combination of: legal name, phone number, email, password hash, home and work addresses, the origin and destination of every journey ever taken, a GPS breadcrumb trail sampled through each trip, the content of every message exchanged with a driver, wallet balance and full financial ledger, payment tokens, device push identifiers, and IP addresses with user agents for every audited action.

For captains it additionally holds the four-part Arabic legal name, date of birth, **national ID number in plaintext**, driving licence expiry, and scanned images of the national ID card and licence.

There is no data classification in the schema. Nothing marks a column as sensitive, and nothing behaves differently because a column is sensitive.

### 3.2 Identity documents: upload → storage → review

A captain uploads through `POST /captain/upload` (`apps/api/src/routes/captain.ts:625`). The handler is genuinely careful about *file safety*: 10 MB cap (`captain.ts:631`), and content type decided by byte-sniffing the header rather than trusting the declared MIME (`captain.ts:637-659`), with a narrow ISO-BMFF fallback for HEIC. The stored content type is derived from the verified extension and never echoed from the upload (`captain.ts:662`).

The object key is:

```
docs/${user.id}/${Date.now()}_${id("f")}.${ext}          — captain.ts:664
```

`id()` is `crypto.randomUUID()` with dashes stripped (`apps/api/src/lib/utils.ts:9-12`), so the key carries 122 bits of entropy and is not guessable. It does, however, embed the captain's user ID and the upload timestamp.

Bytes go to the `FILES` R2 bucket (`captain.ts:665`; binding at `apps/api/wrangler.toml:18-21`). The key is returned to the client, which then posts it to `POST /captain/documents`, where the server checks the key is inside the caller's own folder before inserting the row — a real IDOR guard.

Two read paths exist:

- `GET /captain/file/*` (`captain.ts:673`) — the captain's own documents. Enforces the folder prefix, **except** that `user.role === "admin"` bypasses the check entirely (`captain.ts:680`), so an admin may fetch any key in the bucket through this route.
- `GET /admin/documents/:id/file` (`apps/api/src/routes/admin.ts:894`) — looks the R2 key up from the document ID and streams the object. The response headers are conscientious: `Cache-Control: private, no-store` (`admin.ts:912`) and `X-Content-Type-Options: nosniff` (`admin.ts:919`), with a long comment explaining exactly why a shared cache must never hold an identity scan.

The bucket is not public, and an object key alone is not sufficient to fetch a document. **That part is sound.** Two things undermine it:

1. `apps/api/src/middleware/auth.ts:25` explicitly permits `?token=<jwt>` authentication for `/admin/documents/:id/file`, because the console renders scans via `<img src>`. The file's own doc comment (`auth.ts:16-19`) states the objection to query tokens correctly and then makes the exception anyway.
2. Neither read path writes an audit row. See §3.5.

### 3.3 Location: the movement trace

A captain's app pings `POST /captain/location`. Each ping fans out three ways (`captain.ts:210-265`):

- a heartbeat to the `GeoCell` Durable Object carrying `userId`, `lat`, `lng` **and `name`** (`captain.ts:213-221`);
- an `UPDATE` of `trips.captain_lat/captain_lng` when the ping carries an active trip (`captain.ts:231-235`);
- a sampled insert into `trip_path_points`, throttled to at most one point per 30 seconds (`captain.ts:237-252`).

`trip_path_points` is created at `migrations/0002_enhancements.sql:14-22` with `lat`, `lng`, `heading`, `speed`, `recorded_at`, indexed by trip and by `(trip_id, recorded_at)` (`0002:23-24`). At one point per 30 s, an eight-hour shift produces roughly 960 rows per captain per day, each a precise, timestamped position of an identified person.

Nothing deletes them. The `ON DELETE CASCADE` on `trip_id` (`0002:16`) is the only deletion mechanism, and trips are never deleted (§3.4).

### 3.4 Retention: what actually gets deleted

The cron handler calls `runExpiredDataCleanup` (`apps/api/src/lib/cleanup.ts:29`). It removes exactly two things:

| Statement | Target | Window |
|---|---|---|
| `cleanup.ts:36` | `otp_codes` | expired more than 1 day ago |
| `cleanup.ts:49-51` | `refresh_tokens` | revoked or expired more than 7 days ago |

That is the entirety of the platform's scheduled retention. Every other `DELETE FROM` in the codebase is a user- or admin-triggered action, not a retention policy:

```
apps/api/src/routes/user.ts:323      saved_places        (user deletes one saved place)
apps/api/src/routes/captain.ts:567   driver_documents    (supersede on re-upload, non-approved only)
apps/api/src/routes/captain.ts:605   driver_documents    (captain clears a pending upload)
apps/api/src/routes/intercity.ts:157 intercity_bookings  (booking cancellation)
apps/api/src/routes/devices.ts:38    device_tokens       (device unregister)
```

There is no `DELETE FROM users`, no `DELETE FROM trips`, no `DELETE FROM trip_path_points`, no `DELETE FROM audit_log`, no `DELETE FROM trip_chat_messages`, and no `DELETE FROM notification_log` anywhere in the repository.

The R2 side is worse, and it is worth being precise. `FILES.delete` is called in exactly two places, both for **avatars**:

```
apps/api/src/routes/user.ts:186   delete stale avatar on replace
apps/api/src/routes/user.ts:235   delete avatar on DELETE /user/avatar
```

No code path anywhere deletes a document object. Not on rejection, not on re-upload, not on suspension, not on captain deactivation. And the re-upload path at `captain.ts:567` deletes the **database row** that holds `r2_key` while leaving the object in the bucket — which means the platform not only retains superseded national-ID scans indefinitely, it also **loses the only pointer it had to them**. They become unreferenced blobs that cannot be found for deletion without enumerating the bucket.

`cleanup.ts:11-13` carries a stale comment asserting that `turnstile_verifications` "does not exist in the current migrations (0001–0010)". The table was added at `migrations/0003_global_transport.sql:201`, which is inside that range. It stores an IP address per row (`0003:201-209`) and is never purged.

### 3.5 Audit: a write log, not an access log

`logAudit` (`apps/api/src/lib/audit.ts:3-37`) inserts `actor_id`, `action`, `entity_type`, `entity_id`, a JSON `payload`, `ip` and `user_agent`. It catches and swallows its own failures so audit never breaks a request (`audit.ts:33-36`) — reasonable for availability, but it means audit loss is silent.

Classifying every call site: audit rows are written for `auth.login`, `auth.register.email`, `auth.login.email`, `captain.approve`, `captain.suspend`, `pricing.update`, `system_config.update`, `promo.deactivate`, `document_type.*`, `document.approved`, `document.rejected`, `payment.webhook.*`, and `system.cleanup`.

Every one of those is a **state change**. Not a single read is audited. In particular these endpoints return personal data and write nothing:

| Endpoint | Returns | `path:line` |
|---|---|---|
| `GET /admin/documents/:id/file` | the national ID / licence **image** | `admin.ts:894-922` |
| `GET /admin/documents` | `d.*` incl. `national_id_number`, `holder_full_name`, plus captain email + phone | `admin.ts:620-679` |
| `GET /admin/captains` | `c.*` incl. `national_id_number`, `birth_date`, four name parts | `admin.ts:229-258` |
| `GET /admin/users` | id, email, name, phone for up to 200 users | `admin.ts:326-331` |
| `GET /admin/search` | name, email, phone across riders and captains | `admin.ts:551-608` |
| `GET /admin/online-captains` | name, email, phone **and live `last_lat`/`last_lng`** | `admin.ts:925-936` |
| `GET /admin/live-trips` | rider and captain IDs with pickup/dropoff coordinates | `admin.ts:52-62` |

The authorization model is a single binary role. `requireRole("admin")` (`apps/api/src/middleware/auth.ts:67-74`) gates the whole surface, and the role check is a flat `includes()`. There is no support tier, no reviewer tier, no read-only tier, and no field-level filtering — the person who edits a pricing rule and the person who reviews a licence photo hold identical rights over every citizen's record.

### 3.6 Consent and transparency

There is a terms checkbox on both sign-up forms — `apps/rider/lib/screens/login_screen.dart:542` (state field `_acceptedTerms`, line 90; submit gate at line 143) and `apps/captain/lib/screens/login_screen.dart:374` (field `_acceptTerms`, line 70; gate at line 98). Both block the button until ticked.

Three things are true about that checkbox:

1. **There is nothing to read.** No URL, no screen, no bundled document. Repo-wide search for `privacy` returns three hits and none of them is a policy (§2).
2. **The acceptance is never recorded.** `POST /auth/register` accepts `email`, `name`, `phone`, `password`, `role` and nothing else (`apps/api/src/routes/auth.ts:347-383`). There is no `terms_accepted` column on `users` (`migrations/0001_init.sql:3-13`), no consent version, no timestamp. The gate is client-side decoration; the server has no idea whether anyone agreed to anything.
3. **The one visible "Privacy policy" affordance is dead.** `apps/captain/lib/screens/profile/settings_screen.dart:519` renders it with `_InfoRow` — a non-tappable `ListTile` (widget defined at lines 839-879) with `value: ''`. It displays the label and does nothing. The rider settings screen has no such row at all: `apps/rider/lib/screens/profile/settings_screen.dart` offers Language (line 33), Dark mode (line 58), About (line 84) and Logout (line 101).

The complete list of privacy-relevant controls a user has today is: change language, change theme, replace or remove their avatar, and log out. There is no data export, no account deletion, no notification opt-out, and no location control.

### 3.7 What leaves the country

| Provider | Purpose | Call site | Personal data sent | In URL? |
|---|---|---|---|---|
| OSRM (`router.project-osrm.org`) | route geometry, distance, ETA | `apps/api/src/lib/routing.ts:28` | exact pickup + dropoff coordinates | **yes — URL path** |
| OSRM | batch ETA | `routing.ts:121` | N captains' live coordinates + rider pickup | **yes — URL path** |
| Nominatim / OSM | reverse geocode | `apps/api/src/lib/geocode.ts:39-40` | `lat`/`lon` at 4 dp (~11 m) | **yes — query string** |
| Nominatim / OSM | forward search | `geocode.ts:100-102` | raw typed search text | **yes — query string** |
| Meta Graph API | WhatsApp OTP | `apps/api/src/lib/notifications.ts:114` | phone number (E.164) | no — POST body |
| Resend | email OTP | `notifications.ts:175` | email address + the OTP code in the body | no — POST body |
| Google FCM | push delivery | `notifications.ts:324` | FCM registration token, title, body, `data` map | no — POST body |
| Cloudflare Turnstile | bot check | `apps/api/src/lib/turnstile.ts:30` | user IP as `remoteip` | no — POST form body |
| Paymob | payment key | `apps/api/src/lib/paymob.ts:63` | first/last name, email, phone, street-level address | no — POST body |

`OSRM_URL` defaults to the public demo server in both the root `[vars]` block (`apps/api/wrangler.toml:88`) and the production environment block — so this is the shipping configuration, not a dev convenience. `router.project-osrm.org` is a community demo instance operated in Germany; it carries no SLA, no confidentiality undertaking and no data-processing agreement of any kind. Every routed trip hands it an identified citizen's origin-destination pair inside a URL path, where it lands in that operator's access logs.

Geocode results are cached in KV for 30 days (reverse, `geocode.ts:82`) and 7 days (search, `geocode.ts:128`), which reduces repeat exposure but does nothing for the first call.

`wrangler.toml` contains no `jurisdiction` key and no Data Localization Suite configuration. D1, KV, R2, Durable Objects and Queues all run with Cloudflare's default global behaviour — `confirmed` as an absence in the config; the resulting physical data geography is `needs-check`.

The `NOTIFICATIONS` queue has `max_retries = 3` and a dead-letter queue (`wrangler.toml:51-55`). Queue messages carry phone numbers, email addresses and FCM tokens, so the DLQ is a second, undocumented PII store with no retention policy in the repo.

### 3.8 Observability as a data store

`[observability] enabled = true` (`apps/api/wrangler.toml:93-94`) means Workers Logs retains console output. That converts every `console.error` into a retained record. The global handler at `apps/api/src/index.ts:233-236` does both things at once:

```ts
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: err.message || "Internal error", code: "INTERNAL" }, 500);
});
```

— it logs the full error object *and* returns `err.message` verbatim to the caller. `apps/api/src/routes/payments.ts:91` does the same explicitly for Paymob failures, and `paymob.ts:31/49/78` throw with `data.detail` taken straight from the PSP response.

### 3.9 Data inventory

Every category of personal data the platform holds, from the DDL. "Retention today" is what the code does, not what anyone intends.

| # | Data category | Table · columns | Store | Created at | Who can read it | Retention today | Confidence |
|---|---|---|---|---|---|---|---|
| 1 | Account identity | `users.name`, `.email`, `.phone` | D1 | `migrations/0001_init.sql:3-13` | self; any admin (bulk, `admin.ts:326`) | **forever** | confirmed |
| 2 | Credential | `users.password_hash` | D1 | `0001_init.sql:6` | nobody (hash) | forever | confirmed |
| 3 | Avatar image | `users.avatar_url` → R2 object | D1 + R2 | `migrations/0013_user_avatar.sql:17` | self; admins | deleted on replace/remove (`user.ts:186,235`) | confirmed |
| 4 | **National ID number** | `captains.national_id_number` | D1 **plaintext** | `migrations/0015_captain_onboarding_fields.sql:15` | any admin via `c.*` (`admin.ts:229-258`) | **forever** | confirmed |
| 5 | **Legal name (4-part) + DOB** | `captains.first_name`, `.father_name`, `.grandfather_name`, `.family_name`, `.birth_date` | D1 plaintext | `0015:10-14` | any admin | **forever** | confirmed |
| 6 | **National ID number (2nd copy)** | `driver_documents.national_id_number`, `.holder_full_name` | D1 plaintext | `migrations/0012_document_identity_fields.sql:10-11` | any admin (bulk, `admin.ts:620-679`) | forever if approved | confirmed |
| 7 | **Identity document images** | `driver_documents.r2_key` → R2 `docs/<userId>/…` | R2 | `migrations/0002_enhancements.sql:26-36`; key at `captain.ts:664` | any admin (`admin.ts:894`) | **never deleted, ever** | confirmed |
| 8 | Licence expiry | `captains.license_expiry`, `driver_documents.expires_at` | D1 | `0015:16`, `0012:12` | any admin | forever | confirmed |
| 9 | **Movement trace** | `trip_path_points.lat`, `.lng`, `.heading`, `.speed`, `.recorded_at` | D1 | `0002_enhancements.sql:14-22`; written `captain.ts:246-251` | admins; anyone with a share token (last point, `safety.ts:110`) | **forever** | confirmed |
| 10 | Trip origin/destination | `trips.pickup_lat/lng/address`, `.dropoff_lat/lng/address` | D1 | `0001_init.sql:58-87` | parties; admins | forever | confirmed |
| 11 | Live captain position | `captains.last_lat`, `.last_lng`, `.last_seen_at`; `trips.captain_lat/lng` | D1 | `0001_init.sql:27-44`, `:78-79` | admins (`admin.ts:925`) | overwritten, never purged | confirmed |
| 12 | Home/work addresses | `saved_places.label`, `.lat`, `.lng`, `.address` | D1 | `0002_enhancements.sql:72-81` | self | until user deletes one (`user.ts:323`) | confirmed |
| 13 | Emergency location | `sos_alerts.lat`, `.lng`, `.reason`, `.shared_with` | D1 | `migrations/0003_global_transport.sql:161-175` | admins | **forever** | confirmed |
| 14 | Message content | `trip_chat_messages.body`, `.sender_id`, `.sender_role` | D1 | `0003:187-196` | trip parties; admins | **forever** | confirmed |
| 15 | Financial ledger | `wallet_transactions.amount`, `.note`, `.payment_ref` | D1 | `0003:27-42` | self; admins | forever | confirmed |
| 16 | **Bank / mobile-money account** | `wallet_transactions.note` = `"<method>:<account_info>"` | D1 | written `wallet.ts:129` | self; admins | forever | confirmed |
| 17 | **Bank account (2nd copy)** | `audit_log.payload` for `wallet.payout.request` | D1 | written `wallet.ts:139` | admins (`GET /admin/audit-log`) | **forever** | confirmed |
| 18 | Payment token | `payment_methods.token`, `.last4`, `.provider` | D1 | `0002_enhancements.sql:95-105` | self; admins | forever | confirmed |
| 19 | Payment intent | `payment_intentions.*` | D1 | `migrations/0011_payment_intentions.sql:8-19` | admins | forever | confirmed |
| 20 | Device identifier | `device_tokens.token`, `.platform`, `.app_role` | D1 | `0003:12-22` | server | until unregister (`devices.ts:38`) | confirmed |
| 21 | Device identifier (copy) | `notification_log.payload` contains the FCM token | D1 | `0003:214-227`; written `notifications.ts:351,359,367` | admins | **forever** | confirmed |
| 22 | Network metadata | `audit_log.ip`, `.user_agent`, `.actor_id` | D1 | `0002_enhancements.sql:39-49` | admins | **forever** | confirmed |
| 23 | Network metadata | `turnstile_verifications.ip`, `.token` | D1 | `0003:201-209` | server | **forever** (stale comment `cleanup.ts:11-13`) | confirmed |
| 24 | Auth secret | `otp_codes.code` (plaintext 6 digits), `.email` (holds phone *or* email) | D1 | `0001_init.sql:15-23`; written `auth.ts:91-95` | server | expired + 1 day (`cleanup.ts:36`) | confirmed |
| 25 | Contact in a cache key | KV key `otp-name:<phone|email>` | KV `SESSIONS` | `auth.ts:98` | server | 600 s TTL | confirmed |
| 26 | IP in a cache key | KV key `rl:<prefix>:<ip>:<bucket>` | KV `SESSIONS` | `rateLimit.ts:20,25` | server | bucket TTL | confirmed |
| 27 | Behavioural | `ratings.score`, `.comment`; `trip_events.payload`; `referrals.*` | D1 | `0001:94-114`, `0002:107-115` | admins | forever | confirmed |
| 28 | Share grant | `trip_share_tokens.token`, `.expires_at`, `.revoked_at` | D1 | `0003:177-184` | **anyone holding the token** | forever (expired rows never purged) | confirmed |
| 29 | Name inside a DO | `GeoCell` heartbeat body: `userId`, `lat`, `lng`, `name` | DO storage | `captain.ts:213-221` | server | unknown | needs-check |
| 30 | Queue payloads | `NOTIFICATIONS` queue + DLQ: phone, email, FCM token | CF Queues | `wrangler.toml:46-55` | server | undocumented | needs-check |
| 31 | Console output | error objects, cell keys, user IDs | Workers Logs | `wrangler.toml:93-94` | Cloudflare account holders | platform default | likely |
| 32 | B2B contact | `companies.legal_name`, `.tax_id`, `.contact_email`, `.contact_phone` | D1 | `0003:113-124` | admins | forever | confirmed |

**Encryption.** No application-layer encryption, tokenisation, hashing or field-level key management exists anywhere for any of the above except `users.password_hash` and `refresh_tokens.token_hash`. `wrangler.toml` configures no customer-managed keys. D1, KV and R2 are encrypted at rest by the platform with Cloudflare-held keys — `likely`, and in any case that is not a control the product owns. Transit is HTTPS throughout. **The national ID number of every captain on the platform is stored as readable text in a database column** and is returned in bulk by an admin endpoint.

**Cascade behaviour.** Fifteen tables declare `ON DELETE CASCADE` from `users` (e.g. `captains` `0001:28`, `driver_documents` `0002:28`, `saved_places` `0002:74`, `wallet_transactions` `0003:29`, `sos_alerts` `0003:163`, `trip_chat_messages` `0003:190`, `notification_log` `0003:216`). But `trips.rider_id` and `trips.captain_id` declare no action at all (`0001_init.sql:60-61`), and `ratings` (`0001:108-109`), `audit_log.actor_id` (`0002:41`), `driver_documents.reviewed_by` (`0002:33`) and `referrals` (`0002:109-110`) are likewise bare references. If a user row were ever deleted, their trips — and everything cascading from trips, including the entire movement trace — would be **orphaned rather than removed**. This is currently academic, because nothing deletes users.

---

## 4. Findings

Severity per `board/TEMPLATE.md`. "S1 — blocker" includes *data can be leaked*, which is the operative clause for most of this track.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-25-01 | S1 | No privacy policy exists in the product or the repository | repo-wide search: 3 hits, none a policy; `apps/captain/.../settings_screen.dart:519` is a dead row | No transparency notice → PDPL processing has no lawful footing | confirmed |
| F-25-02 | S1 | Consent is never recorded: the terms checkbox is client-side only | `apps/rider/lib/screens/login_screen.dart:542`, `apps/captain/lib/screens/login_screen.dart:374`, vs `auth.ts:347-383` (no consent field) | Cannot prove consent for any user; no version, no timestamp | confirmed |
| F-25-03 | S1 | No data-subject rights mechanism at all — no access, export, correction or erasure | `grep "DELETE FROM users"` → none; no export endpoint in `user.ts` | Every PDPL Art. 2 right is unimplementable; also breaches app-store deletion rules | confirmed |
| F-25-04 | S1 | Identity-document images are never deleted from R2 | `FILES.delete` exists only at `user.ts:186,235` (avatars) | National ID scans accumulate permanently with no expiry | confirmed |
| F-25-05 | S1 | Superseded documents are orphaned: the DB row is deleted, the R2 object is not | `captain.ts:567` deletes the row holding `r2_key`; no R2 delete | Scans become unreferenced blobs — undeletable without bucket enumeration | confirmed |
| F-25-06 | S1 | Staff access to national IDs is entirely unaudited | `admin.ts:894-922`, `:620-679`, `:229-258` — no `logAudit` in any | Cannot answer "who viewed this citizen's ID"; insider misuse is invisible | confirmed |
| F-25-07 | S1 | `trip_path_points` retains a 30-second-resolution movement trace forever | `0002_enhancements.sql:14-22`; written `captain.ts:246`; `cleanup.ts` untouched | The most sensitive dataset in the system has no retention justification or limit | confirmed |
| F-25-08 | S1 | Precise trip coordinates are sent to a public demo server with no contract | `routing.ts:28`, `:121`; `wrangler.toml:88` (prod default) | Unlawful cross-border transfer of location data; third party logs O/D pairs | confirmed |
| F-25-09 | S1 | National ID numbers stored and returned in plaintext, in bulk | `0015:15`, `0012:11`; `SELECT c.*` at `admin.ts:229-258`, `d.*` at `admin.ts:620-679` | Mass exposure of a national identifier from a single admin credential | confirmed |
| F-25-10 | S1 | No breach-detection or breach-notification capability exists | no alerting, no access log, no runbook in repo | PDPL 72-hour clock cannot be met; breach could go unnoticed indefinitely | confirmed |
| F-25-11 | S2 | `audit_log` grows forever, carrying IP + user-agent on every row | `0002:39-49`; `cleanup.ts:29-57` never touches it | Permanent IP-to-action log with no retention basis | confirmed |
| F-25-12 | S2 | Bank / mobile-money account numbers written to two permanent stores | `wallet.ts:129` (ledger `note`), `wallet.ts:139` (audit `payload`) | Financial account identifiers in an unbounded, admin-readable log | confirmed |
| F-25-13 | S2 | Public `/track/:token` returns pickup and dropoff addresses despite claiming not to | comment `safety.ts:88-89` says "no PII"; body returns them at `safety.ts:119-120` | Anyone with a forwarded link reads both addresses; the code's own contract is wrong | confirmed |
| F-25-14 | S2 | Expired share tokens are never purged | `0003:177-184`; no cleanup | Unbounded grant table; every past share retained | confirmed |
| F-25-15 | S2 | Single `admin` role — no least privilege over identity documents | `middleware/auth.ts:67-74`; `admin.ts:11` | Any operator, including a pricing clerk, can read every national ID | confirmed |
| F-25-16 | S2 | JWTs accepted in query strings for WS and document images | `middleware/auth.ts:23-25`; `index.ts:144`, `:199` | Tokens (carrying email + name) land in access logs, history, Referer | confirmed |
| F-25-17 | S2 | Error messages returned verbatim to callers | `index.ts:235`; `payments.ts:91` with PSP `data.detail` from `paymob.ts:31,49,78` | DB constraint text or PSP echo can disclose stored values | confirmed |
| F-25-18 | S2 | User coordinates and typed search text sent to Nominatim in the query string | `geocode.ts:39-40`, `:100-102` | Location data recorded in a third party's access logs, no DPA | confirmed |
| F-25-19 | S2 | Phone numbers to Meta and emails to Resend with no visible transfer mechanism | `notifications.ts:114`, `:175` | Cross-border transfer of contact data without a PDPL permit | confirmed |
| F-25-20 | S2 | `notification_log` stores FCM device tokens indefinitely | `0003:214-227`; `notifications.ts:351,359,367` | Permanent device-linkage corpus | confirmed |
| F-25-21 | S2 | Raw phone/email embedded in a KV key | `auth.ts:98` (`otp-name:<identKey>`) | Contact identifiers in a key namespace visible to key listing | confirmed |
| F-25-22 | S2 | `turnstile_verifications` retains IPs forever behind a stale exemption comment | `0003:201-209`; `cleanup.ts:11-13` claims the table doesn't exist | Unbounded IP store nobody believes exists | confirmed |
| F-25-23 | S2 | No data-residency configuration; no DPO; no processing register | `wrangler.toml` has no `jurisdiction` key; nothing in repo | Core PDPL governance obligations unaddressed | confirmed (absence) |
| F-25-24 | S2 | Rider app declares always-on location on iOS with no implemented use | `apps/rider/ios/Runner/Info.plist:51`, `:57-59` vs Android manifest line 8 comment | Over-collection; App Review rejection risk | confirmed |
| F-25-25 | S3 | iOS permission purpose strings are Arabic-only | both `ios/Runner/Info.plist:49-55` | Non-Arabic users get prompts they cannot read | confirmed |
| F-25-26 | S3 | Admin bypass in the captain file route lets an admin fetch any R2 key | `captain.ts:680` | Second, unaudited path to identity documents | confirmed |
| F-25-27 | S3 | `GeoCell` DO receives and holds the captain's name alongside coordinates | `captain.ts:213-221` | Name+location in a store with unreviewed lifetime | needs-check |
| F-25-28 | S3 | `LICENSE` contains the literal string `test-license` | `LICENSE:1` | No enforceable licence terms; blocks OSS compliance and store review | confirmed |
| F-25-29 | S3 | `GET /admin/audit-log` is itself unaudited | `admin.ts:219-226` | An operator can inspect what traces their actions left | likely |
| F-25-30 | S3 | Notification queue DLQ is an undocumented PII store | `wrangler.toml:51-55` | PII persists outside the modelled data estate | needs-check |
| F-25-31 | S4 | `cleanup.ts` docstring describes a policy the code does not implement | `cleanup.ts:3-14` | Misleads the next engineer into thinking retention exists | confirmed |
| F-25-32 | S4 | R2 keys embed user ID and upload timestamp | `captain.ts:664` | Metadata leak if a listing is ever exposed | confirmed |

### The S1 set, in prose

**F-25-01 · There is no privacy policy.** I searched the entire repository for the word `privacy` and got three results: a comment about `localStorage` in `apps/admin/src/design/ThemeContext.tsx`, a string getter `privacyPolicy` in `packages/flutter_shared/lib/l10n/app_strings.dart`, and one usage of that string at `apps/captain/lib/screens/profile/settings_screen.dart:519`. That usage renders an `_InfoRow`, which is defined at lines 839-879 as a `ListTile` with no `onTap` and is passed `value: ''`. It is a label with nothing behind it. The rider app does not even have the label. This is not a gap in a policy — there is no policy. Every downstream obligation in this document (lawful basis, transparency, transfer disclosure, retention notice) depends on a document that does not exist, and writing it is the single highest-leverage action in this track.

**F-25-02 · Consent is theatre.** Both sign-up screens gate submission on a checkbox, and both then throw the answer away. `POST /auth/register` (`apps/api/src/routes/auth.ts:347-383`) accepts five fields and none of them is consent. There is no column on `users` to hold it (`migrations/0001_init.sql:3-13`). If a regulator or a claimant asks the company to produce evidence that a named user agreed to a named version of a policy on a named date, the company cannot — not because the record is hard to find, but because it was never written. Consent must be captured server-side, versioned, and timestamped, and the policy version must be immutable once shown.

**F-25-03 · No data-subject rights.** I searched every route file for a deletion or export path. There is no `DELETE FROM users`, no deactivation endpoint, no export endpoint, no correction endpoint beyond the profile fields a user can already edit. Two independent regimes require this: PDPL Art. 2 grants access, correction, erasure and portability; and both the Apple App Store and Google Play require any app that lets a user create an account to offer in-app account deletion. `apps/rider/.../settings_screen.dart` and the captain equivalent offer Language, Theme, About and Logout. This is a launch blocker on the store side alone, before the legal argument starts.

**F-25-04 and F-25-05 · Identity documents are immortal, and some are also lost.** `FILES.delete` appears twice in the codebase, both in `apps/api/src/routes/user.ts` (lines 186 and 235), both for avatar images. No path deletes a document object — not rejection, not re-upload, not suspension, not deactivation. A captain who applies, is rejected, and never returns leaves a scan of their national ID in the bucket permanently.

F-25-05 is the sharper edge. When a captain re-uploads a document type, `captain.ts:567` runs `DELETE FROM driver_documents WHERE captain_id = ? AND type = ? AND status != 'approved'`. That row held `r2_key` — the only reference to the object. The object stays; the pointer is destroyed. The platform is therefore accumulating identity scans it can no longer enumerate, attribute, or delete through any application code path. A right-to-erasure request could not be honoured for those objects even after the rest of this plan is built, without a bucket-wide listing and reconciliation job. Every day of operation makes that job larger.

**F-25-06 · Nobody can tell who looked at a national ID.** `logAudit` is called for approvals, suspensions, pricing changes, config changes, document review decisions and payment webhooks. It is called on zero read paths. The three endpoints that expose identity data most directly — the document image stream (`admin.ts:894`), the bulk document list that returns `national_id_number` (`admin.ts:620-679`), and the captain list that returns `c.*` including `national_id_number` and `birth_date` (`admin.ts:229-258`) — write nothing. Combined with F-25-15 (one undifferentiated admin role), the platform has no answer to the most basic insider-risk question. Audit of *access to* sensitive data, not merely modification of it, is the control that regulators look for first, and it is the cheapest S1 on this list to fix.

**F-25-07 · The movement trace has no end date.** `trip_path_points` takes a position every 30 seconds of every active trip (`captain.ts:237-252`), storing latitude, longitude and heading against a timestamp, indexed for efficient retrieval by trip and time (`0002:23-24`). Nothing deletes it. The `ON DELETE CASCADE` on `trip_id` is not a retention mechanism because trips are never deleted. Over a year of operation this becomes a queryable, indexed history of where every captain physically was, minute by minute, for their entire tenure. There is no stated purpose that requires keeping a completed trip's breadcrumb trail beyond the dispute window. This dataset is the one most likely to cause acute harm if leaked and the one with the weakest justification for existing at rest.

**F-25-08 · Trip coordinates go to a demo server.** `routing.ts:28` builds `https://router.project-osrm.org/route/v1/driving/${pickup.lng},${pickup.lat};${dropoff.lng},${dropoff.lat}`. `routing.ts:121` sends the live positions of multiple captains plus a rider's pickup to the `/table` endpoint. `router.project-osrm.org` is the OSRM project's public demonstration instance, hosted in Germany. It is offered for evaluation, not production; there is no contract, no SLA, no confidentiality undertaking, and no data-processing agreement. The coordinates travel in the URL path, which means they are written to that operator's access logs in the clear. `wrangler.toml:88` sets this as the default and the production environment block does not override it, so this is what ships. This is simultaneously a privacy failure, an availability risk owned by T21, and a cost/scale risk owned by T24 — but the privacy dimension is the one that makes it a launch blocker.

**F-25-09 · Plaintext national IDs, served in bulk.** `captains.national_id_number` (`0015:15`) and `driver_documents.national_id_number` (`0012:11`) are `TEXT` columns written directly from the request body (`captain.ts:574-587`). Two admin endpoints return them wholesale: `admin.ts:229-258` selects `c.*` from `captains`, and `admin.ts:620-679` selects `d.*` from `driver_documents` alongside captain email and phone, paginated at 50 captains. One compromised admin session yields the national ID, full legal name, date of birth, phone and email of the entire captain fleet in a handful of requests, with no audit trail (F-25-06) and no rate limit specific to bulk PII.

**F-25-10 · There is no way to know a breach happened.** PDPL requires notification to the Personal Data Protection Center within 72 hours (`confident`, subject to the executive regulations — see §10). That clock starts when the controller becomes aware. This platform has no access logging on PII reads, no anomaly detection, no alerting on bulk exports, and no documented incident runbook anywhere in the repository. In its current state, the realistic detection path for a D1 compromise is a third party telling the company. The obligation cannot be met by a team that cannot see the event.

### The S2 set, in prose

**F-25-11, F-25-12 · The audit log is a permanent PII store, and it holds bank details.** `audit_log` carries `ip` and `user_agent` on every row (`0002:39-49`) and nothing ever deletes from it. Worse, `wallet.ts:139` passes `JSON.stringify(body)` as the audit payload for `wallet.payout.request`, and that body contains `account_info` — a free-text bank account number, IBAN, or Vodafone Cash number. The same value is concatenated into `wallet_transactions.note` at `wallet.ts:129` as `"<method>:<account_info>"`. So a captain's bank account number is written to two separate permanent stores, one of which is readable through an admin endpoint that is itself unaudited (F-25-29). Redacting the audit payload is a one-line change; the ledger `note` needs a column and a short migration.

**F-25-13 · A public endpoint contradicts its own comment.** `safety.ts:88-89` says: *"public read-only view for shared trips. Returns only the trip status + last path point (lat/lng), no PII."* The handler then returns `pickup` and `dropoff` — full street addresses from `trips.pickup_address` / `dropoff_address` — at lines 119-120, plus the most recent path point. The token itself is strong (`crypto.randomUUID`, `utils.ts:9-12`), so this is not brute-forceable; the problem is that the disclosure is broader than designed and than documented, and safety-share links are routinely forwarded into group chats. A recipient meant to see "she's 5 minutes away" also learns exactly where she was picked up and exactly where she is going. Expiry is enforced (`safety.ts:99-101`) and revocation exists (`safety.ts:126-135`), which is good; the payload is what needs narrowing.

**F-25-15 · One role for everything.** `requireRole("admin")` is a flat membership test (`middleware/auth.ts:67-74`). There is no reviewer role that can approve a document without reading the ID number, no support role that can resolve a fare dispute without opening a licence scan, and no read-only role for analysts. Least privilege is the control that limits the blast radius of F-25-06 and F-25-09; without it, every operator account is equivalent to a full PII export. The role model itself belongs to T02 — I am claiming the requirement, not the design.

**F-25-16 · Tokens in URLs.** `middleware/auth.ts:21-27` permits `?token=` for any `/ws/` path and for `/admin/documents/:id/file`. The file's own comment (lines 16-19) states the objection precisely — query tokens leak into server logs, proxy logs, browser history and the `Referer` header — and then grants the exception anyway. `index.ts:144` and `:199` repeat it inline with a `DEPRECATED` marker and no removal date. The JWT carries `id`, `email`, `name` and `role` (`middleware/auth.ts:55-60`), so a leaked URL leaks identity, not just a session. The `<img src>` case has a clean fix: a short-lived, single-purpose, single-object view token that is not the session JWT.

**F-25-17 · Errors talk too much.** `index.ts:233-236` returns `err.message` to the caller for any unhandled exception. D1 surfaces constraint violations as text that can embed the offending value — a `UNIQUE constraint failed: users.phone` response confirms an account exists for a probed number, which is an enumeration oracle. `payments.ts:91` is more direct: it returns `(e as Error).message` from the Paymob path, and `paymob.ts:31/49/78` throw with `data.detail` straight from the PSP, which can echo submitted billing fields. Both should return an opaque message with a correlation ID and keep the detail server-side.

**F-25-18, F-25-19 · Third parties, no paperwork.** Nominatim receives coordinates rounded to 4 decimal places — about 11 metres, enough to identify a building — in a GET query string (`geocode.ts:39-40`), and raw typed search text likewise (`geocode.ts:100-102`). Meta receives phone numbers (`notifications.ts:114`); Resend receives email addresses together with the OTP code in the message body (`notifications.ts:175`). None of these has a data-processing agreement visible in the repository, and none is disclosed to users, because there is no document in which to disclose it (F-25-01). The KV caches (`geocode.ts:82`, `:128`) reduce volume but not the legal character of the transfer.

**F-25-21, F-25-22 · Identifiers hiding in keys and forgotten tables.** `auth.ts:98` writes a KV entry keyed `otp-name:<phone or email>`; the TTL is 600 seconds, so the exposure is bounded, but the key namespace itself carries contact data. `turnstile_verifications` stores an IP per verification (`0003:201-209`) and is excluded from cleanup by a comment (`cleanup.ts:11-13`) asserting the table does not exist in migrations 0001–0010 — it was added in `0003`. A stale comment is now the only reason an IP table grows without bound.

**F-25-23 · The governance layer is absent, not weak.** No `jurisdiction` key or Data Localization configuration in `wrangler.toml`; no designated data-protection officer; no record of processing activities; no DPA templates; no retention policy document; no incident runbook. These are not code, which is precisely why they get skipped, and they are the artefacts a regulator asks for first.

**F-25-24 · Over-declared permissions on the rider app.** `apps/rider/ios/Runner/Info.plist:51` declares `NSLocationAlwaysAndWhenInUseUsageDescription` and lines 57-59 declare `UIBackgroundModes: location`, while the rider Android manifest carries a comment at line 8 explaining that background location was deliberately removed because no foreground service exists. The two platforms disagree, and the iOS side asks for more than the product uses. Data minimisation is a PDPL principle and an App Review criterion at the same time.

---

## 5. Benchmark gap

### 5.1 Egypt PDPL 151/2020 — obligation to implementation

Law 151 of 2020 has applied since October 2020. Article numbers below are given for orientation and are marked for confidence; the executive regulations govern much of the operational detail and **their current status and text must be confirmed by Egyptian counsel** (`needs-check`, §10 Q1). The obligations themselves — lawful basis, transparency, data-subject rights, security, breach notification, DPO, sensitive-data licensing, cross-border permitting — are the settled structure of the statute and are marked `confident`.

| # | Obligation (PDPL) | What it requires | Synaptic Go today | Gap | Blocks launch? |
|---|---|---|---|---|---|
| 1 | Lawful basis for processing (Art. 2, 3) | An identified basis per purpose; consent must be specific, informed, documented | No policy, no purpose register, consent not recorded (`auth.ts:347-383`) | Total | **Yes** |
| 2 | Transparency / notice (Art. 2) | Accessible notice: identities, purposes, recipients, transfers, retention, rights | No policy anywhere; dead link at `settings_screen.dart:519` | Total | **Yes** |
| 3 | Right of access (Art. 2) | Provide a copy of the data held | No endpoint | Total | **Yes** |
| 4 | Right of correction (Art. 2) | Rectify inaccurate data | Partial — profile edit only; no correction of documents or trip data | Large | No |
| 5 | Right of erasure (Art. 2) | Delete on request, subject to lawful retention | No mechanism; R2 objects undeletable in part (F-25-05) | Total | **Yes** |
| 6 | Right to portability (Art. 2) | Structured, machine-readable export | No endpoint | Total | No (P1) |
| 7 | Right to withdraw consent (Art. 7) | As easy to withdraw as to give | Nothing to withdraw — nothing recorded | Total | **Yes** |
| 8 | Data minimisation & purpose limitation (Art. 3) | Collect only what the purpose needs | 30-second traces kept forever; iOS always-on location unused (F-25-07, F-25-24) | Large | **Yes** (traces) |
| 9 | Storage limitation (Art. 3) | Keep only as long as the purpose requires | Two tables purged out of ~30 (`cleanup.ts:29-57`) | Near-total | **Yes** |
| 10 | Security of processing (Art. 4, 8) | Appropriate technical and organisational measures | Transport TLS and platform-default at-rest only; national IDs plaintext; no least privilege | Large | **Yes** (plaintext IDs, no access audit) |
| 11 | Accountability / records of processing | Demonstrate compliance; maintain a register | No register, no DPIA, no policy set | Total | **Yes** |
| 12 | Data Protection Officer (Art. 8 / 12) | Appoint a DPO, publish contact, register | None designated | Total | **Yes** |
| 13 | Breach notification (Art. 7 / 13) | Notify the Center within 72 hours; notify data subjects for high-risk breaches | No detection, no runbook, no contact path (F-25-10) | Total | **Yes** |
| 14 | Sensitive personal data licensing | A permit from the Personal Data Protection Center to process sensitive categories; financial data is enumerated as sensitive | Wallet, ledger, payout accounts, payment tokens all processed; no permit referenced | Total | **Yes** — `needs-legal-review` |
| 15 | Cross-border transfer permit (Art. 14-16) | Transfer outside Egypt needs a permit and an adequate protection level | Meta, Resend, Google, OSM, OSRM, Cloudflare — no permits, no DPAs, no residency pinning | Total | **Yes** |
| 16 | Processor contracts (Art. 5) | Written terms binding each processor | No DPA visible for any provider; OSRM has no contract at all | Total | **Yes** |
| 17 | Electronic marketing consent (Art. 19) | Prior consent, identity disclosed, opt-out available | Push/WhatsApp/email pipeline exists (`notifications.ts`) with no opt-out control in either app | Large | No (P1) — **Yes** if promotional sends start |
| 18 | Children's data | Sensitive category; heightened protection | No age gate, no DOB for riders | Unknown | `needs-check` |

**Penalty exposure.** Law 151/2020 attaches administrative fines and, for some offences, criminal liability; the sensitive-data and cross-border provisions attract the higher tiers. I am not going to quote figures I cannot verify against the current text — counsel should quantify (`needs-legal-review`). The point that matters for engineering prioritisation is that the two obligations carrying the heaviest penalties (sensitive-data processing and unpermitted cross-border transfer) are also two of the three most clearly breached today.

### 5.2 GDPR as the design template

GDPR is stricter than PDPL on several axes and is the sensible engineering target because it future-proofs expansion and because the tooling ecosystem assumes it. Three GDPR concepts should be adopted even though PDPL does not compel them in the same words:

- **Privacy by design and by default** (Art. 25) — retention windows and field-level access decided when a table is created, not retrofitted. Concretely: a `retention_policy` entry required alongside every new migration that adds a personal-data column.
- **DPIA for high-risk processing** (Art. 35) — systematic monitoring of individuals in a public space is the textbook trigger, and `trip_path_points` is exactly that. A DPIA on the location trace should gate its retention design.
- **Records of processing** (Art. 30) — the register that makes every other obligation answerable.

### 5.3 Uber, Careem and inDrive — the transparency standard

Claims below are marked `confident` where they describe long-standing, publicly documented product behaviour, and `assumed` otherwise.

| Capability | Uber | Careem | inDrive | Synaptic Go |
|---|---|---|---|---|
| Public privacy centre with per-region notices | Yes — `confident` | Yes — `confident` | Yes — `assumed` | **None** |
| In-app account deletion | Yes — `confident` | Yes — `confident` | Yes — `assumed` | **None** |
| Self-service data download / export | Yes — `confident` | Yes — `assumed` | `assumed` | **None** |
| Trip data visible to the user (history, map) | Yes — `confident` | Yes — `confident` | Yes — `confident` | Trip history yes; no privacy framing |
| Phone-number masking between rider and driver | Yes — `confident` | Yes — `confident` | Partial — `assumed` | **No masking; in-app chat only** |
| Granular staff access tiers + access auditing | Yes — `confident` (post-2014 "God View" enforcement action) | `assumed` | `assumed` | **Neither** |
| Published retention periods per data category | Yes — `confident` | Yes — `assumed` | `assumed` | **None** |
| Driver-document handling disclosed | Yes — `confident` | Yes — `assumed` | `assumed` | **Not disclosed; never deleted** |
| Data-safety / permissions rationale in store listing | Yes — `confident` | Yes — `confident` | Yes — `confident` | Not present in repo — T26 |

The most instructive precedent is Uber's own history: the "God View" episode led directly to an enforcement settlement whose remedy was, in substance, F-25-06 and F-25-15 — restrict staff access to rider location by role, and log every access. Synaptic Go currently sits where Uber sat before that settlement: `GET /admin/online-captains` returns the live position of every working captain with their name, email and phone (`admin.ts:925-936`), to any admin, with no record that anyone looked.

The gap to close is not exotic. It is: publish a notice, record consent, let people leave, delete what you no longer need, restrict and log who can see identity documents, and put contracts under the third parties you already use.

---

## 6. Improvement plan

### 6.1 The retention schedule to implement

This is the target state. "Basis" is the reason for keeping it that long; anything without a basis gets the minimum. Periods are proposals for the product owner to ratify with counsel (§10 Q3).

| Data category | Table(s) | Proposed retention | Basis | Deletion mechanism |
|---|---|---|---|---|
| OTP codes | `otp_codes` | 24 h after expiry | already implemented | `cleanup.ts:36` (keep) |
| Refresh tokens | `refresh_tokens` | 7 d after revoke/expiry | already implemented | `cleanup.ts:49` (keep) |
| Turnstile records | `turnstile_verifications` | 30 d | anti-abuse forensics | new cron delete |
| **Movement trace** | `trip_path_points` | **90 d raw, then delete** (aggregate distance/duration onto `trips` before deletion) | dispute and safety investigation window | new cron delete + rollup |
| Live position | `captains.last_lat/lng` | null after 24 h offline | dispatch only | cron nulling |
| Trip records | `trips`, `trip_events` | 7 y (financial), coordinates coarsened to ~1 km after 12 m | tax/accounting retention; dispute defence | cron update + archive |
| Chat messages | `trip_chat_messages` | 12 m | dispute and safety investigation | cron delete |
| SOS alerts | `sos_alerts` | 7 y | safety incident record, potential litigation | manual review before delete |
| Identity documents (approved, active captain) | `driver_documents` + R2 | duration of engagement + 12 m | regulatory driver-vetting | lifecycle job |
| Identity documents (rejected / superseded) | `driver_documents` + R2 | **30 d** | appeal window | lifecycle job + orphan reconciliation |
| Financial ledger | `wallet_transactions`, `payment_intentions` | 7 y | Egyptian tax/accounting retention — `needs-legal-review` | archive, no delete |
| Payout account identifiers | `wallet_transactions.note`, `audit_log.payload` | **redact at write**; keep last 4 only | no basis for full retention | code change + backfill |
| Payment tokens | `payment_methods` | until removed by user + 90 d | chargeback window | cron delete |
| Device tokens | `device_tokens` | 90 d since last successful send | deliverability | cron delete |
| Notification log | `notification_log` | 90 d; strip FCM token at write | debugging | code change + cron |
| Audit log — writes | `audit_log` | 24 m | accountability | cron delete |
| Audit log — PII access (new) | `pii_access_log` | 24 m | insider-risk investigation | cron delete |
| Share tokens | `trip_share_tokens` | 30 d after expiry | none beyond audit | cron delete |
| Account on erasure request | `users` + cascade | 30 d grace, then anonymise | fraud re-registration check | erasure job |

### 6.2 P0 — before any production traffic

#### P0.1 — Publish the notice, capture consent server-side
- **Goal** — every user is told what happens to their data before they hand it over, and the company can prove they were told.
- **Design** — author a Privacy Policy and Terms of Service in Arabic and English, versioned (`v1.0`, ISO date). Host as static pages. On sign-up the checkbox links to them; on submit the client sends `termsVersion` and `privacyVersion`. The server writes a `user_consents` row. A version bump triggers an in-app re-consent sheet on next launch. Consent rows are append-only — withdrawal is a new row, never an update.
- **Files to change** — `apps/api/src/routes/auth.ts` (register + OTP verify), `apps/api/src/lib/schemas.ts`, `apps/rider/lib/screens/login_screen.dart`, `apps/captain/lib/screens/login_screen.dart`, both `profile/settings_screen.dart`, `packages/flutter_shared/lib/l10n/app_strings.dart`, new `docs/legal/privacy-policy.md` and `terms-of-service.md`.
- **DB** — `migrations/0020_consent_records.sql`:
  ```sql
  CREATE TABLE IF NOT EXISTS user_consents (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document TEXT NOT NULL CHECK (document IN ('privacy','terms','marketing')),
    version TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('granted','withdrawn')),
    ip TEXT, user_agent TEXT, locale TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE INDEX IF NOT EXISTS idx_consent_user ON user_consents(user_id, document, created_at);
  ```
- **API contract** — `POST /auth/register` and `POST /auth/verify-otp` gain required `consents: [{document, version}]`; reject with `CONSENT_REQUIRED` if absent. New `GET /user/consents` → `{ consents: [{document, version, action, created_at}] }`. New `POST /user/consents` for withdrawal.
- **Effort** — M (backend S, two Flutter apps M, policy drafting is counsel's clock not engineering's).
- **Risk** — old app builds do not send the fields. Mitigate with a two-week grace: log `consent_missing` and backfill a prompt on next launch rather than hard-failing sign-in.
- **Acceptance criteria** — (1) A new account cannot be created without a consent row. (2) The policy is reachable in two taps from settings in both apps. (3) Bumping the version re-prompts existing users. (4) Withdrawal is recorded and visible.
- **Tests** — unit: register without consent → 400. Integration: register → consent row exists with correct version and IP. Widget: checkbox link opens the policy. Migration test: table created idempotently.

#### P0.2 — Data-subject rights: export and erasure
- **Goal** — a user can obtain their data and can leave, and the company can honour a regulator's order.
- **Design** — `DELETE /user/account` starts a 30-day grace: set `users.status='pending_deletion'`, `deletion_requested_at`, revoke all sessions and device tokens immediately, hide the account from dispatch. A daily job then executes erasure: hard-delete the cascade set; **anonymise** rather than delete the financially and legally retained set (`trips`, `wallet_transactions`, `sos_alerts`) by repointing to a tombstone user and nulling free-text. Delete all R2 objects under `docs/<userId>/` and the avatar. Write a `pii_access_log` row for the operation. Export is `POST /user/export` → job → signed download of a JSON bundle plus the user's documents, delivered in-app, expiring in 72 h.
- **Files to change** — `apps/api/src/routes/user.ts`, new `apps/api/src/lib/erasure.ts` and `export.ts`, `apps/api/src/index.ts` (cron), both apps' settings screens, `apps/admin/src/pages/UsersPage.tsx` (ops view of pending erasures).
- **DB** — `migrations/0021_erasure_requests.sql`: add `users.deletion_requested_at TEXT`, `users.anonymised_at TEXT`; create `erasure_requests(id, user_id, requested_at, scheduled_for, completed_at, status, notes)`. Also seed a reserved tombstone user row.
- **API contract** — `DELETE /user/account` → `202 {scheduledFor}`; `POST /user/account/cancel-deletion` → `200`; `POST /user/export` → `202 {jobId}`; `GET /user/export/:jobId` → `{status, downloadUrl?, expiresAt?}`.
- **Effort** — L.
- **Risk** — over-deletion breaks financial integrity (T03's ledger must still balance). Mitigate by making the anonymisation set explicit and covered by a test asserting ledger totals are unchanged before and after. Rollback: the 30-day grace means nothing is destroyed for a month.
- **Acceptance criteria** — (1) Deletion is reachable in-app in both apps. (2) After execution, no query returns the user's name, phone, email, documents or path points. (3) Ledger sums are unchanged. (4) Export bundle round-trips to valid JSON and contains every category in §3.9.
- **Tests** — integration: full lifecycle request → grace → execute → assert per-table row counts. Property test: ledger invariants hold. Manual: App Store deletion-policy walkthrough.

#### P0.3 — Document lifecycle and the orphan reconciliation
- **Goal** — an identity document exists for exactly as long as there is a reason for it, and no scan exists that the platform cannot find.
- **Design** — three parts. (a) Wherever a `driver_documents` row is deleted or superseded, delete the R2 object in the same handler — fix `captain.ts:567` and `captain.ts:605`. (b) A retention job deletes rejected/superseded documents after 30 days and documents of departed captains after engagement + 12 months. (c) A **one-off reconciliation**: list the `FILES` bucket under `docs/`, join against `driver_documents.r2_key`, and quarantine then delete objects with no row. Run it before launch and keep it as a monthly integrity job — this is the only way to clear the backlog created by F-25-05.
- **Files to change** — `apps/api/src/routes/captain.ts`, `apps/api/src/routes/admin.ts`, new `apps/api/src/lib/documentLifecycle.ts`, `apps/api/src/index.ts` (cron), new `scripts/r2-orphan-reconcile.ts`.
- **DB** — `migrations/0022_document_lifecycle.sql`: add `driver_documents.deleted_at TEXT`, `driver_documents.purge_after TEXT`; index on `purge_after`.
- **API contract** — none changed. Internal cron only.
- **Effort** — M.
- **Risk** — deleting a document still needed for a regulatory check. Mitigate: soft-delete for 30 days (`deleted_at`) before the R2 object goes, and never auto-purge documents for captains in `approved` + `active` state.
- **Acceptance criteria** — (1) Re-uploading a document leaves zero orphaned objects. (2) The reconciliation script reports zero orphans on a second run. (3) A rejected document is gone from R2 within 31 days.
- **Tests** — integration: upload → re-upload → assert `FILES.get(oldKey)` is null. Script test against a seeded bucket with known orphans.

#### P0.4 — Audit every read of sensitive data
- **Goal** — the company can answer "who looked at this citizen's national ID, and when".
- **Design** — a dedicated `pii_access_log` (separate from `audit_log` so retention and alerting differ). A small middleware wraps the PII-returning admin endpoints and records actor, endpoint, subject ID(s), record count, IP, user agent and — for the document image route — the document ID. Add a required `reason` query parameter on the document image and bulk document endpoints, surfaced in the console as a short prompt. Alert on bulk thresholds (one operator reading more than N distinct subjects in an hour).
- **Files to change** — new `apps/api/src/middleware/piiAccess.ts`, `apps/api/src/routes/admin.ts` (the seven endpoints in §3.5), `apps/api/src/routes/captain.ts:673` (the admin bypass), `apps/admin/src/pages/CaptainVerificationPage.tsx` and `UsersPage.tsx` (reason prompt).
- **DB** — `migrations/0023_pii_access_log.sql`:
  ```sql
  CREATE TABLE IF NOT EXISTS pii_access_log (
    id TEXT PRIMARY KEY,
    actor_id TEXT NOT NULL,
    action TEXT NOT NULL,
    subject_user_id TEXT,
    entity_type TEXT, entity_id TEXT,
    record_count INTEGER NOT NULL DEFAULT 1,
    reason TEXT,
    ip TEXT, user_agent TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE INDEX IF NOT EXISTS idx_pii_actor_time ON pii_access_log(actor_id, created_at);
  CREATE INDEX IF NOT EXISTS idx_pii_subject ON pii_access_log(subject_user_id, created_at);
  ```
- **API contract** — `GET /admin/documents/:id/file?reason=<text>` and `GET /admin/documents?reason=<text>` require the parameter (min 3 chars); 400 `REASON_REQUIRED` otherwise. New `GET /admin/pii-access-log` (restricted, see P1.1).
- **Effort** — M.
- **Risk** — logging failures must not block review work. Reuse the swallow-and-continue pattern from `audit.ts:33-36`, but emit a metric on failure so silence is visible.
- **Acceptance criteria** — (1) Every endpoint in the §3.5 table writes exactly one row per request. (2) Given a captain ID, a single query lists every operator who viewed their documents. (3) Bulk reads record the row count.
- **Tests** — integration per endpoint asserting a row is written; negative test that a missing reason is rejected; load test that logging adds under 20 ms.

#### P0.5 — Implement the retention schedule
- **Goal** — data stops accumulating without justification; §6.1 becomes code.
- **Design** — extend `runExpiredDataCleanup` from two statements into a table-driven engine: a declarative list of `{table, predicate, batchSize}` executed in batches with per-table counts written to `audit_log` as today. Periods come from `system_config` (`migrations/0016_system_config.sql` already provides the mechanism) so they are tunable without a deploy. Start with `turnstile_verifications`, `trip_share_tokens`, `notification_log`, `audit_log`, `device_tokens`, then `trip_chat_messages`, then `trip_path_points` with the rollup. **Fix the stale docstring at `cleanup.ts:3-14` in the same PR.**
- **Files to change** — `apps/api/src/lib/cleanup.ts` (rewrite), `apps/api/src/index.ts` (the cron already fires daily), `migrations/0024_retention_config.sql` (seed `system_config` keys), `apps/admin/src/pages/` (a read-only retention status panel).
- **DB** — `0024` seeds config keys; `0025_trip_path_rollup.sql` adds `trips.path_distance_m INTEGER`, `trips.path_point_count INTEGER` so the trace can be summarised before deletion.
- **API contract** — none. Internal.
- **Effort** — L.
- **Risk** — a bad predicate deletes live data. Mitigate: every statement is `SELECT COUNT(*)`-previewed in a dry-run mode gated by a config flag, run in dry-run for one week in production before enabling, and batch-limited so a mistake is bounded per run.
- **Acceptance criteria** — (1) Every table in §6.1 has either an implemented rule or a written exemption. (2) Dry-run output matches expected counts on seeded data. (3) Path points older than the window are gone and the trip carries the rollup.
- **Tests** — unit per predicate against a seeded D1; integration asserting dry-run deletes nothing; a regression test that `trips` row counts never change.

#### P0.6 — Get trip coordinates off the public demo server
- **Goal** — no citizen's origin-destination pair reaches a third party without a contract.
- **Design** — replace `router.project-osrm.org` with either a self-hosted OSRM on a contracted host or a commercial provider under a DPA. Self-hosting is the privacy-strongest option and keeps costs predictable (T24 owns the cost model). Whichever is chosen, move coordinates out of the URL path where the provider's API allows a POST body, and set `OSRM_URL` per environment with **no working public default** — the code should fail closed if the variable is unset rather than silently falling back.
- **Files to change** — `apps/api/src/lib/routing.ts` (remove the default at line 15, add fail-closed), `apps/api/wrangler.toml:88` and the production vars block, `docs/DEPLOYMENT.md`.
- **DB** — none.
- **API contract** — none externally.
- **Effort** — M for the code, L including provisioning.
- **Risk** — routing outage if the new endpoint is misconfigured; fail-closed turns a silent privacy leak into a visible incident, which is the correct trade but must be staged. Roll out behind a config flag with health checks. Rollback is a config change.
- **Acceptance criteria** — (1) No request leaves the platform to `router.project-osrm.org` in any environment. (2) An unset `OSRM_URL` fails the health check at deploy rather than at runtime. (3) A signed DPA exists for whatever replaces it.
- **Tests** — a CI grep asserting the string `router.project-osrm.org` appears nowhere outside documentation; integration test against the new endpoint; a negative test that an unset variable fails startup.

#### P0.7 — Stop the incidental leaks
- **Goal** — remove the three cheap disclosure paths before launch.
- **Design** — (a) `index.ts:233-236` returns a generic message plus a correlation ID; the detail goes to the log only. Same for `payments.ts:91`. (b) Replace the `?token=` carve-out for `/admin/documents/:id/file` (`middleware/auth.ts:25`) with a short-lived, single-object view token minted by an authenticated call and valid for 60 seconds; keep the `/ws/` carve-out only until the first-message auth flow is confirmed shipped in both apps, then delete it. (c) Narrow `GET /track/:token` (`safety.ts:116-122`) to status, ETA and last point — drop `pickup` and `dropoff`, and correct the comment at `safety.ts:88-89` so it matches the code.
- **Files to change** — `apps/api/src/index.ts`, `apps/api/src/routes/payments.ts`, `apps/api/src/middleware/auth.ts`, `apps/api/src/routes/safety.ts`, `apps/api/src/routes/admin.ts`, `apps/admin/src/pages/CaptainVerificationPage.tsx`, both apps' trip-share UI.
- **DB** — none (view tokens live in KV with a TTL).
- **API contract** — new `POST /admin/documents/:id/view-token` → `{token, expiresAt}`; `GET /admin/documents/:id/file?vt=<token>`. `GET /track/:token` response loses `pickup` and `dropoff`.
- **Effort** — S.
- **Risk** — the share view becomes less useful; product may object to losing the destination. Compromise available: show a coarsened destination (district name) rather than a street address. Decide in §10 Q5.
- **Acceptance criteria** — (1) A 500 never contains a DB or PSP string. (2) The session JWT is rejected as `?token=` on the document route. (3) `/track/:token` returns no address field.
- **Tests** — integration forcing a UNIQUE violation and asserting the response body is generic; auth test that a session JWT in `?token=` fails; contract test on the track payload.

#### P0.8 — Redact financial account identifiers at the write path
- **Goal** — bank and mobile-money account numbers stop being written to permanent logs.
- **Design** — introduce `redactForAudit()` with an explicit deny-list (`account_info`, `password`, `code`, `token`, `national_id_number`, `nationalIdNumber`) applied inside `logAudit` itself so no future call site can bypass it. Change `wallet.ts:129` to store `"<method>:••••<last4>"` in `note` and put the full value in a new payout-detail row that is deleted once the payout settles. Backfill: scrub existing `audit_log.payload` and `wallet_transactions.note` values.
- **Files to change** — `apps/api/src/lib/audit.ts`, `apps/api/src/routes/wallet.ts`, new `scripts/backfill-redact-payouts.ts`.
- **DB** — `migrations/0026_payout_details.sql`: `payout_details(id, wallet_transaction_id, method, account_ref_encrypted, last4, created_at, purged_at)`.
- **API contract** — unchanged for clients.
- **Effort** — S (M with backfill).
- **Risk** — finance ops needs the full account number to execute a payout. That is exactly why it goes in `payout_details` with a purge on settlement rather than being deleted outright. Coordinate with T04.
- **Acceptance criteria** — (1) No new `audit_log` row contains a value matching the deny-list keys. (2) `wallet_transactions.note` contains only a masked reference. (3) Backfill leaves zero unmasked historical values.
- **Tests** — unit on `redactForAudit` with nested objects; integration asserting a payout request writes a masked note; a repo-wide test scanning a seeded audit table for account-number patterns.

#### P0.9 — Breach detection and the response runbook
- **Goal** — the company can notice a breach and meet the 72-hour clock.
- **Design** — the detection half is mostly delivered by P0.4: alert on anomalous PII access volume. Add alerts for failed-auth spikes, admin role changes, and mass export. The response half is a written runbook: severity definitions, who declares an incident, the DPO's notification duty and template, the data-subject notice template in Arabic and English, evidence-preservation steps, and a contact list. Rehearse once with a tabletop exercise before launch.
- **Files to change** — new `docs/runbooks/data-breach.md`, `docs/runbooks/breach-notification-templates.md`; alert wiring coordinated with T22.
- **DB** — none.
- **API contract** — none.
- **Effort** — M (mostly writing and one rehearsal).
- **Risk** — a runbook nobody has read. Mitigate with the tabletop and an annual repeat.
- **Acceptance criteria** — (1) The runbook names a decision-maker and a deadline for each step. (2) A tabletop exercise is completed and its gaps logged. (3) Alerts fire on a simulated bulk read.
- **Tests** — the exercise itself; a synthetic bulk-read that must page someone.

#### P0.10 — The governance pack (legal-led, engineering-supported)
- **Goal** — the artefacts a regulator asks for exist before anyone asks.
- **Design** — designate and register a DPO with published contact details. Build the record of processing activities from §3.9 — the inventory in this document is the first draft. Execute DPAs with Cloudflare, Meta, Resend, Google, Paymob and the chosen routing provider. Apply for the sensitive-data processing permit and the cross-border transfer permit. Run a DPIA on the location trace before P0.5 fixes its retention, so the retention period has a documented rationale.
- **Files to change** — `docs/legal/ropa.md`, `docs/legal/dpia-location.md`, `docs/legal/subprocessors.md` (public list), `docs/legal/dpo.md`.
- **DB** — none.
- **API contract** — none.
- **Effort** — L, and the calendar is counsel's and the regulator's, not engineering's. **Start this first** — the permits have lead times that no amount of engineering speed will compress.
- **Risk** — launch slips waiting on a permit. That risk is real and it is the reason this item is listed first in §7 rather than last.
- **Acceptance criteria** — DPO appointed and published; RoPA covers every category in §3.9; a signed DPA per processor; permit applications filed with dated receipts; DPIA signed off.
- **Tests** — not applicable; evidence is documentary. A quarterly review confirms the sub-processor list still matches the code.

### 6.3 P1 — first 30 days

#### P1.1 — Graded admin roles and PII masking
- **Goal** — most operators never see a national ID.
- **Design** — split `admin` into `support`, `reviewer`, `finance`, `superadmin`. Mask `national_id_number` to last 4 everywhere except the reviewer surface; mask phone to last 3 in list views with click-to-reveal, which writes a `pii_access_log` row. Replace `SELECT c.*` (`admin.ts:229-258`) and `SELECT d.*` (`admin.ts:620-679`) with explicit column lists so a new sensitive column is never exposed by default. Remove the admin bypass at `captain.ts:680`.
- **Files** — `apps/api/src/middleware/auth.ts`, `apps/api/src/routes/admin.ts`, `apps/admin/src/pages/*`. **DB** — `migrations/0027_admin_roles.sql`. **API** — role claim in JWT; 403 shape unchanged. **Effort** — L. **Risk** — locking out real operators; ship with a migration mapping existing admins to `superadmin` and downgrade deliberately. **Acceptance** — a `support` token receives 403 on the document image route; list views show masked values. **Tests** — a matrix test of role × endpoint. Design owned by T02.

#### P1.2 — Protect the national ID number at rest
- **Goal** — a D1 dump does not hand over the fleet's national IDs.
- **Design** — application-layer encryption via a Worker secret (AES-GCM through WebCrypto), storing ciphertext plus a searchable HMAC for exact-match lookup, and a plaintext `last4` for display. Migrate both copies (`captains`, `driver_documents`) and stop writing plaintext at `captain.ts:574-587`.
- **Files** — new `apps/api/src/lib/fieldCrypto.ts`, `apps/api/src/routes/captain.ts`, `admin.ts`. **DB** — `migrations/0028_encrypt_national_id.sql` adding `*_enc`, `*_hmac`, `*_last4`, plus a backfill and a later column drop. **Effort** — L. **Risk** — key loss makes the data unreadable; document key custody and rotation before enabling. **Acceptance** — no plaintext national ID column remains readable; exact-match search still works. **Tests** — round-trip encryption, backfill idempotency, search parity.

#### P1.3 — Notification preferences and marketing consent
- **Goal** — users can turn off what they did not ask for, satisfying PDPL Art. 19 before any promotional send.
- **Design** — a preferences table keyed by channel and category; the notification pipeline consults it before enqueueing. Settings UI in both apps. Marketing consent recorded through the P0.1 `user_consents` mechanism with `document='marketing'`.
- **Files** — `apps/api/src/lib/notifications.ts`, `apps/api/src/routes/user.ts`, both settings screens. **DB** — `migrations/0029_notification_preferences.sql`. **API** — `GET/PUT /user/notification-preferences`. **Effort** — M. **Risk** — suppressing operational messages; category `operational` is non-optional and must be excluded from the UI. **Acceptance** — a disabled category produces no queue message. **Tests** — unit on the gate; integration on the full send path.

#### P1.4 — Close the remaining transfer and key-hygiene gaps
- **Goal** — third-party exposure is contracted, minimised and disclosed.
- **Design** — self-host Nominatim or move to a contracted geocoder; hash the identifier in the KV key at `auth.ts:98`; hash the IP in rate-limit keys (`rateLimit.ts:20,25`); strip the FCM token from `notification_log` payloads (`notifications.ts:351,359,367`); publish the sub-processor list from P0.10.
- **Files** — `apps/api/src/lib/geocode.ts`, `notifications.ts`, `middleware/rateLimit.ts`, `routes/auth.ts`. **DB** — none. **Effort** — M. **Risk** — hashed rate-limit keys break existing buckets; acceptable, they expire. **Acceptance** — no raw phone, email, IP or device token appears in any KV key or log payload. **Tests** — a scanner over KV key patterns in staging.

#### P1.5 — Mobile permission and store-readiness hygiene
- **Goal** — the apps ask for exactly what they use, in the user's language.
- **Design** — remove `NSLocationAlwaysAndWhenInUseUsageDescription` and the `location` background mode from the rider `Info.plist` unless and until a foreground service ships; localise all four purpose strings to English and Arabic; remove the unused `fetch` background mode from the captain plist if no `BGAppRefreshTask` exists; replace the dead privacy row with a real link.
- **Files** — `apps/rider/ios/Runner/Info.plist`, `apps/captain/ios/Runner/Info.plist`, both `AndroidManifest.xml`, both settings screens. **DB** — none. **Effort** — S. **Risk** — removing a permission an unshipped feature will need; re-add with the feature. **Acceptance** — permission set matches implemented functionality; prompts appear in the device language. **Tests** — manual on both platforms in both locales. Store-listing work is T26's.

### 6.4 P2 — next 90 days

- **P2.1 — Self-service DSAR portal.** Turn P0.2's endpoints into a guided in-app flow with status tracking and a documented SLA. **Effort** M.
- **P2.2 — Data residency decision.** Evaluate Cloudflare's regional options against the PDPL transfer position; pin what can be pinned; document what cannot. Depends on P0.10's permit outcome. **Effort** M, `needs-legal-review`.
- **P2.3 — Privacy dashboard in-app.** Show the user what is held about them: trips, saved places, documents, devices, consents — with per-item deletion where lawful. This is what closes the transparency gap against Uber and Careem in §5.3. **Effort** L.
- **P2.4 — Retention as a first-class schema concern.** A CI check that fails any migration adding a personal-data column without a matching entry in the retention config. **Effort** S, high leverage.
- **P2.5 — Real `LICENSE`.** Replace `test-license` (`LICENSE:1`) with the intended terms, and add third-party licence attribution for the Flutter and npm dependency trees. **Effort** S, `needs-legal-review`.
- **P2.6 — Annual DPIA refresh and access-log review cadence.** Quarterly review of `pii_access_log` anomalies; annual DPIA revisit. **Effort** S recurring.

---

## 7. Phasing

### 7.1 Blocks launch

Nothing below is optional before production traffic. Items are ordered by *when to start*, not by severity — P0.10 leads because permits and counsel have lead times engineering cannot compress.

| # | Item | Findings closed | Effort | Owner type |
|---|---|---|---|---|
| 1 | P0.10 — Governance pack: DPO, RoPA, DPAs, permits, DPIA | F-25-23 | L | legal + product |
| 2 | P0.1 — Privacy policy, terms, server-side consent | F-25-01, F-25-02 | M | legal + backend + Flutter ×2 |
| 3 | P0.6 — Replace the public OSRM demo server | F-25-08 | M (L with provisioning) | backend + ops |
| 4 | P0.4 — Audit reads of sensitive data | F-25-06, F-25-26, F-25-29 | M | backend + admin |
| 5 | P0.7 — Error messages, query tokens, share payload | F-25-13, F-25-16, F-25-17 | S | backend + admin + Flutter ×2 |
| 6 | P0.8 — Redact financial account identifiers | F-25-12 | S (M with backfill) | backend |
| 7 | P0.3 — Document lifecycle + orphan reconciliation | F-25-04, F-25-05 | M | backend + ops |
| 8 | P0.5 — Implement the retention schedule | F-25-07, F-25-11, F-25-14, F-25-20, F-25-22, F-25-31 | L | backend |
| 9 | P0.2 — Export and erasure | F-25-03 | L | backend + Flutter ×2 + admin |
| 10 | P0.9 — Breach detection and runbook | F-25-10 | M | ops + legal |

Two dependencies worth stating plainly. **P0.4 should land before P0.2**, because the erasure job is itself a bulk PII operation and ought to be logged from its first run. **The DPIA inside P0.10 should precede P0.5's location decision**, so that the 90-day retention window has a written rationale rather than being a number an engineer chose.

### 7.2 Needed within six months

| # | Item | Findings closed | Phase | Effort | Owner type |
|---|---|---|---|---|---|
| 11 | P1.1 — Graded admin roles and PII masking | F-25-09 (partial), F-25-15 | P1 | L | backend + admin (design: T02) |
| 12 | P1.2 — Encrypt the national ID at rest | F-25-09 | P1 | L | backend |
| 13 | P1.3 — Notification preferences and marketing consent | PDPL Art. 19 row | P1 | M | backend + Flutter ×2 |
| 14 | P1.4 — Transfer and key hygiene | F-25-18, F-25-19, F-25-21 | P1 | M | backend |
| 15 | P1.5 — Mobile permissions and purpose strings | F-25-24, F-25-25 | P1 | S | Flutter ×2 |
| 16 | P2.1 — Self-service DSAR portal | F-25-03 (UX) | P2 | M | backend + Flutter ×2 |
| 17 | P2.2 — Data residency decision | F-25-23 (partial) | P2 | M | ops + legal |
| 18 | P2.3 — In-app privacy dashboard | §5.3 transparency gap | P2 | L | Flutter ×2 + backend |
| 19 | P2.4 — Retention enforced in CI | prevents recurrence | P2 | S | backend |
| 20 | P2.5 — Real `LICENSE` and dependency attribution | F-25-28 | P2 | S | legal |
| 21 | P2.6 — DPIA refresh and access-review cadence | recurrence | P2 | S | legal + ops |
| 22 | Queue DLQ retention and DO storage lifetimes | F-25-27, F-25-30 | P1 | S | backend (investigate first) |

---

## 8. Metrics

Instrument these so the change is provable rather than asserted. "Current" is measured at commit `0f43270`.

| Metric | Current | Target | How measured |
|---|---|---|---|
| Tables with an enforced retention rule | 2 of ~30 (`cleanup.ts:36,49`) | 100% of personal-data tables, or a written exemption | count of rules in the retention config vs. inventory §3.9 |
| Oldest `trip_path_points` row | unbounded | ≤ 90 days | `SELECT MIN(recorded_at)` daily |
| Orphaned R2 objects under `docs/` | unknown, non-zero (F-25-05) | 0 | monthly reconciliation job output |
| Sensitive-data read events logged | 0% | 100% of the §3.5 endpoint list | `pii_access_log` rows ÷ endpoint request count |
| Operators able to read a national ID | all admins | reviewers only | role matrix test in CI |
| Users with a recorded consent row | 0 | 100% of accounts created after P0.1 | `COUNT(DISTINCT user_id)` in `user_consents` ÷ active users |
| Median time to fulfil an erasure request | n/a (impossible) | ≤ 30 days, p95 ≤ 30 days | `erasure_requests.completed_at − requested_at` |
| Median time to fulfil an export request | n/a | ≤ 72 hours | export job duration |
| Third parties receiving PII without a DPA | 6 of 7 | 0 | quarterly sub-processor review vs. signed agreements |
| Requests to `router.project-osrm.org` | all routed trips | 0 | egress metric + CI grep |
| 5xx responses containing a DB or PSP string | unknown, non-zero (F-25-17) | 0 | response-body scanner in integration tests |
| Audit rows containing a deny-listed key | non-zero (F-25-12) | 0 | scheduled scan of `audit_log.payload` |
| Time from breach detection to Center notification | no capability | < 72 hours, evidenced | incident record; tabletop until a real event |
| Apps exposing in-app account deletion | 0 of 2 | 2 of 2 | release checklist |

---

## 9. Cross-cutting notes

Things I found that belong to another track. Not fixed here.

**T01 — Auth, identity, sessions.** `otp_codes.code` is stored as plaintext (`migrations/0001_init.sql:18`, written at `apps/api/src/routes/auth.ts:91-95`). A database read yields directly usable authentication credentials for every unconsumed OTP. Store an HMAC instead. Separately, `DEV_OTP` returns the code in the response body (`auth.ts:122-125`); the committed value is `"false"` in both `[vars]` (`wrangler.toml:85`) and the production block, and `wrangler.toml:77-84` documents the bare-deploy hazard honestly — but the only control is a comment. A technical guard (refuse to start with `DEV_OTP=true` when the environment is production) belongs to T01 or T23.

**T02 — Authorization and RBAC.** The single `admin` role (`middleware/auth.ts:67-74`) is the structural cause of F-25-15, and the admin bypass at `captain.ts:680` lets any admin fetch any R2 key through the captain file route, sidestepping the document endpoint entirely. I have specified the privacy *requirement* in P1.1; the role model itself is yours.

**T03 — Money integrity.** `wallet.ts:129` writes `"<method>:<account_info>"` into `wallet_transactions.note`. My P0.8 changes that column's contents to a masked form and moves the full value to `payout_details`. If any reconciliation or payout tooling parses `note`, it will break — please check before P0.8 lands.

**T04 — Payments and payouts.** `payments.ts:91` returns the Paymob error string to the caller, and `paymob.ts:31/49/78` throw with `data.detail` from the PSP. Beyond the privacy leak, this couples your client contract to a third party's error text.

**T11 — Admin console.** Every PII-returning endpoint in §3.5 needs the reason prompt and masking from P0.4 and P1.1. `GET /admin/online-captains` (`admin.ts:925-936`) returning live coordinates plus name, email and phone for every working captain is the single most sensitive screen in the console and currently has no access control beyond "is an admin".

**T17 — Safety and trust.** `GET /track/:token` (`safety.ts:88-123`) returns pickup and dropoff addresses despite its own comment promising no PII. My P0.7 narrows the payload; if the safety UX depends on showing the destination, tell me and we will coarsen instead of remove (§10 Q5). Also: `sos_alerts` retains precise emergency coordinates forever with no review process — that is a safety-record question as much as a privacy one.

**T21 — Maps and routing.** F-25-08 is your dependency too. `router.project-osrm.org` is a demo instance with no SLA; the availability and accuracy arguments for replacing it point the same direction as the privacy argument.

**T22 — Observability.** `[observability] enabled = true` (`wrangler.toml:93-94`) makes Workers Logs a retained data store, so `console.error(err)` at `index.ts:234` is a retention decision. Log-field redaction and a Workers Logs retention setting belong to your track. `nearby.ts:84` logs a geo-derived cell key.

**T23 — Testing and CI.** Three checks I want in CI and cannot add from a documentation PR: a grep gate on `router.project-osrm.org`, a scanner asserting no deny-listed key appears in `audit_log.payload`, and the P2.4 migration check that any new personal-data column carries a retention entry.

**T24 — Performance and cost.** The retention engine in P0.5 is also a cost story: `trip_path_points` at ~960 rows per captain-day is the fastest-growing table in the schema, and D1 is billed on rows read and stored.

**T26 — Mobile release.** The store data-safety declarations must match §3.9, and both stores require the in-app account deletion that P0.2 builds. `LICENSE` containing `test-license` (`LICENSE:1`) may also surface in review.

**T27 — Cross-app parity.** The two apps have drifted on every privacy surface I touched, and in the wrong direction:

| Surface | Rider | Captain | Problem |
|---|---|---|---|
| Privacy policy row in settings | absent entirely | present but dead (`apps/captain/lib/screens/profile/settings_screen.dart:519`, `_InfoRow` with `value: ''`) | Two different wrong answers to the same requirement |
| Terms checkbox | `apps/rider/lib/screens/login_screen.dart:542`, field `_acceptedTerms` (line 90), string `loginTermsLabel` | `apps/captain/lib/screens/login_screen.dart:374`, field `_acceptTerms` (line 70), string `loginAcceptTermsLabel` | Near-identical logic, divergent field names and string keys — one shared widget should own this |
| Account deletion | absent | absent | Both need it (P0.2); build it once in `packages/flutter_shared` |
| Notification opt-out | absent | absent | Same |
| iOS always-on location | declared (`Info.plist:51`) with no foreground service | declared and genuinely used | The rider app over-declares; the captain app is the correct case |
| iOS `UIBackgroundModes` | `location`, `remote-notification` | `location`, `remote-notification`, `fetch` | Captain's `fetch` has no corresponding implementation found |
| Purpose strings | Arabic only | Arabic only | Both need English; the strings should live in one localisation source |

The captain app collects strictly more sensitive data — national ID, licence, birth date, four-part legal name — and yet its consent surface is no stronger than the rider's. Whatever consent and privacy components come out of P0.1 and P0.2 should be built once in `packages/flutter_shared` and consumed by both apps, which is the pattern your track is establishing anyway.

---

## 10. Open questions

Decisions the product owner must make. Each with options and my recommendation.

**Q1 — What is the current status of the PDPL executive regulations, and what is the Center's live licensing practice?**
Every deadline and permit obligation in §5.1 depends on this. Options: (a) engage Egyptian data-protection counsel now; (b) proceed on the statute alone and adjust later. **Recommendation: (a), immediately.** This is the gating input for P0.10 and it has the longest lead time of anything in this document. `needs-legal-review`.

**Q2 — Is the platform a data controller for captains, or a joint controller with them?**
This changes who owes the notice and who answers a data-subject request about trip data. It is entangled with driver classification (Q7). Options: (a) sole controller; (b) joint controller for trip data. **Recommendation: (a) sole controller** — it is the simpler and more defensible posture given the platform sets pricing, dispatch and the retention policy. Confirm with counsel.

**Q3 — Ratify the retention periods in §6.1.**
The 90-day location window and 12-month chat window are my proposals, calibrated to a plausible dispute and safety-investigation horizon. Options: (a) adopt as proposed; (b) shorten location to 30 days; (c) lengthen to 180 days for safety investigations. **Recommendation: (a) 90 days**, with the DPIA in P0.10 recording the reasoning. If T17 shows that safety investigations routinely reach back further, revisit before P0.5 ships rather than after.

**Q4 — Self-host routing and geocoding, or buy under contract?**
Options: (a) self-host OSRM and Nominatim on contracted infrastructure — strongest privacy position, highest ops burden; (b) commercial provider with a DPA — fastest, recurring cost, still a cross-border transfer needing a permit; (c) Egyptian or regional provider — best transfer position if one meets the quality bar. **Recommendation: (a) for routing** because it eliminates the transfer entirely and T24 will want the cost predictability; **(b) for geocoding** initially, since geocoding volume is cacheable and lower-risk once coordinates leave the query string. Coordinate with T21.

**Q5 — What may a shared trip link reveal?**
`GET /track/:token` currently returns both addresses (`safety.ts:119-120`) contrary to its own comment. Options: (a) status and live position only; (b) add a coarsened destination (district, not street); (c) keep full addresses. **Recommendation: (b).** It preserves the reassurance the feature exists for while removing the street-level disclosure to whoever the link is forwarded to. T17 should confirm.

**Q6 — Encrypt the national ID at rest, or stop storing the number at all?**
The number is captured at `captain.ts:574-587` and stored twice (`captains`, `driver_documents`). Options: (a) encrypt with a searchable HMAC (P1.2); (b) store only the last 4 plus the scan image, and read the full number from the image when a reviewer needs it; (c) status quo. **Recommendation: (a)**, unless verification workflows genuinely never need the number in text — in which case (b) is stronger, because the best protection for a field is not holding it. Ask the ops team which they actually use.

**Q7 — Driver classification and labour exposure.** `needs-legal-review`.
The platform sets pricing rules, dispatches work, suspends accounts and takes a commission. Whether Egyptian labour law treats captains as independent contractors on these facts is a question for counsel with direct consequences for social insurance, end-of-service entitlements and tax withholding. Engineering cannot answer it; it should be asked before the fleet scales, because the remedy is contractual and retroactive. **Recommendation: obtain a written opinion before commercial launch.**

**Q8 — VAT and e-invoicing with the Egyptian Tax Authority.** `needs-legal-review`.
`company_invoices` exists (`migrations/0003_global_transport.sql:144`) and a monthly cron generates B2B invoices (`wrangler.toml:61-65`), but nothing in the repository integrates with the ETA e-invoicing system, and I found no VAT treatment of the commission. Options: (a) scope ETA e-invoicing integration now; (b) launch B2C only and defer B2B until it is built. **Recommendation: (b)** — B2B invoicing without e-invoicing compliance creates a tax exposure that grows with every invoice issued. Hand the integration scope to T20.

**Q9 — Transport-sector licensing and insurance.** `needs-legal-review`.
Ride-hailing operation in Egypt is a licensed activity, and passenger-liability insurance obligations attach to the operator as well as the driver. Neither appears anywhere in the repository, which is expected — they are not code — but they are launch gates. **Recommendation: confirm the operating licence and the insurance policy are in place, and record where the evidence lives, before the first paid trip.**

**Q10 — Who is the DPO, and does the company meet the appointment threshold?**
Options: (a) appoint an internal DPO; (b) engage an external DPO service. **Recommendation: (b) initially** — an external service is cheaper than a hire at this stage and satisfies the appointment and registration requirement — moving in-house as the fleet grows. Either way the contact must be published in the privacy policy from day one, which makes this a dependency of P0.1, not just of P0.10.
