#!/usr/bin/env bash
# =============================================================================
# cutover.sh — switch traffic: stop the old sequencer and promote the recovery node
# =============================================================================
# Steps:
#   1. Run verify-recovery.sh against the recovery node (port 8645); abort on failure
#   2. Stop the old sequencer container (qday2-sequencer); leave its data volume in place
#   3. Move the recovery node to the standard ports 8545/6900, clear L1_SYNC_STOP_BATCH,
#      and restore the empty-txpool wait from 0s to 250ms
#      (recovery is done; the node becomes a normal sequencer and opens new batches from the L1 tip)
#   4. Restart cdk components (aggregator / sequence-sender / validator)
#   5. Run verification again against the standard port
#
# Usage:
#   ./cutover.sh          # prompt before proceeding
#   ./cutover.sh --yes    # skip the prompt
#
# Rollback: `docker start qday2-sequencer` returns to the pre-cutover state (the chain
# is still stuck, but no worse). Fix the recovery node and retry.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

OLD_CONTAINER="${OLD_CONTAINER:-qday2-sequencer}"
RECOVER_CONTAINER="qday2-sequencer-recover"
STD_RPC_PORT="${STD_RPC_PORT:-8545}"
STD_DATASTREAM_PORT="${STD_DATASTREAM_PORT:-6900}"
CDK_COMPONENTS="${CDK_COMPONENTS:-cdk-aggregator cdk-sequence-sender cdk-validator}"

CONFIRM=1
[[ "${1:-}" == "--yes" ]] && CONFIRM=0

# ---- 1. Pre-cutover verification (recovery port) ---------------------------
echo "==> 1/5 pre-cutover verification (recovery node :${RECOVER_RPC_PORT:-8645})"
if ! ./verify-recovery.sh "http://127.0.0.1:${RECOVER_RPC_PORT:-8645}"; then
  echo "Verification failed; aborting cutover."
  exit 1
fi

if [[ $CONFIRM -eq 1 ]]; then
  echo
  echo "About to stop $OLD_CONTAINER, move $RECOVER_CONTAINER to :$STD_RPC_PORT/$STD_DATASTREAM_PORT, clear the stop-batch gate, and restore the empty-pool wait to 250ms."
  read -r -p "Continue? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Cancelled."; exit 0; }
fi

# ---- 2. Stop the old node ---------------------------------------------------
echo "==> 2/5 stopping old sequencer ($OLD_CONTAINER)"
if docker ps --format '{{.Names}}' | grep -qx "$OLD_CONTAINER"; then
  docker stop "$OLD_CONTAINER"
else
  echo "    ($OLD_CONTAINER is not running; skipping)"
fi

# ---- 3. Promote the recovery node -------------------------------------------
echo "==> 3/5 moving recovery node to $STD_RPC_PORT/$STD_DATASTREAM_PORT, L1_SYNC_STOP_BATCH=0, empty-pool wait=250ms"
# Persist the empty-pool wait in .env so a later restart with L1_SYNC_START_BLOCK=0
# does not fall back to 0s (0s is only for replaying historical empty blocks).
if [[ -f .env ]] && grep -q '^SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=' .env; then
  sed -i.bak 's|^SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=.*|SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=250ms|' .env
  rm -f .env.bak
elif [[ -f .env ]]; then
  printf '\nSEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=250ms\n' >> .env
fi
# Shell environment variables override .env, so the stop-batch value in the file stays unchanged.
RECOVER_RPC_PORT="$STD_RPC_PORT" \
RECOVER_DATASTREAM_PORT="$STD_DATASTREAM_PORT" \
L1_SYNC_STOP_BATCH=0 \
SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=250ms \
docker compose -f docker-compose.recover.yml --env-file .env up -d

echo "    waiting for the node health check..."
for i in $(seq 1 20); do
  if curl -sf -m 5 -X POST "http://127.0.0.1:$STD_RPC_PORT" -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | grep -q result; then
    break
  fi
  [[ $i -eq 20 ]] && { echo "Node RPC is not ready. See: docker logs $RECOVER_CONTAINER"; exit 1; }
  sleep 3
done

# ---- 4. Restart cdk components ----------------------------------------------
echo "==> 4/5 restarting cdk components"
for c in $CDK_COMPONENTS; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    docker restart "$c" && echo "    restarted $c"
  else
    echo "    ($c does not exist; skipping)"
  fi
done

# ---- 5. Post-cutover verification (standard port) --------------------------
echo "==> 5/5 post-cutover verification (:$STD_RPC_PORT)"
./verify-recovery.sh "http://127.0.0.1:$STD_RPC_PORT"

echo
echo "Cutover complete. Watch for:"
echo "  - aggregator: no more BatchL2Data mismatch; settlement tx logs appear"
echo "  - L1 verified batch should advance from $ANCHOR_BATCH to $EXPECTED_BATCH"
echo "  - after the chain is stable, set L1_SYNC_START_BLOCK=0 in .env and restart this node"
echo "    (leave L1 recovery mode). Remove the old data volume only after that is confirmed."
