#!/usr/bin/env bash
# Create database `hummingbot_sol_pump` on the hummingbot-api Postgres if missing (existing volumes
# skip docker-entrypoint-initdb.d). Run from repo root: ./scripts/ensure-hummingbot-trading-db.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
PGU="${POSTGRES_USER:-hbot}"
if docker compose exec -T postgres psql -U "$PGU" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='hummingbot_sol_pump'" | grep -q 1; then
  echo "Database 'hummingbot_sol_pump' already exists."
  exit 0
fi
docker compose exec -T postgres psql -U "$PGU" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE hummingbot_sol_pump OWNER $PGU;"
echo "Created database 'hummingbot_sol_pump' (owner $PGU)."
