#!/usr/bin/env bash
# =============================================================================
# cutover.sh — 切换:停旧 sequencer,恢复节点转正
# =============================================================================
# 执行内容:
#   1. 先对恢复节点(8645 端口)跑 verify-recovery.sh,不通过则中止
#   2. 停止旧 sequencer 容器(qday2-sequencer,数据卷保留不动)
#   3. 恢复节点切到标准端口 8545/6900,摘掉 L1_SYNC_STOP_BATCH 关卡,
#      并把空交易池等待从 0s 改回 250ms
#      (恢复已完成,节点转为正常 sequencer,从 L1 顶端继续开新 batch)
#   4. 重启 cdk 组件(aggregator / sequence-sender / validator)
#   5. 对标准端口再跑一次验收
#
# 用法:
#   ./cutover.sh          # 交互确认后执行
#   ./cutover.sh --yes    # 跳过确认
#
# 回滚:docker start qday2-sequencer 即可回到切换前状态(链仍是卡住的,
# 但不会更坏),然后排查恢复节点问题后重试。
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

# ---- 1. 切换前验收(对恢复端口)---------------------------------------------
echo "==> 1/5 切换前验收(恢复节点 :${RECOVER_RPC_PORT:-8645})"
if ! ./verify-recovery.sh "http://127.0.0.1:${RECOVER_RPC_PORT:-8645}"; then
  echo "验收未通过,中止切换。"
  exit 1
fi

if [[ $CONFIRM -eq 1 ]]; then
  echo
  echo "即将执行:停止 $OLD_CONTAINER,把 $RECOVER_CONTAINER 切到 :$STD_RPC_PORT/$STD_DATASTREAM_PORT,摘掉 stop-batch 关卡,并把空池等待改回 250ms。"
  read -r -p "确认继续? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "已取消。"; exit 0; }
fi

# ---- 2. 停旧节点 ------------------------------------------------------------
echo "==> 2/5 停止旧 sequencer ($OLD_CONTAINER)"
if docker ps --format '{{.Names}}' | grep -qx "$OLD_CONTAINER"; then
  docker stop "$OLD_CONTAINER"
else
  echo "    ($OLD_CONTAINER 不在运行,跳过)"
fi

# ---- 3. 恢复节点转正 ---------------------------------------------------------
echo "==> 3/5 恢复节点切到标准端口 $STD_RPC_PORT/$STD_DATASTREAM_PORT,L1_SYNC_STOP_BATCH=0,空池等待=250ms"
# 空池等待写回 .env:之后按 README 把 L1_SYNC_START_BLOCK 改为 0 再 up,
# 不会退回 0s(0s 只用于重放历史空块)。
if [[ -f .env ]] && grep -q '^SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=' .env; then
  sed -i.bak 's|^SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=.*|SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=250ms|' .env
  rm -f .env.bak
elif [[ -f .env ]]; then
  printf '\nSEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=250ms\n' >> .env
fi
# shell 环境变量优先于 .env,实现不改 stop-batch 文件值的切换
RECOVER_RPC_PORT="$STD_RPC_PORT" \
RECOVER_DATASTREAM_PORT="$STD_DATASTREAM_PORT" \
L1_SYNC_STOP_BATCH=0 \
SEQUENCER_TIMEOUT_ON_EMPTY_TX_POOL=250ms \
docker compose -f docker-compose.recover.yml --env-file .env up -d

echo "    等待节点健康检查通过..."
for i in $(seq 1 20); do
  if curl -sf -m 5 -X POST "http://127.0.0.1:$STD_RPC_PORT" -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | grep -q result; then
    break
  fi
  [[ $i -eq 20 ]] && { echo "节点 RPC 未就绪,请查看: docker logs $RECOVER_CONTAINER"; exit 1; }
  sleep 3
done

# ---- 4. 重启 cdk 组件 --------------------------------------------------------
echo "==> 4/5 重启 cdk 组件"
for c in $CDK_COMPONENTS; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    docker restart "$c" && echo "    $c 已重启"
  else
    echo "    ($c 不存在,跳过)"
  fi
done

# ---- 5. 切换后验收(对标准端口)---------------------------------------------
echo "==> 5/5 切换后验收(:$STD_RPC_PORT)"
./verify-recovery.sh "http://127.0.0.1:$STD_RPC_PORT"

echo
echo "切换完成。后续观察点:"
echo "  - aggregator: 不再报 BatchL2Data mismatch,出现 settlement tx 日志"
echo "  - L1 verified batch 应从 $ANCHOR_BATCH 推进到 $EXPECTED_BATCH"
echo "  - 稳定运行后,把 .env 中 L1_SYNC_START_BLOCK 改为 0 并重启本节点"
echo "    (退出 L1 recovery 模式),旧数据卷确认无问题后再清理"
