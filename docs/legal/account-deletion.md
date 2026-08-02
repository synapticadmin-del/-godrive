# Account deletion

Two routes into erasure, one implementation behind them. Written against
`apps/api/src/routes/user.ts` as this task leaves it.

## 1. The two routes

### In-app (authenticated)

`DELETE /user/account`

Rider app: **الإعدادات ← الخصوصية والبيانات ← حذف الحساب**
Captain app: same path under its own settings screen.

Both apps confirm in a dialog that names what is deleted and what is kept, and
require the word **حذف** to be typed before the destructive button enables. Deleting
an account is not an action that should be one mis-tap away.

### Public (unauthenticated)

`GET  /user/deletion-request` — a visitable page
`POST /user/deletion-request` — the form target, and a JSON endpoint

This is the URL that goes in both store listings. Google Play requires a deletion
route reachable **without installing the app**, and a reviewer has to be able to open
it in a browser — which is why the `GET` exists alongside the `POST` that E02's brief
names.

**The public route does not delete anything.** It is unauthenticated, so acting on it
directly would let anyone erase any account by typing an email address. It records a
row in `account_deletion_requests` for an operator to action, and it answers
identically whether or not the address matches an account — an endpoint that says
"no such user" is an account-enumeration oracle on the public internet. It is rate
limited to 5 requests per hour per IP.

> **Mount dependency.** Both live at `/user/...`, and `userRoutes` applies
> `authMiddleware` to `*`. The public app therefore has to be matched **first**:
>
> ```ts
> app.route("/user", publicUserRoutes);  // E16 — must come BEFORE the line below
> app.route("/user", userRoutes);
> ```
>
> `publicUserRoutes` is exported from `apps/api/src/routes/user.ts`. E02 owns
> `index.ts` and adds the mount; until that merges, the handler exists and is
> unrouted, which is inert. **If the mount is missing, the store listing URL 401s and
> the app is rejected.**

## 2. What deletion actually does

Soft delete with identifier tombstoning. The `users` row survives; every identifier
on it does not.

The row survives because `wallet_transactions`, `user_credits`, `trips.rider_id` and
`ratings.from_user_id` all reference `users(id)` and several are `NOT NULL`. Removing
the row would either fail on the constraint or cascade the ledger away — and the
ledger has to keep balancing after an erasure.

**Nulled or tombstoned on `users`:** `name`, `phone`, `avatar_url`, `password_hash`.
`email` becomes `deleted+<id>@deleted.invalid` rather than `NULL`, because the column
is `NOT NULL UNIQUE` (`0001_init.sql:5`). That tombstone is also what makes the
erasure hold at the login path: `routes/auth.ts:392` finds users by email, so the old
address matches nothing — and stays free for a fresh sign-up.

**Nulled on `captains`:** the four-part legal name, birth date, national ID number,
licence number and expiry, vehicle plate, and last known position. Approval state and
rating counters stay; they are not identifiers and the trips referencing them still
have to make sense.

**Rows deleted outright:** `saved_places` (home and work pins), `payment_methods`
(stored card tokens), `device_tokens` (push targets), `driver_documents` (identity
scans).

**R2 objects deleted:** the avatar under `avatars/<id>/`, and every document under
`docs/<id>/` named by a `driver_documents.r2_key`. Keys are read *before* the rows
that name them are deleted — reading them after is how the orphans in
`data-retention-and-erasure.md` §4 were created.

**Sessions ended:** every `refresh_tokens` row for the user gets `revoked_at` set.
`routes/auth.ts:285` refuses a refresh whose row is revoked, so the session cannot be
extended past the current access token.

**Retained, attached to the tombstone:** `wallet_transactions`, `user_credits`,
`trips`, `ratings`, `referrals`, `sos_alerts`, `trip_chat_messages`, `user_consents`.
The response body names these back to the caller so the app can tell the user the
truth rather than "all your data has been erased", which would be false.

## 3. When deletion is refused

| Condition | Status | Code |
|---|---|---|
| A trip is `searching`, `offered`, `assigned`, `arrived` or `in_progress` | 409 | `ACTIVE_TRIP` |
| `users.wallet_balance > 0` | 409 | `BALANCE_OUTSTANDING` |

Both are refusals, not silent partial deletions. Erasing a party mid-trip strands the
other one; erasing an account in credit destroys the user's claim to their own money.

## 4. Residual window

The access token is a stateless JWT and `middleware/auth.ts` never reads the
database, so a token minted seconds before deletion remains *cryptographically* valid
until it expires. A guard on `userRoutes` rejects it with `401 ACCOUNT_DELETED` by
checking `deleted_at` on every `/user/*` request except `GET /user/avatar/*`.

That guard covers this file's routes. Routes owned by other tasks — `/trips`,
`/captain`, `/wallet` — do **not** yet carry it, and a global equivalent belongs in
`middleware/auth.ts`, which no task in this wave owns. Refresh revocation bounds the
exposure to one access-token lifetime. This is stated rather than hidden: see the
seam note on the E16 PR.
