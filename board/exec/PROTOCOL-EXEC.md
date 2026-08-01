# PROTOCOL-EXEC — implementation phase
# بروتوكول مرحلة التنفيذ

> The review phase protocol (`board/PROTOCOL.md`) does **not** apply here and must not be reused.
> It was built for read-only, independent, parallel work. Implementation writes to shared files,
> and two chats editing `trips.ts` at the same time will silently destroy each other's work.
> Read this file instead, and follow it literally.

---

## 0. Constants

| Key | Value |
|---|---|
| `OWNER` | `synapticadmin-del` |
| `REPO` | `-godrive` (the leading dash is part of the name) |
| `BOARD_BRANCH` | `review-board` |
| `BASE_BRANCH` | `main` |
| Plan | `docs/plan/00-EXECUTION-PLAN.md` — **not on `main`.** PR #87 is still open, as are the 28 review PRs. Read it from branch `plan/29-execution-plan`. |
| Task briefs | `board/exec/tasks/E01.md` … `E19.md` |
| Claims | `board/exec/claims/ENN.md` |
| Wave plan & file ownership | `board/exec/WAVE-PLAN.md` |
| Migration lock | `board/exec/MIGRATION-LOCK.md` |

Action names, short form only (`GITHUB_*` does not exist on this connection):

```
github__get_file_contents   github__create_or_update_file
github__push_files          github__create_branch
github__create_pull_request github__list_commits
```

---

## 1. What is different from the review phase

Four changes. Each exists because of something that actually happened.

1. **A claim locks files, not just a task.** Every task declares `owns:` — an explicit list of paths.
   You may not claim a task whose `owns:` intersects any in-progress claim's `owns:`. This is the
   whole reason parallel execution is safe; §3 is not optional.
2. **`depends_on` must be *merged*, not merely `done`.** Verify on `main` before you start. A
   dependency that is `done` but unmerged does not exist as far as your branch is concerned.
3. **You never merge your own work, and you never close your own finding.** A different chat verifies
   the *effect* against `main` after the merge. See §7.
4. **Migrations serialise globally.** One counter, one lock file. See §6.

---

## 2. Generate your CHAT_ID

```
CHAT_ID = chat-<UTC yyyymmdd-HHMM>-<4 random hex>
```

It goes in the claim, the commit messages and the PR body. The branch is not named after it.

---

## 3. Claim a task — before you read a line of code

### 3.1 Read the whole claims folder, not just the one you want

```
github__get_file_contents { owner, repo, path: "board/exec/claims", ref: "refs/heads/review-board" }
```

Download every claim that is `status: in_progress` and collect the union of their `owns:` lists.
Call that set `LOCKED`.

### 3.2 Pick a candidate

The lowest-numbered task where **all** of these hold:

- no claim file exists for it, or its claim is `status: abandoned`
- every id in its `depends_on` has a claim with `status: done` **and** you have confirmed that PR is
  merged into `main`
- **its `owns:` does not intersect `LOCKED`**

If nothing qualifies, stop and report `no unblocked task — N tasks in progress, waiting on <ids>`.
Do not invent a task, and do not take one whose dependency is unmerged.

### 3.3 Take the lock

`github__create_or_update_file` on `board/exec/claims/ENN.md` with **no `sha`**. The rejection when
the path already exists is the lock. For an `abandoned` file, update it *with* its `sha` and add
`takeover_of:`.

Claim file shape:

```markdown
---
task: E09
title: Trip lifecycle — expiry sweeper, active-trip recovery, scheduled dispatch
status: in_progress
claimed_by: chat-20260801-1812-4b7a
claimed_at_utc: 2026-08-01T18:12:04Z
branch: exec/09-trip-lifecycle
pr:
owns:
  - apps/api/src/routes/trips.ts
  - apps/api/src/lib/dispatch.ts
  - apps/api/src/cron/dispatch.ts
  - apps/api/src/lib/cleanup.ts
migration: no
finished_at_utc:
---

## Progress
- claimed
```

Copy `owns:` from the task brief **verbatim**. Shortening it breaks the lock for everyone else.

### 3.4 Verify by read-back — mandatory

Re-read the claim and confirm `claimed_by` is your `CHAT_ID`. Error strings vary; the file does not.

### 3.5 Re-check before you push

Between claiming and pushing, another chat may have claimed something adjacent. Re-read the claims
folder before you open your PR. If someone has taken a file you own, do not merge over them — say so
on both PRs and let a human decide.

### 3.6 Staleness

`in_progress` untouched for **90 minutes** is abandonable. Write a heartbeat line into your claim's
`## Progress` when you pass a milestone, so a slow task is not mistaken for a dead one.

---

## 4. Do the work

- **One task is one change.** If your task needs a file you do not own, you have found a missing
  seam. Say so on the PR. Do not reach across the boundary.
- **Pure refactors ship alone.** E02 and E03 are structural passes with no behaviour change; that is
  what makes the rest parallelisable. Do not smuggle a fix into one.
- **Tests are named in the brief and are not optional.** A task whose test is "manual check" is not
  ready to be worked.
- **Cite before you change.** Every `path:line` in the plan came from a track document written
  against that track's own snapshot. Nine claims are marked `[verified]` against `b0c0866`;
  everything else you must open and confirm before you rely on it. Line numbers drift.
- **Never ask the user anything.** Decide, write the assumption into the PR, keep going.
- **Subagents are for analysis, not for plumbing.** Do not spawn an agent whose whole job is to
  download files.

### 4.1 Consequence files — the ones that change *because* you changed something

Your `owns` list names the files you set out to edit. It does not name the files that move as a
**side effect**. Every collision found on this board after the first audit was one of these, because
a brief describes intent and a lockfile is a consequence. Check this table before you write anything:

| If your change… | …it also rewrites | Owned by |
|---|---|---|
| adds or bumps an npm dependency | `package-lock.json` — one root lockfile, npm workspaces | `E01` |
| adds an npm script another task will call | `apps/api/package.json` | `E01` |
| adds a Flutter package | that app's `pubspec.yaml` **and** `pubspec.lock` | captain → `E11` · rider → **nobody** |
| adds a user-facing string through the shared catalogue | `packages/flutter_shared/lib/l10n/app_strings.dart` — the abstract class **and** `AppStringsAr` **and** `AppStringsEn`, all three | `E16` |
| adds a D1 migration | the number comes from `MIGRATION-LOCK.md`, never from a directory listing | see §6 |

**Reading an existing `AppStrings` getter is free. Adding one is not** — it is a three-place edit in a
5,664-line file that two chats cannot make at once.

`ci.yml` is what will catch you, and it fails the whole job:

- **`npm ci`** — fails outright when `package-lock.json` has drifted from any manifest. It is `npm ci`
  deliberately, not `npm install`, precisely so drift cannot be papered over.
- **`check_l10n_parity.py`** — a getter present in `AppStringsAr` but not `AppStringsEn` (or absent from
  the abstract class) fails. So does a duplicate getter, which is a hard Dart compile error.
- **`check_migrations.py`** — filenames must be `NNNN_lower_snake_case.sql`, ordered, no UTF-8 BOM.
- **`check_migrations_apply.py`** — every migration must apply in order to a fresh SQLite database.
- **`check_repo_hygiene.py`** — no conflict markers, no `.orig`/`.rej` artefacts, no BOM.

**The rule.** If your work requires a consequence file you do not own: **stop, and say so on the PR.**
Do not edit it, and do not work around it by duplicating the thing elsewhere. A task that quietly
reaches outside its `owns` is the exact failure this board exists to prevent — and a task that fakes
its way around a missing seam is root R3, work declared done at the point of definition rather than
effect. Naming the gap is a correct outcome. Silently widening your blast radius is not.

## 5. Ship it

1. `github__create_branch` from `main`, named `exec/NN-slug`.
2. Push with `github__push_files`. Large payloads: write the params to a JSON file on disk and pass
   `paramsFile` — inline params get truncated mid-string with no error.
3. Open a PR into `main`. The body states: the task id, the findings it closes, what you changed,
   the tests you added, **and what you deliberately did not touch**.
4. Update your claim: `status: done`, the PR link, `finished_at_utc`, and five lines of what you
   actually did.
5. Add your block to `PROJECT.md` on `main` — append before `<!-- TRACK-ENTRIES:END -->`, byte for
   byte, re-reading on conflict. This is still the only write to `main` you may make.

## 6. Migrations

Three tasks need one (E06, E13, E16) and more will follow. The next free number is **0020**.

Claim it by editing `board/exec/MIGRATION-LOCK.md` **with** its `sha`, appending your row. If you get
a `409`, someone took your number — re-read, take the next one, and rename your file. Never guess a
number from the repository listing; two chats will pick the same one.

Migrations are forward-only. Your PR states the rollback (a forward repair migration, or a restore)
and confirms it against the rehearsed restore from E18. Four existing backfills are irreversible;
do not add a fifth without saying so.

## 7. Verification — the part that is not optional

**This programme exists because a previous fix round declared success without verification.** PR #46
was titled *"ci: deploy the API from main instead of from someone's laptop"*, merged, and did not do
that — the workflow went to `docs/` and has never run. `docs/DEPLOYMENT.md` records PR #45 sitting
merged while all three of its fixes were still reported broken. The same shape appears eighteen more
times in the code as root R3 of the plan: a value defined, and nothing ever calling it.

So:

- The author moves the finding to `awaiting-verification` and **stops**. The author never closes it.
- A **different chat** verifies against `main` *after* the merge. It reads the code as it now exists,
  re-runs the reproduction from the original finding, and posts the result on the PR and as a line in
  `PROJECT.md`.
- **The verifier does not read the author's summary before forming a view.**
- **Verification names the effect, not the artefact.** "Workflow added" is not verification; "workflow
  ran, here is the run URL" is. "Token defined" is not verification; "token renders, here is the
  screenshot" is. "Endpoint written" is not verification; "endpoint returns 403 for the case that used
  to return 200" is.

To verify a task, claim `board/exec/claims/VNN.md` the same way, with `owns: []`.

## 8. Never

- push to `main` (sole exception: your own `PROJECT.md` block)
- merge or close any PR, including your own
- edit a file outside your `owns:` list
- edit another chat's claim, task brief, or `PROJECT.md` block
- touch `.github/workflows/**` — the GitHub App has no `workflows` permission; the push will fail.
  Put proposed YAML at `docs/plan/assets/` and name the human step in your PR.
- edit `apps/api/src/index.ts` after E02 has merged — it is frozen; see the note in E02
- re-enable anything the launch shape disabled (§2.1 of the plan). Those are G1‡: disabled, not fixed.
- ask the user a question before or during the run

## 9. If your run stops early

Set your claim to `status: abandoned` with one line saying how far you got and what is actually on the
branch. An unreleased claim looks like a crash and blocks the file lock for 90 minutes.
