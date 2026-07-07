#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────
# qday2-testnet — configuration validator
# Checks YAML syntax, JSON validity, chain-id consistency,
# and cross-file references for the qday2-testnet configs.
#
# Usage:
#   ./qday/dynamic-configs/validate-config.sh
# ──────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$CONFIG_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

echo "=== qday2-testnet Config Validator ==="
echo ""

# ──────────────────────────────────────────────────────
# 1. File existence checks
# ──────────────────────────────────────────────────────
echo "File existence:"

declare -a REQUIRED_FILES=(
  "dynamic-validium.yaml"
  "dynamic-validium-rpc.yaml"
  "dynamic-qday2-testnet-chainspec.json"
  "dynamic-qday2-testnet-conf.json"
  "dynamic-qday2-testnet-allocs.json"
  "empty-batch.json"
  "docker-compose.yml"
  "docker-compose.rpc.yml"
  "env.example"
  "poolmanager.toml"
  "Dockerfile.local"
  "docker-entrypoint.sh"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    pass "$f"
  else
    fail "$f — MISSING"
  fi
done

echo ""

# ──────────────────────────────────────────────────────
# 2. YAML syntax check
# ──────────────────────────────────────────────────────
echo "YAML syntax:"

if command -v python3 &>/dev/null; then
  for yaml_file in dynamic-validium.yaml dynamic-validium-rpc.yaml; do
    if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
      pass "$yaml_file — valid YAML"
    else
      fail "$yaml_file — YAML parse error"
    fi
  done
elif command -v ruby &>/dev/null; then
  for yaml_file in dynamic-validium.yaml dynamic-validium-rpc.yaml; do
    if ruby -ryaml -e "YAML.load_file('$yaml_file')" 2>/dev/null; then
      pass "$yaml_file — valid YAML"
    else
      fail "$yaml_file — YAML parse error"
    fi
  done
else
  warn "python3 or ruby not found — skipping YAML validation"
fi

echo ""

# ──────────────────────────────────────────────────────
# 3. JSON validity
# ──────────────────────────────────────────────────────
echo "JSON validity:"

JSON_FILES=(
  "dynamic-qday2-testnet-chainspec.json"
  "dynamic-qday2-testnet-conf.json"
  "dynamic-qday2-testnet-allocs.json"
)

for json_file in "${JSON_FILES[@]}"; do
  if command -v python3 &>/dev/null; then
    if python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
      pass "$json_file — valid JSON"
    else
      fail "$json_file — JSON parse error"
    fi
  elif command -v jq &>/dev/null; then
    if jq empty "$json_file" 2>/dev/null; then
      pass "$json_file — valid JSON"
    else
      fail "$json_file — JSON parse error"
    fi
  else
    warn "python3 or jq not found — skipping JSON validation"
  fi
done

echo ""

# ──────────────────────────────────────────────────────
# 4. Chain ID consistency
# ──────────────────────────────────────────────────────
echo "Chain ID (44005) consistency:"

EXPECTED_CHAIN_ID=44005

# From chainspec
CHAINSPEC_ID=$(grep -o '"chainId"[[:space:]]*:[[:space:]]*[0-9]*' dynamic-qday2-testnet-chainspec.json | grep -o '[0-9]*' || echo "")
if [[ "$CHAINSPEC_ID" == "$EXPECTED_CHAIN_ID" ]]; then
  pass "chainspec chainId = $EXPECTED_CHAIN_ID"
else
  fail "chainspec chainId = ${CHAINSPEC_ID:-not found}, expected $EXPECTED_CHAIN_ID"
fi

# From sequencer YAML (exact line match to avoid collision with datastream-version)
SEQ_CHAIN_ID=$(grep 'zkevm.l2-chain-id:' dynamic-validium.yaml | head -1 | grep -o '[0-9]*' | tail -1 || echo "")
if [[ "$SEQ_CHAIN_ID" == "$EXPECTED_CHAIN_ID" ]]; then
  pass "sequencer config zkevm.l2-chain-id = $EXPECTED_CHAIN_ID"
else
  fail "sequencer config zkevm.l2-chain-id = ${SEQ_CHAIN_ID:-not found}, expected $EXPECTED_CHAIN_ID"
fi

# From RPC YAML (exact line match to avoid collision with datastream-version)
RPC_CHAIN_ID=$(grep 'zkevm.l2-chain-id:' dynamic-validium-rpc.yaml | head -1 | grep -o '[0-9]*' | tail -1 || echo "")
if [[ "$RPC_CHAIN_ID" == "$EXPECTED_CHAIN_ID" ]]; then
  pass "RPC config zkevm.l2-chain-id = $EXPECTED_CHAIN_ID"
else
  fail "RPC config zkevm.l2-chain-id = ${RPC_CHAIN_ID:-not found}, expected $EXPECTED_CHAIN_ID"
fi

# Blockscout configs not included — see separate blockscout repo

echo ""

# ──────────────────────────────────────────────────────
# 5. Chain name consistency
# ──────────────────────────────────────────────────────
echo "Chain name consistency:"

EXPECTED_CHAIN="dynamic-qday2-testnet"

SEQ_CHAIN_NAME=$(grep -o '^chain:[[:space:]]*.*' dynamic-validium.yaml | sed 's/^chain:[[:space:]]*//' || echo "")
if [[ "$SEQ_CHAIN_NAME" == "$EXPECTED_CHAIN" ]]; then
  pass "sequencer config chain = $EXPECTED_CHAIN"
else
  fail "sequencer config chain = '${SEQ_CHAIN_NAME:-not found}', expected '$EXPECTED_CHAIN'"
fi

RPC_CHAIN_NAME=$(grep -o '^chain:[[:space:]]*.*' dynamic-validium-rpc.yaml | sed 's/^chain:[[:space:]]*//' || echo "")
if [[ "$RPC_CHAIN_NAME" == "$EXPECTED_CHAIN" ]]; then
  pass "RPC config chain = $EXPECTED_CHAIN"
else
  fail "RPC config chain = '${RPC_CHAIN_NAME:-not found}', expected '$EXPECTED_CHAIN'"
fi

echo ""

# ──────────────────────────────────────────────────────
# 6. Standalone mode consistency
# ──────────────────────────────────────────────────────
echo "Standalone mode validation:"

# Sequencer should have skip-l1-sync and initial-fork-id
if grep -q 'zkevm.skip-l1-sync: true' dynamic-validium.yaml; then
  pass "sequencer: zkevm.skip-l1-sync = true"
else
  fail "sequencer: zkevm.skip-l1-sync is not true in standalone mode"
fi

if grep -q 'zkevm.initial-fork-id:' dynamic-validium.yaml; then
  FORK_ID=$(grep 'zkevm.initial-fork-id:' dynamic-validium.yaml | head -1 | grep -oE '[0-9]+' | head -1 || echo "")
  if [[ -n "$FORK_ID" && "$FORK_ID" -gt 0 ]]; then
    pass "sequencer: zkevm.initial-fork-id = $FORK_ID (non-zero)"
  else
    fail "sequencer: zkevm.initial-fork-id = ${FORK_ID:-0} (must be non-zero in standalone mode)"
  fi
fi

if grep -q 'zkevm.skip-l1-sync: true' dynamic-validium-rpc.yaml; then
  pass "RPC: zkevm.skip-l1-sync = true"
else
  fail "RPC: zkevm.skip-l1-sync is not true in standalone mode"
fi

echo ""

# ──────────────────────────────────────────────────────
# 7. Port isolation check (sequencer vs RPC)
# ──────────────────────────────────────────────────────
echo "Port isolation (sequencer vs RPC):"

SEQ_HTTP=$(grep -o 'http.port:[[:space:]]*[0-9]*' dynamic-validium.yaml | grep -o '[0-9]*' || echo "")
RPC_HTTP=$(grep -o 'http.port:[[:space:]]*[0-9]*' dynamic-validium-rpc.yaml | grep -o '[0-9]*' || echo "")

if [[ "$SEQ_HTTP" != "$RPC_HTTP" && -n "$SEQ_HTTP" && -n "$RPC_HTTP" ]]; then
  pass "HTTP ports: sequencer=$SEQ_HTTP, RPC=$RPC_HTTP (no conflict)"
else
  fail "HTTP ports conflict: sequencer=$SEQ_HTTP, RPC=$RPC_HTTP"
fi

echo ""

# ──────────────────────────────────────────────────────
# 8. Docker .env check
# ──────────────────────────────────────────────────────
echo "Docker .env:"

if [[ -f .env ]]; then
  IMAGE=$(grep 'CDK_ERIGON_IMAGE=' .env | head -1 | cut -d'=' -f2-)
  pass ".env exists (image: ${IMAGE:-not set})"
else
  warn ".env not found — copy from env.example: cp env.example .env"
fi

echo ""

# ──────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────
echo "──────────────────────────────────────"
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
  echo -e "${GREEN}All checks passed.${NC}"
elif [[ $ERRORS -eq 0 ]]; then
  echo -e "${YELLOW}Passed with $WARNINGS warning(s).${NC}"
else
  echo -e "${RED}Failed with $ERRORS error(s) and $WARNINGS warning(s).${NC}"
fi
echo "──────────────────────────────────────"

exit $ERRORS
