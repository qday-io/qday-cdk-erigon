#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────
# qday2-testnet — all-in-one launcher
# Starts the sequencer in the background, waits for it
# to be ready, then starts the RPC node.
#
# Usage:
#   ./qday/dynamic-configs/start-all.sh
#
# Environment variables:
#   DATASTREAM_URL   override sequencer datastream URL (default: 127.0.0.1:6900)
#   SEQUENCER_PORT   override sequencer health-check port (default: 8123)
#   WAIT_TIMEOUT     max seconds to wait for sequencer (default: 120)
# ──────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SEQUENCER_PORT="${SEQUENCER_PORT:-8123}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
DATASTREAM_URL="${DATASTREAM_URL:-127.0.0.1:6900}"

BINARY="$ROOT/build/bin/cdk-erigon"

if [[ ! -x "$BINARY" ]]; then
  echo "[ERROR] Binary not found at $BINARY"
  echo "        Build it first: make cdk-erigon"
  exit 1
fi

SEQ_DATADIR="$ROOT/qday/dynamic-configs/datadir-validium"
RPC_DATADIR="$ROOT/qday/dynamic-configs/datadir-validium-rpc"

echo "=== qday2-testnet All-in-One Launcher ==="
echo ""
echo "Sequencer:  RPC :${SEQUENCER_PORT}, datastream on :6900"
echo "RPC Node:   RPC :8124, syncing from ${DATASTREAM_URL}"
echo "Datadirs:   ${SEQ_DATADIR} / ${RPC_DATADIR}"
echo ""

# ──────────────────────────────────────────────────────
# Step 1: Start the sequencer in background
# ──────────────────────────────────────────────────────
echo "[1/3] Starting sequencer..."
export CDK_ERIGON_SEQUENCER=1

"$BINARY" \
  --config="$ROOT/qday/dynamic-configs/dynamic-validium.yaml" \
  --datadir="$SEQ_DATADIR" \
  --zkevm.initial-batch.config="$ROOT/qday/dynamic-configs/empty-batch.json" &
SEQ_PID=$!

trap 'echo "Shutting down..."; kill $SEQ_PID $RPC_PID 2>/dev/null || true' EXIT INT TERM

# ──────────────────────────────────────────────────────
# Step 2: Wait for the sequencer to be ready
# ──────────────────────────────────────────────────────
echo "[2/3] Waiting for sequencer to be ready..."
START_TIME=$(date +%s)

while true; do
  if ! kill -0 "$SEQ_PID" 2>/dev/null; then
    echo "[ERROR] Sequencer process died unexpectedly"
    exit 1
  fi

  RESULT=$(curl -sf -X POST "http://127.0.0.1:${SEQUENCER_PORT}" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null || true)

  if echo "$RESULT" | grep -q '"result"'; then
    BLOCK=$(echo "$RESULT" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    echo "  Sequencer ready (block: $BLOCK)"
    break
  fi

  ELAPSED=$(( $(date +%s) - START_TIME ))
  if [[ $ELAPSED -ge $WAIT_TIMEOUT ]]; then
    echo "[ERROR] Sequencer did not become ready within ${WAIT_TIMEOUT}s"
    kill "$SEQ_PID" 2>/dev/null || true
    exit 1
  fi

  sleep 2
done

# ──────────────────────────────────────────────────────
# Step 3: Start the RPC node
# ──────────────────────────────────────────────────────
echo "[3/3] Starting RPC node..."

"$BINARY" \
  --config="$ROOT/qday/dynamic-configs/dynamic-validium-rpc.yaml" \
  --datadir="$RPC_DATADIR" \
  --zkevm.l2-datastreamer-url="$DATASTREAM_URL" &
RPC_PID=$!

echo ""
echo "=== Both nodes running ==="
echo "  Sequencer PID: $SEQ_PID  (RPC http://127.0.0.1:${SEQUENCER_PORT})"
echo "  RPC Node PID:  $RPC_PID  (RPC http://127.0.0.1:8124)"
echo ""
echo "Press Ctrl+C to stop both nodes."

wait
