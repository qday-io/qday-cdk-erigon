#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────
# qday2-testnet — health check script
# Verifies the Sequencer and RPC nodes are running and
# responding correctly.
#
# Usage:
#   ./qday/dynamic-configs/health-check.sh                    # check local defaults
#   SEQUENCER_URL=http://<host>:8123 RPC_URL=http://<host>:8124 ./qday/dynamic-configs/health-check.sh
# ──────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SEQUENCER_URL="${SEQUENCER_URL:-http://127.0.0.1:8123}"
RPC_URL="${RPC_URL:-http://127.0.0.1:8124}"
EXPECTED_CHAIN_ID='"0xabe5"'   # 44005 in hex

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

rpc_call() {
  local url="$1" method="$2"
  curl -sf -X POST "$url" \
    -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
    2>/dev/null || echo ""
}

echo "=== qday2-testnet Health Check ==="
echo ""

# ──────────────────────────────────────────────────────
# Check 1: Sequencer is reachable
# ──────────────────────────────────────────────────────
echo "Sequencer ($SEQUENCER_URL):"

SEQ_CHAIN_ID=$(rpc_call "$SEQUENCER_URL" "eth_chainId")
if echo "$SEQ_CHAIN_ID" | grep -q "$EXPECTED_CHAIN_ID"; then
  pass "eth_chainId = $EXPECTED_CHAIN_ID (44005)"
else
  fail "eth_chainId — got: ${SEQ_CHAIN_ID:-no response}"
fi

SEQ_BLOCK=$(rpc_call "$SEQUENCER_URL" "eth_blockNumber")
if echo "$SEQ_BLOCK" | grep -q '"result"'; then
  BLOCK_HEX=$(echo "$SEQ_BLOCK" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  BLOCK_DEC=$((BLOCK_HEX))
  pass "eth_blockNumber = ${BLOCK_HEX} (${BLOCK_DEC})"
else
  fail "eth_blockNumber — got: ${SEQ_BLOCK:-no response}"
fi

SEQ_SYNCING=$(rpc_call "$SEQUENCER_URL" "eth_syncing")
if echo "$SEQ_SYNCING" | grep -q 'false'; then
  pass "eth_syncing = false (not syncing — producing blocks)"
elif echo "$SEQ_SYNCING" | grep -q 'true'; then
  warn "eth_syncing = true (sequencer is syncing, not yet producing)"
else
  warn "eth_syncing — could not determine"
fi

# Check if sequencer is actually in sequencer mode (txpool available)
SEQ_TXPOOL=$(rpc_call "$SEQUENCER_URL" "txpool_status")
if echo "$SEQ_TXPOOL" | grep -q '"result"'; then
  pass "txpool_status — sequencer mode confirmed"
else
  warn "txpool_status — unavailable (sequencer may not be in sequencer mode)"
fi

echo ""

# ──────────────────────────────────────────────────────
# Check 2: RPC node is reachable
# ──────────────────────────────────────────────────────
echo "RPC Node ($RPC_URL):"

RPC_CHAIN_ID=$(rpc_call "$RPC_URL" "eth_chainId")
if echo "$RPC_CHAIN_ID" | grep -q "$EXPECTED_CHAIN_ID"; then
  pass "eth_chainId = $EXPECTED_CHAIN_ID (44005)"
else
  fail "eth_chainId — got: ${RPC_CHAIN_ID:-no response}"
fi

RPC_BLOCK=$(rpc_call "$RPC_URL" "eth_blockNumber")
if echo "$RPC_BLOCK" | grep -q '"result"'; then
  BLOCK_HEX=$(echo "$RPC_BLOCK" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  BLOCK_DEC=$((BLOCK_HEX))
  pass "eth_blockNumber = ${BLOCK_HEX} (${BLOCK_DEC})"
else
  fail "eth_blockNumber — got: ${RPC_BLOCK:-no response}"
fi

RPC_SYNCING=$(rpc_call "$RPC_URL" "eth_syncing")
if echo "$RPC_SYNCING" | grep -q 'false'; then
  pass "eth_syncing = false (fully synced)"
elif echo "$RPC_SYNCING" | grep -q 'true'; then
  warn "eth_syncing = true (still catching up to sequencer)"
else
  warn "eth_syncing — could not determine"
fi

echo ""

# ──────────────────────────────────────────────────────
# Check 3: Block consistency
# ──────────────────────────────────────────────────────
echo "Consistency Check:"

SEQ_BLOCK_NUM=$(echo "$SEQ_BLOCK" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
RPC_BLOCK_NUM=$(echo "$RPC_BLOCK" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [[ -n "$SEQ_BLOCK_NUM" && -n "$RPC_BLOCK_NUM" ]]; then
  DIFF=$(( $SEQ_BLOCK_NUM - $RPC_BLOCK_NUM ))
  if [[ $DIFF -le 2 ]]; then
    pass "Block lag: $DIFF (sequencer @ $SEQ_BLOCK_NUM, RPC @ $RPC_BLOCK_NUM)"
  elif [[ $DIFF -le 20 ]]; then
    warn "Block lag: $DIFF (moderate lag, RPC is catching up)"
  else
    warn "Block lag: $DIFF (large lag — check RPC sync status and datastream connection)"
  fi
else
  fail "Could not compare block heights"
fi

echo ""

# ──────────────────────────────────────────────────────
# Check 4: Datastream port (sequencer only)
# ──────────────────────────────────────────────────────
SEQUENCER_HOST=$(echo "$SEQUENCER_URL" | sed -e 's|^https\?://||' -e 's|:[0-9]*$||')
if command -v nc &>/dev/null; then
  if nc -z -w 2 "$SEQUENCER_HOST" 6900 2>/dev/null; then
    pass "Datastream port 6900 is reachable on $SEQUENCER_HOST"
  else
    warn "Datastream port 6900 is NOT reachable on $SEQUENCER_HOST"
  fi
else
  warn "nc not available — skipping datastream port check"
fi

echo ""

# ──────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────
ERRORS=$(echo -e "${RED}✗${NC}")  # dummy count
if [[ "$SEQUENCER_URL" == *"127.0.0.1"* ]] && [[ "$RPC_URL" == *"127.0.0.1"* ]]; then
  echo "Tip: To check remote nodes, set SEQUENCER_URL and RPC_URL environment variables."
fi

echo "Health check complete."
