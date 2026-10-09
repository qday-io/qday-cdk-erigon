#!/usr/bin/env bash
# =============================================================================
# verify-recovery.sh — acceptance checks for an L1 rebuild
# =============================================================================
# Checks the recovery node in order:
#   1. zkevm_batchNumber has reached EXPECTED_BATCH (latest virtual batch on L1)
#   2. stateRoot of ANCHOR_BATCH equals the L1-verified anchor ANCHOR_STATE_ROOT
#      (proof that the replay matches)
#   3. SPOT_CHECK_BATCH exists and contains blocks (it was null on the old node)
#   4. A witness can be built for SPOT_CHECK_BATCH (required by the aggregator)
#   5. zkevm_virtualBatchNumber matches L1 (L1 sync is healthy)
#
# Usage:
#   ./verify-recovery.sh [rpc-url]
# Defaults are read from .env in this directory.
# rpc-url defaults to http://127.0.0.1:${RECOVER_RPC_PORT}
#
# Requires: bash, curl, grep, printf (not jq or python)
# Exit code: 0 if every check passes; 1 if any check fails
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---- load .env when present -------------------------------------------------
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

EXPECTED_BATCH="${EXPECTED_BATCH:?set EXPECTED_BATCH in .env}"
ANCHOR_BATCH="${ANCHOR_BATCH:?set ANCHOR_BATCH in .env}"
ANCHOR_STATE_ROOT="${ANCHOR_STATE_ROOT:?set ANCHOR_STATE_ROOT in .env}"
SPOT_CHECK_BATCH="${SPOT_CHECK_BATCH:?set SPOT_CHECK_BATCH in .env}"

RPC_URL="${1:-http://127.0.0.1:${RECOVER_RPC_PORT:-8645}}"

# ---- helpers ----------------------------------------------------------------
rpc() { # rpc <method> <params-json>
  curl -sf -m 30 -X POST "$RPC_URL" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}

hex_of() { printf '0x%x' "$1"; } # decimal -> 0x hex

lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; } # bash 3.2 compatible

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILED=1; }

FAILED=0

echo "Target node: $RPC_URL"
echo

# ---- 0. connectivity --------------------------------------------------------
echo "[0] node connectivity"
if ! rpc eth_blockNumber '[]' >/dev/null 2>&1; then
  fail "cannot reach $RPC_URL; is the node running?"
  echo; echo "Verification failed"; exit 1
fi
pass "RPC is up"

# ---- 1. batch height --------------------------------------------------------
echo "[1] zkevm_batchNumber should be >= $EXPECTED_BATCH"
resp="$(rpc zkevm_batchNumber '[]' || true)"
got="$(echo "$resp" | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || true)"
want="$(hex_of "$EXPECTED_BATCH")"
if [[ -n "$got" && $((got)) -ge $EXPECTED_BATCH ]]; then
  pass "batchNumber = $got ($((got)))"
else
  fail "batchNumber = ${got:-no result}, want >= $want ($EXPECTED_BATCH) (still syncing?)"
fi

# ---- 2. stateRoot anchor ----------------------------------------------------
echo "[2] stateRoot of batch $ANCHOR_BATCH should match the L1-verified anchor"
resp="$(rpc zkevm_getBatchByNumber "[\"$(hex_of "$ANCHOR_BATCH")\",false]" || true)"
got_root="$(echo "$resp" | grep -o '"stateRoot":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || true)"
if [[ -n "$got_root" && "$(lower "$got_root")" == "$(lower "$ANCHOR_STATE_ROOT")" ]]; then
  pass "stateRoot = $got_root"
else
  fail "stateRoot = ${got_root:-no result}, want $ANCHOR_STATE_ROOT"
  echo "         stateRoot mismatch means the replay forked from L1-verified state; do not cut over"
fi

# ---- 3. spot-check batch data -----------------------------------------------
echo "[3] batch $SPOT_CHECK_BATCH should exist and contain blocks"
resp="$(rpc zkevm_getBatchByNumber "[\"$(hex_of "$SPOT_CHECK_BATCH")\",false]" || true)"
if echo "$resp" | grep -q '"result":null'; then
  fail "batch $SPOT_CHECK_BATCH is null (the old node's symptom); recovery did not cover it"
elif echo "$resp" | grep -q '"blocks":\["0x'; then
  pass "batch $SPOT_CHECK_BATCH exists and blocks are non-empty"
else
  fail "batch $SPOT_CHECK_BATCH exists but blocks are empty; inspect: $resp"
fi

# ---- 4. witness can be built ------------------------------------------------
echo "[4] witness for batch $SPOT_CHECK_BATCH should be buildable"
resp="$(rpc zkevm_getBatchWitness "[${SPOT_CHECK_BATCH},\"trimmed\"]" || true)"
if echo "$resp" | grep -q '"result":"0x'; then
  pass "witness built"
else
  err="$(echo "$resp" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || true)"
  fail "witness build failed: ${err:-$resp}"
fi

# ---- 5. L1 virtual batch matches --------------------------------------------
echo "[5] zkevm_virtualBatchNumber should equal $EXPECTED_BATCH"
resp="$(rpc zkevm_virtualBatchNumber '[]' || true)"
got="$(echo "$resp" | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || true)"
if [[ -n "$got" && $((got)) -eq $EXPECTED_BATCH ]]; then
  pass "virtualBatchNumber = $got ($((got)))"
else
  fail "virtualBatchNumber = ${got:-no result}, want $(hex_of "$EXPECTED_BATCH") ($EXPECTED_BATCH) (L1 sync unfinished?)"
fi

# ---- summary ----------------------------------------------------------------
echo
if [[ $FAILED -eq 0 ]]; then
  echo "All checks passed. Cut over with: ./cutover.sh"
  exit 0
else
  echo "Verification failed; do not cut over. See the FAIL lines above and the troubleshooting section in README.md."
  exit 1
fi
