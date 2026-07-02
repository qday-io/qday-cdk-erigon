#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────
# qday2-testnet — cleanup / reset script
# Wipes all chain data directories so the next start
# begins from genesis.
#
# Usage:
#   ./qday/dynamic-configs/cleanup.sh          # interactive confirmation
#   ./qday/dynamic-configs/cleanup.sh --force  # skip confirmation
#
# Wipes:
#   - datadir-validium        (sequencer chain data)
#   - datadir-validium-rpc    (RPC node chain data)
#   - data/pool-db            (pool manager Postgres data)
# ──────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/qday/dynamic-configs"

SEQ_DATADIR="./datadir-validium"
RPC_DATADIR="./datadir-validium-rpc"
POOL_DB_DIR="./data/pool-db"

DIRS_TO_CLEAN=()

[[ -d "$SEQ_DATADIR" ]] && DIRS_TO_CLEAN+=("$SEQ_DATADIR")
[[ -d "$RPC_DATADIR" ]] && DIRS_TO_CLEAN+=("$RPC_DATADIR")
[[ -d "$POOL_DB_DIR" ]] && DIRS_TO_CLEAN+=("$POOL_DB_DIR")

if [[ ${#DIRS_TO_CLEAN[@]} -eq 0 ]]; then
  echo "Nothing to clean up — no data directories found."
  exit 0
fi

echo "=== qday2-testnet Cleanup ==="
echo ""
echo "The following directories will be deleted:"
for dir in "${DIRS_TO_CLEAN[@]}"; do
  SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
  echo "  $dir  ($SIZE)"
done
echo ""

if [[ "${1:-}" != "--force" ]]; then
  read -r -p "Are you sure you want to wipe all chain data? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

for dir in "${DIRS_TO_CLEAN[@]}"; do
  echo "Removing $dir..."
  rm -rf "$dir"
done

echo ""
echo "All chain data wiped. Start fresh with:"
echo "  ./start-sequencer.sh    (or ./start-all.sh)"
