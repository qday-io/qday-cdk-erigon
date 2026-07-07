#!/usr/bin/env bash
# =============================================================================
# QDAY2 Chain Verification Tool
# =============================================================================
# Interactive menu for verifying and interacting with the QDAY2 L2 chain.
# Requires forge/cast (Foundry).
#
# Usage:
#   bash tools/verify.sh --rpc http://localhost:8545
#   bash tools/verify.sh --rpc https://rpc-test.qday.io
# =============================================================================
set -euo pipefail

RPC_URL=""
VERBOSE=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc) RPC_URL="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=true; shift ;;
    -h|--help)
      echo "Usage: $0 --rpc <URL> [--verbose]"
      echo ""
      echo "  --rpc <URL>     JSON-RPC endpoint (required)"
      echo "  --verbose, -v   Show raw command output"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$RPC_URL" ]]; then
  echo "ERROR: --rpc is required."
  echo "  bash tools/verify.sh --rpc http://localhost:8545"
  exit 1
fi

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
if ! command -v cast &>/dev/null; then
  echo "ERROR: 'cast' (foundry) is required."
  echo "  Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
cast_call() {
  if $VERBOSE; then
    echo "  \$ cast $* --rpc-url ${RPC_URL}"
    cast "$@" --rpc-url "$RPC_URL"
  else
    cast "$@" --rpc-url "$RPC_URL" 2>/dev/null
  fi
}

section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

divider() {
  echo "──────────────────────────────────────────────────────────────────"
}

# ---------------------------------------------------------------------------
# Menu display
# ---------------------------------------------------------------------------
show_menu() {
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  echo "│  QDAY2 Chain Verification                    RPC: ${RPC_URL}  │"
  echo "├─────────────────────────────────────────────────────────────┤"
  echo "│                                                             │"
  echo "│  Chain Info:                                                │"
  echo "│   1) Chain ID         2) Block Number    3) Gas Price       │"
  echo "│   4) Fork ID          5) Latest Block                       │"
  echo "│                                                             │"
  echo "│  Account:                                                   │"
  echo "│   6) ETH Balance      7) Nonce           8) Tx Count        │"
  echo "│                                                             │"
  echo "│  Contract:                                                  │"
  echo "│   9) Check Code      10) Call View Fn                       │"
  echo "│                                                             │"
  echo "│  Transaction:                                               │"
  echo "│  11) Send ETH        12) Tx Receipt     13) Estimate Gas    │"
  echo "│                                                             │"
  echo "│  Network Health:                                            │"
  echo "│  14) Sync Status     15) Net Version    16) Peer Count      │"
  echo "│  17) Quick Health Check (runs 1,2,3,4,14)                   │"
  echo "│                                                             │"
  echo "│  Settings:                                                  │"
  echo "│  v) Toggle Verbose   r) Change RPC URL                      │"
  echo "│  q) Quit                                                    │"
  echo "│                                                             │"
  echo "└─────────────────────────────────────────────────────────────┘"
}

# ===========================================================================
# Chain Info
# ===========================================================================

fn_chain_id() {
  section "Chain ID"
  local id; id=$(cast_call chain-id)
  echo "  Chain ID: ${id:-error}"
  divider
}

fn_block_number() {
  section "Block Number"
  local bn; bn=$(cast_call block-number)
  echo "  Latest block: ${bn:-error}"
  divider
}

fn_gas_price() {
  section "Gas Price"
  local gp; gp=$(cast_call gas-price)
  if [[ -n "$gp" ]]; then
    local gwei; gwei=$(echo "scale=2; $gp / 1000000000" | bc 2>/dev/null || echo "$gp")
    echo "  Gas price: ${gp} wei  (~${gwei} gwei)"
  else
    echo "  Gas price: error"
  fi
  divider
}

fn_fork_id() {
  section "Fork ID"
  local fid; fid=$(cast rpc zkevm_forkId --rpc-url "$RPC_URL" 2>/dev/null || cast rpc zkevm_getForkId --rpc-url "$RPC_URL" 2>/dev/null || echo "N/A")
  echo "  Fork ID: ${fid:-N/A}"
  divider
}

fn_latest_block() {
  section "Latest Block"
  cast_call block latest
  divider
}

# ===========================================================================
# Account
# ===========================================================================

fn_balance() {
  section "ETH Balance"
  read -r -p "  Address (0x…): " ADDR
  [[ -z "$ADDR" ]] && { echo "  Cancelled."; return; }
  local bal; bal=$(cast_call balance "$ADDR")
  if [[ -n "$bal" ]]; then
    local eth; eth=$(echo "scale=6; $bal / 1000000000000000000" | bc 2>/dev/null || echo "$bal")
    echo "  Balance: ${bal} wei  (~${eth} ETH)"
  else
    echo "  Balance: error"
  fi
  divider
}

fn_nonce() {
  section "Nonce"
  read -r -p "  Address (0x…): " ADDR
  [[ -z "$ADDR" ]] && { echo "  Cancelled."; return; }
  local nonce; nonce=$(cast_call nonce "$ADDR")
  echo "  Nonce: ${nonce:-error}"
  divider
}

fn_tx_count() {
  section "Transaction Count"
  read -r -p "  Address (0x…): " ADDR
  [[ -z "$ADDR" ]] && { echo "  Cancelled."; return; }
  local count; count=$(cast_call tx-count "$ADDR")
  echo "  Transaction count: ${count:-error}"
  divider
}

# ===========================================================================
# Contract
# ===========================================================================

fn_check_code() {
  section "Check Contract Code"
  read -r -p "  Contract address (0x…): " ADDR
  [[ -z "$ADDR" ]] && { echo "  Cancelled."; return; }
  local code; code=$(cast_call code "$ADDR")
  if [[ -z "$code" || "$code" == "0x" ]]; then
    echo "  Result: NO code (EOA or empty address)"
  else
    local len; len=$(echo -n "${code:2}" | wc -c | tr -d ' ')
    echo "  Result: CONTRACT deployed  (code length: $len bytes)"
  fi
  divider
}

fn_call_view() {
  section "Call View Function"
  read -r -p "  Contract address (0x…): " ADDR
  [[ -z "$ADDR" ]] && { echo "  Cancelled."; return; }
  read -r -p "  Function signature (e.g. 'totalSupply()(uint256)'): " SIG
  [[ -z "$SIG" ]] && { echo "  Cancelled."; return; }
  echo ""
  cast_call call "$ADDR" "$SIG"
  divider
}

# ===========================================================================
# Transaction
# ===========================================================================

fn_send_eth() {
  section "Send ETH"
  read -r -p "  Private key (0x…): " PK
  [[ -z "$PK" ]] && { echo "  Cancelled."; return; }
  read -r -p "  To address (0x…): " TO
  [[ -z "$TO" ]] && { echo "  Cancelled."; return; }
  read -r -p "  Amount in ETH (e.g. 0.01): " AMT
  [[ -z "$AMT" ]] && { echo "  Cancelled."; return; }

  local val; val=$(echo "$AMT * 10^18" | bc 2>/dev/null | cut -d. -f1)
  echo ""
  echo "  Sending ${AMT} ETH → ${TO} ..."
  local tx; tx=$(cast_call send --private-key "$PK" --legacy --value "$val" "$TO" 2>&1)
  echo "  TX: ${tx}"
  divider
}

fn_tx_receipt() {
  section "Transaction Receipt"
  read -r -p "  TX hash (0x…): " HASH
  [[ -z "$HASH" ]] && { echo "  Cancelled."; return; }
  cast_call receipt "$HASH"
  divider
}

fn_estimate_gas() {
  section "Estimate Gas"
  read -r -p "  From address (0x…): " FROM
  [[ -z "$FROM" ]] && { echo "  Cancelled."; return; }
  read -r -p "  To address (0x…): " TO
  [[ -z "$TO" ]] && { echo "  Cancelled."; return; }
  read -r -p "  Value in ETH (default 0): " VAL
  VAL="${VAL:-0}"
  local wei; wei=$(echo "$VAL * 10^18" | bc 2>/dev/null | cut -d. -f1)

  echo ""
  echo "  Estimating gas for ${FROM} → ${TO} (${VAL} ETH) ..."
  cast_call estimate --from "$FROM" --value "$wei" "$TO"
  divider
}

# ===========================================================================
# Network Health
# ===========================================================================

fn_sync_status() {
  section "Sync Status"
  local sync; sync=$(cast_call rpc eth_syncing 2>/dev/null)
  if [[ "$sync" == "false" ]]; then
    echo "  Status: Synced ✓"
  elif [[ -z "$sync" ]]; then
    echo "  Status: Unable to query"
  else
    echo "  Status: Syncing"
    echo "  $sync"
  fi
  divider
}

fn_net_version() {
  section "Net Version"
  local ver; ver=$(cast_call rpc net_version)
  echo "  Network ID: ${ver:-error}"
  divider
}

fn_peer_count() {
  section "Peer Count"
  local peers; peers=$(cast_call rpc net_peerCount 2>/dev/null || echo "N/A")
  echo "  Peers: ${peers:-N/A}"
  divider
}

fn_quick_health() {
  section "Quick Health Check"
  local ok=0 fail=0

  echo -n "  Chain ID ... "
  local id; id=$(cast_call chain-id 2>/dev/null) && echo "✓ ${id}" && { ((ok++)); true; } || { echo "✗ FAIL"; ((fail++)); }

  echo -n "  Block Number ... "
  local bn; bn=$(cast_call block-number 2>/dev/null) && echo "✓ ${bn}" && { ((ok++)); true; } || { echo "✗ FAIL"; ((fail++)); }

  echo -n "  Gas Price ... "
  local gp; gp=$(cast_call gas-price 2>/dev/null) && echo "✓" && { ((ok++)); true; } || { echo "✗ FAIL"; ((fail++)); }

  echo -n "  Fork ID ... "
  local fid; fid=$(cast_call rpc zkevm_forkId 2>/dev/null || cast rpc zkevm_getForkId --rpc-url "$RPC_URL" 2>/dev/null) && echo "✓ ${fid}" && { ((ok++)); true; } || { echo "✗ FAIL (may not be zkEVM)"; ((fail++)); }

  echo -n "  Sync Status ... "
  local sync; sync=$(cast_call rpc eth_syncing 2>/dev/null) && echo "✓ Synced" && { ((ok++)); true; } || { echo "✗ FAIL"; ((fail++)); }

  echo ""
  echo "  Result: ${ok}/$((ok+fail)) checks passed"
  divider
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

fn_toggle_verbose() {
  $VERBOSE && VERBOSE=false || VERBOSE=true
  echo "  Verbose: ${VERBOSE}"
}

fn_change_rpc() {
  read -r -p "  New RPC URL: " new_url
  [[ -z "$new_url" ]] && { echo "  Cancelled."; return; }
  RPC_URL="$new_url"
  echo "  RPC set to: ${RPC_URL}"
}

# ===========================================================================
# Main loop
# ===========================================================================
echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     QDAY2 Chain Verification Tool        ║"
echo "  ║     RPC: ${RPC_URL}                      ║"
echo "  ╚══════════════════════════════════════════╝"

# Quick initial health check
echo ""
echo -n "  Testing connection ... "
if cast chain-id --rpc-url "$RPC_URL" &>/dev/null; then
  echo "connected ✓"
else
  echo "FAILED — check RPC URL and network connectivity"
  exit 1
fi

while true; do
  show_menu
  read -r -p "  Select [1-17, v, r, q]: " CHOICE

  case "$CHOICE" in
    1)  fn_chain_id ;;
    2)  fn_block_number ;;
    3)  fn_gas_price ;;
    4)  fn_fork_id ;;
    5)  fn_latest_block ;;
    6)  fn_balance ;;
    7)  fn_nonce ;;
    8)  fn_tx_count ;;
    9)  fn_check_code ;;
   10) fn_call_view ;;
   11) fn_send_eth ;;
   12) fn_tx_receipt ;;
   13) fn_estimate_gas ;;
   14) fn_sync_status ;;
   15) fn_net_version ;;
   16) fn_peer_count ;;
   17) fn_quick_health ;;
    v)  fn_toggle_verbose ;;
    r)  fn_change_rpc ;;
    q|Q) echo ""; echo "  Bye."; exit 0 ;;
    *)  echo "  Invalid choice." ;;
  esac
done