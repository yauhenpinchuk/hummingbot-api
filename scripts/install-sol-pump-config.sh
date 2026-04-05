#!/usr/bin/env bash
# Copy committed sol-pump script + controller YAML into bots/conf/ (gitignored) for API deploy.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/integration/sol-pump/conf"
DEST="$ROOT/bots/conf"
mkdir -p "$DEST/scripts" "$DEST/controllers"
cp -f "$SRC/scripts/sol_pump_lp.yml" "$DEST/scripts/"
cp -f "$SRC/controllers/sol_pump_lp_narrow.yml" "$DEST/controllers/"
cp -f "$SRC/controllers/sol_pump_lp_wide.yml" "$DEST/controllers/"
echo "Installed sol-pump configs into $DEST/{scripts,controllers}/"
