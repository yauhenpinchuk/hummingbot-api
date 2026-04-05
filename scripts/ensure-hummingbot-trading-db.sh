#!/usr/bin/env bash
# Create database `hummingbot_sol_pump` on the hummingbot-api Postgres if missing.
#
# Fresh Postgres volumes: init-db.sql already creates it on first boot.
# Existing volumes (upgrades): run this once or on every deploy (idempotent).
#
# Dev (repo root, docker-compose.yml + .env):
#   ./scripts/ensure-hummingbot-trading-db.sh
#
# Production (same layout as CI: compose.prod + secrets next to repo):
#   COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=../.secrets/env ./scripts/ensure-hummingbot-trading-db.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DC=(docker compose)
if [[ -n "${COMPOSE_FILE:-}" ]]; then
  DC+=(-f "$COMPOSE_FILE")
fi
if [[ -n "${ENV_FILE:-}" ]]; then
  DC+=(--env-file "$ENV_FILE")
fi

if [[ -n "${ENV_FILE:-}" && -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a
elif [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PGU="${POSTGRES_USER:-hbot}"

if "${DC[@]}" exec -T postgres psql -U "$PGU" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='hummingbot_sol_pump'" | grep -q 1; then
  echo "Database 'hummingbot_sol_pump' already exists."
  exit 0
fi

"${DC[@]}" exec -T postgres psql -U "$PGU" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE hummingbot_sol_pump OWNER $PGU;"
echo "Created database 'hummingbot_sol_pump' (owner $PGU)."
