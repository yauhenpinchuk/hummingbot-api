#!/usr/bin/env bash
# Copy a full Hummingbot client conf/ tree into bots/credentials/<PROFILE>/ for use as credentials_profile in deploy API.
# Usage: ./scripts/sync-credentials-from-hummingbot.sh /path/to/hummingbot [profile_name]
# Default profile: sol_pump
set -euo pipefail
HUMMINGBOT_ROOT="${1:?Path to hummingbot repo root required}"
PROFILE="${2:-sol_pump}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_CONF="$HUMMINGBOT_ROOT/conf"
DEST="$ROOT/bots/credentials/$PROFILE"
if [[ ! -d "$SRC_CONF" ]]; then
  echo "ERROR: $SRC_CONF not found" >&2
  exit 1
fi
mkdir -p "$ROOT/bots/credentials"
rm -rf "$DEST"
mkdir -p "$DEST"
# Flat copy: conf/* -> credentials/profile/* (matches DockerService copytree layout)
cp -a "$SRC_CONF/." "$DEST/"
echo "Synced $SRC_CONF -> $DEST"
echo "Use credentials_profile: \"$PROFILE\" in POST /bot-orchestration/deploy-v2-script"
echo "Ensure CONFIG_PASSWORD in API .env matches the password used for encrypted connector files."
