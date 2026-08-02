# docs/legal

Canonical source for the product's legal surface. Written for launch-gate item 12
(E16) against the code as it exists on `main` at `149271d`, not against how the
product is described elsewhere.

| File | What it is | Who owns the next edit |
|---|---|---|
| `privacy-policy.ar.md` | The policy. Arabic is the authoritative text — the product ships Arabic-first. | counsel |
| `privacy-policy.en.md` | English translation of the same version. | counsel |
| `account-deletion.md` | How erasure works, what survives it, and the two routes into it. | engineering |
| `data-retention-and-erasure.md` | Retention schedule, the erasure procedure, and the R2 orphan reconciliation. | engineering |

## Version

The current policy version is **`2026-08-01`**. It appears in three places and they
must not drift:

- the `version:` front-matter of both policy files
- `PRIVACY_POLICY_VERSION` in `apps/api/src/routes/user.ts`
- the `version` recorded on every `user_consents` row

Consent is recorded *against a version*. Bumping the text without bumping the
version silently converts "agreed to v1" into "agreed to v2", which is the whole
failure this table exists to prevent.

## What a human still has to do

None of these can be done by an agent, and the gate item is not closed until they are.

1. **Counsel review.** This text was written by reading the code, not by a lawyer.
   It is an accurate description of processing; it is not yet legal advice, and the
   PDPL (Law 151/2018) controller/representative details in §9 are placeholders.
2. **Fill in the controller identity.** Legal entity name, registered address, and a
   working `privacy@` address, in both policy files. They are marked `TODO(legal)`.
3. **Store listings.** Both stores need two URLs:
   - Privacy policy URL
   - Account deletion URL → `https://<api-host>/user/deletion-request`
   The deletion URL is live as soon as E02 mounts `publicUserRoutes` (see
   `account-deletion.md`). Until a marketing domain exists, the policy URL can point
   at the rendered copy of `privacy-policy.ar.md` in this repository; that is a
   stopgap and counsel should replace it with a hosted page on the product domain.
4. **Run the R2 reconciliation once**, per `data-retention-and-erasure.md` §4. It
   collects the identity documents that were orphaned before this task landed.

## Known gaps, deliberately not fixed here

- **Trip coordinates go to a public routing demo server.** `OSRM_URL` is
  `https://router.project-osrm.org` in the default, `prod` and `staging` var blocks
  of `apps/api/wrangler.toml` (lines 88, 148, 176 on `main`) — a public demo
  endpoint with no contract and no data-processing agreement. That is finding
  F-25-08 and belongs to **E15** (gate item 11), which owns `wrangler.toml`. The
  policy describes recipients by category so it stays true either way, but counsel
  should re-read §6 once E15 lands.
- **`trip_path_points` is retained indefinitely** (F-25-07, G2). The retention
  schedule states the intended period; no sweeper implements it yet, and the cron
  that would is `E02`/`E09` territory.
- **Staff access to identity documents is unaudited** (F-25-06, G2) — `admin.ts` is
  E14's file.
