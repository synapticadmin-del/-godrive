#!/usr/bin/env bash
#
# deploy.sh — publish the Tempo Worker to an explicitly named environment.
#
# ---------------------------------------------------------------------------
# Why this script was rewritten (task E01, launch-gate item 2)
# ---------------------------------------------------------------------------
# The previous version had two production-breaking defects, filed independently
# by two review tracks (T22 F-22-11 and T23 F-23-17):
#
#   1. It ran `wrangler deploy` with no `--env`. The top-level block of
#      apps/api/wrangler.toml shares the worker name "synaptic-go-api" AND the
#      production D1 database id with [env.prod], so a bare deploy publishes the
#      local-dev [vars] straight over production. wrangler.toml warns about this
#      in its own comment: when DEV_OTP is "true" the API returns the OTP code in
#      the response body, which lets anyone sign in as anyone.
#
#   2. It applied exactly ONE migration, hardcoded, out of the 19 in migrations/
#      — and applied it with `wrangler d1 execute --file=`, which writes nothing
#      to the d1_migrations bookkeeping table. The migration it applied was
#      invisible to the migration system, and the other eighteen were skipped.
#
# The fix has one shape in both cases: never infer the target, never infer the
# migration set. The environment is a required argument, and migrations go
# through `wrangler d1 migrations apply`, which applies every pending migration
# and records each one.
#
# Usage:
#   ./deploy.sh <env>                 # <env> is REQUIRED: prod | staging
#   ./deploy.sh prod
#   ./deploy.sh staging --dry-run     # print the commands, execute nothing
#   ./deploy.sh --self-test           # assert the guard holds (npm run test:deploy)
#
# Auth comes from CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID in the
# environment, or from `wrangler login` state.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
API_DIR="$SCRIPT_DIR"
WRANGLER_TOML="$API_DIR/wrangler.toml"

die() { printf 'deploy.sh: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

usage() {
  cat >&2 <<'USAGE'
usage: ./deploy.sh <env> [--dry-run]
       ./deploy.sh --self-test

  <env>        REQUIRED. The wrangler environment to publish to, e.g. prod.
               There is deliberately no default: apps/api/wrangler.toml's
               top-level block shares its worker name and production D1
               binding with [env.prod], so a deploy with no environment
               overwrites production with local-dev values.

  --dry-run    Print every command that would run, execute none of them.
  --self-test  Verify the no-environment guard. Used by `npm run test:deploy`.
USAGE
}

# --- environment discovery -------------------------------------------------
# Valid environments are read out of wrangler.toml rather than hardcoded here,
# so this script cannot drift from the config it deploys. The pattern matches
# only top-level [env.<name>] tables — [env.prod.vars] and friends contain a
# dot and are correctly ignored.
list_envs() {
  sed -n 's/^\[env\.\([A-Za-z0-9_-]*\)\]$/\1/p' "$WRANGLER_TOML" | sort -u
}

# database_name from the [[env.<env>.d1_databases]] block. Never guessed: if it
# cannot be read the script stops rather than migrating an assumed database.
db_name_for_env() {
  awk -v e="$1" '
    $0 ~ "^\\[\\[env\\." e "\\.d1_databases\\]\\]$" { inblock = 1; next }
    /^\[/ { inblock = 0 }
    inblock && /^[[:space:]]*database_name[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*database_name[[:space:]]*=[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  ' "$WRANGLER_TOML"
}

# --- argument parsing ------------------------------------------------------
MODE="deploy"
ENVIRONMENT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test) MODE="self-test"; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    --env)
      # A common muscle-memory mistake; be explicit rather than silently wrong.
      die "pass the environment positionally: ./deploy.sh ${2:-<env>}"
      ;;
    -*) die "unknown option: $1" ;;
    *)
      if [[ -n "$ENVIRONMENT" ]]; then
        die "unexpected extra argument: $1"
      fi
      ENVIRONMENT="$1"
      shift
      ;;
  esac
done

# --- self-test -------------------------------------------------------------
# Executable form of the E01 acceptance criteria. Runs without wrangler, without
# credentials and without network: every deploy path is exercised through
# --dry-run. `npm run test:deploy` calls this.
run_self_test() {
  local pass=0 fail=0 out rc

  check() { # check <description> <condition-result>
    if [[ "$2" == "0" ]]; then
      printf '  PASS  %s\n' "$1"; pass=$((pass + 1))
    else
      printf '  FAIL  %s\n' "$1"; fail=$((fail + 1))
    fi
  }

  printf 'deploy.sh self-test\n\n'

  # 1. The headline acceptance criterion: no environment must not deploy.
  rc=0; out="$(bash "$0" 2>&1)" || rc=$?
  check "no argument exits non-zero" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  # Exiting non-zero is not enough on its own: a script that crashed on its way
  # to deploying also exits non-zero. Assert the guard is what stopped it.
  check "no argument refuses explicitly, not incidentally" \
    "$(grep -q 'refusing to deploy' <<<"$out" && echo 0 || echo 1)"
  check "no argument names the environments it will accept" \
    "$(grep -q 'deploy.sh prod' <<<"$out" && echo 0 || echo 1)"
  check "no argument issues no wrangler command at all" \
    "$(grep -qE 'wrangler (deploy|d1)' <<<"$out" && echo 1 || echo 0)"

  # 2. --dry-run alone is still no environment.
  rc=0; out="$(bash "$0" --dry-run 2>&1)" || rc=$?
  check "--dry-run with no environment exits non-zero" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"

  # 3. An unknown environment is refused, not passed through to wrangler.
  rc=0; out="$(bash "$0" definitely-not-an-env --dry-run 2>&1)" || rc=$?
  check "unknown environment exits non-zero" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  check "unknown environment lists the valid ones" \
    "$(grep -q 'prod' <<<"$out" && echo 0 || echo 1)"

  # 4. A real environment plans the right commands.
  rc=0; out="$(bash "$0" prod --dry-run 2>&1)" || rc=$?
  check "prod --dry-run exits zero" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  check "prod applies ALL pending migrations via 'd1 migrations apply'" \
    "$(grep -q 'wrangler d1 migrations apply synaptic-go --remote --env prod' <<<"$out" && echo 0 || echo 1)"
  check "prod deploys with an explicit --env prod" \
    "$(grep -q 'wrangler deploy --env prod' <<<"$out" && echo 0 || echo 1)"
  check "prod never runs a bare 'wrangler deploy'" \
    "$(grep -qE 'wrangler deploy([[:space:]]*$|[[:space:]]+[^-])' <<<"$out" && echo 1 || echo 0)"
  check "migrations run before the deploy" \
    "$([[ "$(grep -n 'migrations apply' <<<"$out" | head -1 | cut -d: -f1)" -lt \
         "$(grep -n 'wrangler deploy' <<<"$out" | head -1 | cut -d: -f1)" ]] && echo 0 || echo 1)"

  # 5. The second environment is not special-cased.
  rc=0; out="$(bash "$0" staging --dry-run 2>&1)" || rc=$?
  check "staging --dry-run exits zero" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  check "staging targets the staging database, not production" \
    "$(grep -q 'wrangler d1 migrations apply synaptic-go-staging --remote --env staging' <<<"$out" && echo 0 || echo 1)"

  # 6. Static guarantees about the deploy path, ignoring comments. These are the
  #    "no script anywhere applies a single hardcoded migration" criterion.
  #    The scan starts at the guard section so it reads the code that actually
  #    deploys, not the assertion strings in this function — which necessarily
  #    contain the very literals being searched for.
  local code
  code="$(sed -n '/^# --- the guard/,$p' "$0" | grep -vE '^[[:space:]]*#')"
  check "no hardcoded NNNN_*.sql migration path in executable code" \
    "$(grep -qE 'migrations/[0-9]{4}_' <<<"$code" && echo 1 || echo 0)"
  check "no 'wrangler d1 execute --file=' bypass of the migration bookkeeping" \
    "$(grep -q 'd1 execute' <<<"$code" && echo 1 || echo 0)"

  # 7. The npm entry point must not reintroduce a bare deploy.
  if [[ -f "$API_DIR/package.json" ]]; then
    check "package.json 'deploy' script is not a bare 'wrangler deploy'" \
      "$(grep -qE '"deploy"[[:space:]]*:[[:space:]]*"wrangler deploy"' "$API_DIR/package.json" && echo 1 || echo 0)"
  fi

  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [[ $fail -eq 0 ]] || return 1
  return 0
}

if [[ "$MODE" == "self-test" ]]; then
  run_self_test
  exit $?
fi

# --- the guard -------------------------------------------------------------
[[ -f "$WRANGLER_TOML" ]] || die "wrangler.toml not found at $WRANGLER_TOML"

VALID_ENVS="$(list_envs)"
[[ -n "$VALID_ENVS" ]] || die "no [env.*] blocks found in $WRANGLER_TOML"

if [[ -z "$ENVIRONMENT" ]]; then
  printf 'deploy.sh: refusing to deploy: no environment given.\n\n' >&2
  printf '  A deploy with no --env publishes the top-level [vars] block of\n' >&2
  printf '  wrangler.toml over production, because that block shares its worker\n' >&2
  printf '  name and its D1 binding with [env.prod]. That is how local-dev values\n' >&2
  printf '  reach production, and DEV_OTP is one of them.\n\n' >&2
  printf '  Choose an environment explicitly:\n' >&2
  while IFS= read -r e; do printf '    ./deploy.sh %s\n' "$e" >&2; done <<<"$VALID_ENVS"
  printf '\n' >&2
  exit 1
fi

if ! grep -qx "$ENVIRONMENT" <<<"$VALID_ENVS"; then
  printf 'deploy.sh: unknown environment "%s".\n\n  wrangler.toml defines:\n' "$ENVIRONMENT" >&2
  while IFS= read -r e; do printf '    %s\n' "$e" >&2; done <<<"$VALID_ENVS"
  printf '\n' >&2
  exit 1
fi

DB_NAME="$(db_name_for_env "$ENVIRONMENT")"
[[ -n "$DB_NAME" ]] || die "no d1_databases.database_name for [env.$ENVIRONMENT] in wrangler.toml — refusing to guess"

cd "$API_DIR"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

printf 'deploy.sh: environment=%s  database=%s%s\n' \
  "$ENVIRONMENT" "$DB_NAME" "$([[ $DRY_RUN -eq 1 ]] && printf '  (dry run)')"

step "1/4 typecheck"
run npm run typecheck

# Applies every pending migration and records each one in d1_migrations. This
# replaces the old hardcoded single-file `d1 execute`, which recorded nothing.
step "2/4 applying all pending migrations to '$DB_NAME'"
run npx wrangler d1 migrations apply "$DB_NAME" --remote --env "$ENVIRONMENT"

step "3/4 deploying the Worker to '$ENVIRONMENT'"
run npx wrangler deploy --env "$ENVIRONMENT"

step "4/4 smoke test"
SMOKE_URL="${SMOKE_URL:-}"
if [[ -z "$SMOKE_URL" && "$ENVIRONMENT" == "prod" ]]; then
  SMOKE_URL="https://api.synapticstudio.tech/health"
fi
if [[ -z "$SMOKE_URL" ]]; then
  printf '    no SMOKE_URL for env "%s" — skipping\n' "$ENVIRONMENT"
else
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] curl -fsS %s\n' "$SMOKE_URL"
  else
    printf '    GET %s\n' "$SMOKE_URL"
    curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$SMOKE_URL" \
      || die "smoke test failed: $SMOKE_URL did not return 200 — the deploy is live but unhealthy"
    printf '\n'
  fi
fi

printf '\ndeploy.sh: done (%s).\n' "$ENVIRONMENT"
printf 'Reminder: the Flutter clients are built and shipped separately.\n'
