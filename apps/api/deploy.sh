#!/usr/bin/env bash
#
# deploy.sh — GoDrive Worker deploy with the migration-first ordering that
# the city filter depends on.
#
# Why the order matters: migration 0009 adds `captains.city`, which the new
# Worker code writes on /captain/online and /captain/location. Deploying the
# Worker before the migration leaves those endpoints throwing SQL errors and
# drops every captain offline. So: migrate → verify → deploy.
#
# Usage:
#   ./deploy.sh <d1-database-name>
#   CLOUDFLARE_API_TOKEN=... ./deploy.sh godrive-db
#
# The token is read from CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID in the
# environment (standard wrangler auth), or from `wrangler login` state.

set -euo pipefail

DB_NAME="${1:-}"
if [[ -z "$DB_NAME" ]]; then
  echo "usage: $0 <d1-database-name>" >&2
  echo "example: $0 godrive-db" >&2
  exit 1
fi

# Resolve paths relative to this script (apps/api/), so it works from anywhere.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
API_DIR="$SCRIPT_DIR"
MIGRATION="$SCRIPT_DIR/../../migrations/0009_captain_city.sql"

cd "$API_DIR"

if [[ ! -f "$MIGRATION" ]]; then
  echo "migration not found: $MIGRATION" >&2
  exit 1
fi

echo "==> 1/4 applying migration 0009 to D1 database '$DB_NAME'..."
wrangler d1 execute "$DB_NAME" --file="$MIGRATION"

echo "==> 2/4 verifying the backfill (online captains carry city='cairo')..."
wrangler d1 execute "$DB_NAME" \
  --command="SELECT city, COUNT(*) AS captains FROM captains GROUP BY city;"

echo "==> 3/4 deploying the Worker..."
wrangler deploy

echo "==> 4/4 done."
echo "Next: ship new builds of the captain and rider apps — the typing"
echo "indicator, live rider chat and auto-refreshing trips tab are client-side."
