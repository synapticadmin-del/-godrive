# `apps/api/test` — the money paths that stay live

E19. Gate item 16. Scoped, deliberately, to the paths that are **live under the
launch shape** — not to coverage.

Under the launch shape the product is cash-only (E04 rejects `wallet` and `card`
at the edge) and both verticals are off. That leaves a small number of code paths
that can actually move money or strand a rider, and those are what is tested
here:

| File | What it holds down |
|---|---|
| `settlement-cash-commission.test.ts` | the cash commission debit, and its **balance floor** — the only live money path in the product |
| `completion-idempotency.test.ts` | a retried completion must not settle twice — the row guard *and* the `UNIQUE` index, separately |
| `accept-race.test.ts` | two captains, one trip: the compare-and-swap in `POST /trips/:id/accept` |
| `payment-method.test.ts` | E04's rejection, asserted so that widening the enum turns a test red first |

## Running

```bash
npm test -w @synaptic-go/api        # vitest run
```

Tests execute inside `workerd` via `@cloudflare/vitest-pool-workers`, against the
bindings `wrangler.toml` declares — real D1, KV, R2 and Durable Objects. The
migrations applied are the repository's own `migrations/*.sql`, read at config
time, not a fixture. Both choices matter: two of the four guarantees are
properties of the SQL (`meta.changes` on a guarded `UPDATE`, and `idx_wt_idem`
refusing a second insert) and a Node approximation of D1 would assert neither.

**No test reaches a third party.** `OSRM_URL` is set to an unroutable host in
`vitest.config.ts`, and the one test that exercises a *valid* trip body stops
deterministically at `NO_PRICING` before routing is called.

## `tools/` — dependency-free evidence

`tools/offline-verify.mjs` re-checks the same four guarantees using **only** the
Node standard library: `node:sqlite`, native type stripping, the repository's
real migrations, and the API's real source modules. Nothing is reimplemented and
nothing is installed.

```bash
cd apps/api/test/tools
node --import ./ts-loader.mjs offline-verify.mjs
node --import ./ts-loader.mjs offline-verify.mjs --revert=floor
```

It exists for two reasons:

1. **PROTOCOL-EXEC §7 asks a *different chat* to verify the effect against
   `main`.** This gives that chat something it can run immediately, without
   `npm ci`, without a registry, and without waiting for the CI job to be
   installed by hand.
2. **`--revert=<floor|completion|race|enum>`** puts one fix back to its pre-fix
   form so you can watch the matching assertion go red. A guarantee nobody has
   seen fail is not a guarantee. `--revert=floor` is the one to run first: it
   drives a captain's wallet to **−15 EGP**, which is the bug (F-03-11 /
   F-04-12) as it actually behaved.

Requires Node ≥ 22.6. Group D also needs `zod` (a runtime dependency of the API,
present after `npm ci`); without it that group reports `SKIP` rather than
failing. `tools/` is excluded from vitest's `include` glob and never runs in CI.

## Two gaps this task could not close

Both are files in **no task's `owns:`** for this wave, so E19 reported them
instead of reaching across the boundary (PROTOCOL-EXEC §4).

- **The suite is not typechecked.** `npm run typecheck -w @synaptic-go/api` runs
  `tsc --noEmit` against `apps/api/tsconfig.json`, whose `include` is
  `["src/**/*", "worker-configuration.d.ts"]`. `test/tsconfig.json` here serves
  editors; it does not change what that script covers. WAVE-PLAN §8 flagged this
  against E19 before round 5 and never assigned the file to it.
- **`vitest` is not declared by this package.** `apps/api/package.json` lists
  `@cloudflare/vitest-pool-workers` but not `vitest` itself, which resolves only
  by workspace hoisting from `packages/shared`. That file is E01's.

## Not here

`apps/rider/test/` and `apps/captain/test/` are out of scope for this wave and
that is deliberate — `ci.yml` runs `flutter analyze` and never `flutter test`, so
a Dart test added today would execute nowhere. See WAVE-PLAN §9.
