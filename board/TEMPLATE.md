# TEMPLATE — deliverable shape for every task

Copy this structure into `docs/plan/NN-slug.md`. Keep the headings and their
order; a reviewer reads 26 of these and the consistency is the point.

Language: Arabic or English, pick one and stay in it. Technical identifiers
(paths, table names, endpoints) always stay in English.

---

```markdown
# NN — <Title>

> Track: <group> · Reviewer: <CHAT_ID> · Date: <UTC date>
> Base commit reviewed: <sha of main you read>

## 1. Scope

What this document covers, and explicitly what it does not (which sibling
track owns that instead).

## 2. What I actually read

A list of every file inspected, with a one-line note on each. If you skimmed
rather than read, say so. This is the credibility anchor of the whole document.

## 3. How it works today

A factual walkthrough of the current implementation for this axis — the flow,
the data, the failure paths. No opinions yet. Include a sequence or a table
where it helps. Cite `path:line`.

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-NN-01 | S1 | … | `apps/api/src/…:120` | … | confirmed |

Severity scale:

- **S1 — blocker.** Money can be lost or stolen, auth can be bypassed, data can
  be corrupted or leaked, or the platform cannot go live with it.
- **S2 — major.** Users hit it regularly; it costs revenue, trust, or hours of
  ops time.
- **S3 — moderate.** Real but survivable; schedule it.
- **S4 — polish.** Craft, consistency, nice-to-have.

Then expand every S1 and S2 in prose underneath the table: what is wrong, why
it happens, what breaks in production.

## 5. Benchmark gap

How Uber / inDrive / Careem handle this axis, and precisely where Synaptic Go
sits against them. Be specific about mechanisms, not vibes. Only claim
competitor behaviour you are confident about; mark the rest as assumed.

## 6. Improvement plan

Ordered. Each item:

### P<n>.<m> — <name>
- **Goal** — the user-visible or business outcome.
- **Design** — how it works, concretely.
- **Files to change** — real paths.
- **DB** — new migration number and DDL sketch, or "none".
- **API contract** — new/changed endpoints with request + response shapes, or "none".
- **Effort** — S (< 1 day) / M (1–3 days) / L (> 3 days).
- **Risk** — what could break, and the rollback.
- **Acceptance criteria** — checkable statements.
- **Tests** — what proves it.

## 7. Phasing

- **P0 — before any production traffic.** The S1 set.
- **P1 — first 30 days.**
- **P2 — next 90 days.**

A table of item → phase → effort → owner-type (backend / Flutter / admin / ops).

## 8. Metrics

What to instrument so we can prove the change worked. Name the metric, the
current value if known, and the target.

## 9. Cross-cutting notes

Things you found that belong to another track. Name the track (`T14`, `T22`…)
so the owner can pick it up. Do not fix it here.

## 10. Open questions

Decisions the product owner has to make. Each with the options and your
recommendation.
```
