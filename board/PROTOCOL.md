# PROTOCOL — Distributed Review of Synaptic Go
# بروتوكول المراجعة الموزّعة على شاتات متوازية

> اقرأ الملف ده أول حاجة ونفّذه حرفيًا. أي خطوة تتخطاها هتخلي شات تاني يكرر شغلك.
> READ THIS FIRST. FOLLOW IT LITERALLY. Multiple chats run at the same time.

---

## 0. Constants

| Key | Value |
|---|---|
| `OWNER` | `synapticadmin-del` |
| `REPO` | `-godrive` (note the leading dash — it is part of the name) |
| `BOARD_BRANCH` | `review-board` |
| `BASE_BRANCH` | `main` |
| Board root | `board/` |
| Task briefs | `board/tasks/T01.md` … `board/tasks/T26.md` |
| Claims | `board/claims/T01.md` … `board/claims/T26.md` |
| Index | `board/REVIEW_PLAN.md` |
| Deliverable template | `board/TEMPLATE.md` |

**GitHub MCP action names — use these exact strings via `ExecuteIntegration`.**
Do **not** use the long `GITHUB_*` form; it does not exist on this connection.

```
github__get_file_contents      github__create_or_update_file
github__push_files             github__create_branch
github__create_pull_request    github__list_pull_requests
github__search_code            github__list_branches
```

---

## 1. Generate your CHAT_ID (first action of the run)

```
CHAT_ID = chat-<UTC yyyymmdd-HHMM>-<4 random hex chars>
example: chat-20260801-1412-9c3f
```

It is your identity for the whole run. It goes in the claim file, the commit
messages, the branch is *not* named after it, and the PR body mentions it.

---

## 2. CLAIM A TASK — before you read a single line of product code

Other chats are starting seconds apart. Claiming is a **lock**, and the lock is
"create a file that does not exist yet". GitHub's Contents API rejects a create
without a `sha` when the path already exists — that rejection *is* the lock.

### 2.1 List what is already claimed

```
github__get_file_contents {
  owner: OWNER, repo: REPO,
  path: "board/claims",
  ref: "refs/heads/review-board",
  fields: ["name"]
}
```

A 404 here means nothing is claimed yet. `.gitkeep` is not a claim.

### 2.2 Read the index

`board/REVIEW_PLAN.md` from `review-board`. It lists T01…T26 with titles,
branch names and deliverable paths.

### 2.3 Pick a candidate

The **lowest-numbered** task that has no `board/claims/TNN.md`.

### 2.4 Take the lock

```
github__create_or_update_file {
  owner: OWNER, repo: REPO,
  branch: "review-board",
  path: "board/claims/TNN.md",
  message: "claim(TNN): <CHAT_ID>",
  content: <the claim block from section 3>
  // NO sha field. Omitting it is what makes this atomic.
}
```

### 2.5 Read the outcome

| Result | Meaning | Do |
|---|---|---|
| success | you may own it | go to 2.6 — still verify |
| error mentions `sha`, `already exists`, or `422` | another chat got there first | back to 2.1, next candidate |
| error `409` / `expected <sha> but was <sha>` | the branch ref moved under you | sleep 3–10 s (random), back to 2.1 |
| any other error | transient | retry once, then back to 2.1 |

### 2.6 Verify by read-back — MANDATORY

Re-read `board/claims/TNN.md` from `review-board` and confirm `claimed_by`
equals **your** `CHAT_ID`. Error strings vary; the file content does not.
If it names someone else, you lost the race — back to 2.1.

### 2.7 Budget

Up to 10 attempts. If every task is claimed and none is stale (2.8), stop and
report `all tasks claimed — nothing to do`. Do not invent a task.

### 2.8 Stale takeover

A claim with `status: in_progress` and `claimed_at_utc` older than **90
minutes** is abandoned. You may take it: update the file **with** its `sha`,
set `claimed_by` to your `CHAT_ID`, add `takeover_of: <previous id>`, then
verify by read-back as in 2.6.

---

## 3. Claim file format

Write exactly this shape (YAML front-matter + free notes):

```markdown
---
task: T07
title: Realtime — Durable Objects & WebSockets
status: in_progress
claimed_by: chat-20260801-1412-9c3f
claimed_at_utc: 2026-08-01T14:12:07Z
branch: plan/07-realtime-durable-objects-ws
doc: docs/plan/07-realtime-durable-objects-ws.md
pr:
finished_at_utc:
---

## Progress
- claimed
```

`status` is one of `in_progress` | `done` | `abandoned`.

---

## 4. Do the work

Read `board/tasks/TNN.md` — that is your brief. Then:

- **Evidence only.** Every finding cites a real `path:line` you actually read.
  No invented endpoints, no invented table columns, no guessed behaviour.
- **Read at least the files listed in the brief**, then widen with
  `github__search_code` as the questions demand.
- **Mark confidence** on each finding: `confirmed` (you read the code) /
  `likely` (strong inference) / `needs-check` (could not verify).
- **Subagents are allowed and encouraged** for parallel file reading. You stay
  the owner of the deliverable.
- **Never ask the user anything.** Decide, document the assumption, keep going.
- Large tool results get written to disk — read them with shell tools rather
  than pulling them wholesale into context.

---

## 5. Ship the deliverable

### 5.1 Branch off main

```
github__create_branch { owner, repo, branch: "<brief's branch>", from_branch: "main" }
```

### 5.2 Write the document

Path is fixed by the brief: `docs/plan/NN-slug.md`. Follow `board/TEMPLATE.md`
section for section. Push with `github__push_files` (one commit, all files).

> The document will be tens of KB. Stage the params as JSON on disk and pass
> `paramsFile` to `ExecuteIntegration` instead of inline `params`. Inline
> payloads that large get silently truncated mid-string.

### 5.3 Open the PR

```
github__create_pull_request {
  owner, repo,
  title: "docs(plan): NN — <Title>",
  head: "<your branch>", base: "main",
  body: <10–20 line summary: top findings by severity, P0 list, CHAT_ID>
}
```

### 5.4 Never

- push to `main`
- merge or close any PR (yours or anyone's)
- touch `.github/workflows/**` — the GitHub App has no `workflows` permission
  and the push will fail. Put proposed CI YAML inside your document as a fenced
  block, or at `docs/plan/assets/NN-<name>.yml.txt`.
- edit product source code. **This phase is review + plan only.** Your PR
  contains documentation. Implementation is a later phase.

---

## 6. Release the claim

Update `board/claims/TNN.md` on `review-board` — **with** the `sha` this time:

- `status: done`
- `pr: <url>`
- `finished_at_utc: <UTC>`
- a 5-line summary under `## Progress`

On `409`, re-read the file for its fresh `sha` and retry. Do not skip this
step: an unreleased claim looks like a crashed chat and someone will redo it.

---

## 7. Report back to the user

Two lines. Task id + PR URL. Optionally one line for the single most alarming
finding. Do **not** paste the document into chat — it is in the PR.

---

## 8. Hard rules

1. One task per chat. When the claim is released, stop.
2. Read-only on `board/REVIEW_PLAN.md`, `board/PROTOCOL.md`, `board/TEMPLATE.md`,
   `board/tasks/**`, and every claim file that is not yours.
3. Findings outside your axis go under `## Cross-cutting notes` in *your*
   document. Never edit another track's file.
4. Your document must be useful to an engineer who has not read the codebase:
   concrete, ordered, and costed.
