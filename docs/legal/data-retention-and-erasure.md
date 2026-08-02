# Data retention and erasure — operating procedure

Companion to the privacy policy. The policy states the retention periods; this file
states how they are met and who has to do what.

## 1. Retention schedule

| Data | Table / store | Period | Enforced by |
|---|---|---|---|
| Account and profile | `users` | until deletion | `DELETE /user/account` |
| Captain identity and documents | `captains`, `driver_documents`, R2 `docs/` | until deletion | `DELETE /user/account` |
| Saved places | `saved_places` | until deletion | `DELETE /user/account` |
| Payment methods | `payment_methods` | until deletion | `DELETE /user/account` |
| Push tokens | `device_tokens` | until deletion | `DELETE /user/account` |
| Financial ledger | `wallet_transactions`, `user_credits` | 10 years | **not yet automated** |
| Trips | `trips` | 10 years | **not yet automated** |
| Safety reports, chat | `sos_alerts`, `trip_chat_messages` | 3 years | **not yet automated** |
| Consent records | `user_consents` | 10 years | append-only by trigger |
| Detailed trip path | `trip_path_points` | 90 days *(intended)* | **not implemented — F-25-07** |
| Deletion requests | `account_deletion_requests` | 3 years | **not yet automated** |

**Rows marked "not yet automated" are honest, not aspirational.** No sweeper exists
for them. A retention sweep needs a cron job, and cron modules live in
`apps/api/src/cron/` (E02) driven by triggers in `apps/api/wrangler.toml` (E15) —
neither of which E16 owns. `trip_path_points` growing without bound is finding
F-25-07 and is scoped to Wave 2.

## 2. Handling a data-subject request

**Access / export.** The subject self-serves: in-app, or `GET /user/export`. No
operator action. Each export writes a `user.data_exported` row to `audit_log`.

**Correction.** Self-serve via `PATCH /user/profile`. Fields the subject cannot edit
themselves (captain identity fields, which are verified against a document) go
through support with the document re-checked.

**Erasure.** Self-serve in-app. For a request arriving through the public page or
support:

1. Read the pending row: `SELECT * FROM account_deletion_requests WHERE status='pending' ORDER BY requested_at;`
2. **Verify the requester controls the address.** The public form is
   unauthenticated and deliberately non-committal; acting on it without verification
   is an erasure oracle. Confirm by replying to the registered address.
3. Have the subject complete the deletion in-app, which runs the same code path.
4. If they cannot (lost device, no app), an operator runs the erasure and then closes
   the row: `UPDATE account_deletion_requests SET status='completed', completed_at=… WHERE id=…;`
   The in-app path closes matching pending rows automatically.
5. Rejections get `status='rejected'` and a `note` saying why. Never delete the
   request row — it is the record that the request was handled.

**Consent withdrawal.** `POST /user/consent` with `action: "withdrawn"`. Never an
UPDATE: the table's `user_consents_no_update` and `user_consents_no_delete` triggers
reject one with `RAISE(ABORT)`.

## 3. What survives an erasure, and why

Financial ledger rows (tax and accounting obligation), consent records (the evidence
that processing was lawful), and safety reports and trips shared with a second party.
All are detached from identity — they point at a `users` row whose identifiers are
gone — and the API response for a deletion names them back to the caller.

## 4. R2 orphan reconciliation — run once

**The defect.** Before this task, `FILES.delete` was called from exactly two places,
both in the avatar paths of `user.ts` (`:186` and `:235` on `main` at `149271d`).
`captain.ts:665` writes identity documents to `docs/<userId>/…` and nothing ever
deleted them. Superseding a document deletes its row and leaves the object; there was
no deletion path at all. That is F-25-04 and F-25-05.

`DELETE /user/account` now deletes both the avatar and every `docs/<id>/` object it
can name. **Objects orphaned before this shipped are still in the bucket** and have to
be collected once, by hand.

### Procedure

Objects are orphaned when no `driver_documents` row names them. Reconcile by
differencing the bucket listing against the column:

```sh
# 1. Every key the database still vouches for.
npx wrangler d1 execute synaptic-go --env prod --remote --json \
  --command "SELECT r2_key FROM driver_documents WHERE r2_key IS NOT NULL" \
  | jq -r '.[0].results[].r2_key' | sort -u > /tmp/referenced.txt

# 2. Every document object actually in the bucket.
npx wrangler r2 object list synaptic-go-files --prefix "docs/" \
  | jq -r '.objects[].key' | sort -u > /tmp/present.txt

# 3. Present but unreferenced.
comm -13 /tmp/referenced.txt /tmp/present.txt > /tmp/orphans.txt
wc -l /tmp/orphans.txt
```

**Read `/tmp/orphans.txt` before deleting anything.** Sanity checks first:

- Cross-check a sample of orphan prefixes against `users.deleted_at` — an orphan
  under a live captain's id means an upload path lost its row and is a bug to file,
  not a file to delete.
- Confirm the count is plausible against `SELECT COUNT(*) FROM driver_documents`.

Then, and only then:

```sh
while read -r key; do
  npx wrangler r2 object delete "synaptic-go-files/$key"
done < /tmp/orphans.txt
```

**This is irreversible and R2 has no undelete.** Take the E18 backup rehearsal first;
identity documents that a captain has to re-upload are a support incident, and ones
deleted while still required for an audit are worse. Record the date, the operator and
the object count in this file when it is done.

| Run date | Operator | Objects deleted | Notes |
|---|---|---|---|
| *(not yet run)* | | | |

### Why this is a runbook and not a script

A reconciliation script would live in `scripts/`, and in this execution wave
`scripts/` contains exactly one owned path (`scripts/backup-d1.sh`, E18). Per
WAVE-PLAN §8 an unowned path must not be edited, so E16 does not create one. If a
recurring sweep is wanted rather than a one-off, it needs an owner and a cron trigger
— see §1.
