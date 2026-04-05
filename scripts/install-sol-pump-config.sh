#!/usr/bin/env bash
# Copy committed sol-pump script + controller YAML into bots/conf/ (gitignored) for API deploy.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/integration/sol-pump/conf"
DEST="$ROOT/bots/conf"
FILES=(
  "$SRC/scripts/sol_pump_lp.yml"
  "$SRC/controllers/sol_pump_lp_narrow.yml"
  "$SRC/controllers/sol_pump_lp_wide.yml"
)
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "install-sol-pump-config: missing source file: $f" >&2
    echo "Ensure the repo includes integration/sol-pump/conf/ (git pull / correct checkout)." >&2
    exit 1
  fi
done
mkdir -p "$DEST/scripts" "$DEST/controllers"
cp -f "${FILES[0]}" "$DEST/scripts/"
cp -f "${FILES[1]}" "$DEST/controllers/"
cp -f "${FILES[2]}" "$DEST/controllers/"
echo "Installed sol-pump configs:"
echo "  $DEST/scripts/sol_pump_lp.yml"
echo "  $DEST/controllers/sol_pump_lp_narrow.yml"
echo "  $DEST/controllers/sol_pump_lp_wide.yml"
echo "(Not under bots/credentials/ — use make sync-credentials-from-hummingbot for that tree.)"
ls -la "$DEST/scripts" "$DEST/controllers"
