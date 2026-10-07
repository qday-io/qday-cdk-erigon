#!/usr/bin/env bash
# =============================================================================
# verify-recovery.sh — L1 重建结果的验收检查
# =============================================================================
# 对恢复节点依次检查:
#   1. zkevm_batchNumber 已达到 EXPECTED_BATCH(L1 最新 virtual batch)
#   2. ANCHOR_BATCH 的 stateRoot 等于 L1 已验证锚点 ANCHOR_STATE_ROOT
#      (数学上证明重放正确)
#   3. SPOT_CHECK_BATCH 在节点上存在且包含区块(旧节点上它曾是 null)
#   4. SPOT_CHECK_BATCH 的 witness 可以生成(aggregator 需要)
#   5. zkevm_virtualBatchNumber 与 L1 一致(L1 同步正常)
#
# 用法:
#   ./verify-recovery.sh [rpc-url]
# 参数默认从同目录 .env 读取;rpc-url 默认 http://127.0.0.1:${RECOVER_RPC_PORT}
#
# 依赖:bash、curl、grep、printf(不依赖 jq/python)
# 退出码:全部通过 0;任一失败 1
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---- 加载 .env(若存在)------------------------------------------------------
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

EXPECTED_BATCH="${EXPECTED_BATCH:?需要在 .env 中设置 EXPECTED_BATCH}"
ANCHOR_BATCH="${ANCHOR_BATCH:?需要在 .env 中设置 ANCHOR_BATCH}"
ANCHOR_STATE_ROOT="${ANCHOR_STATE_ROOT:?需要在 .env 中设置 ANCHOR_STATE_ROOT}"
SPOT_CHECK_BATCH="${SPOT_CHECK_BATCH:?需要在 .env 中设置 SPOT_CHECK_BATCH}"

RPC_URL="${1:-http://127.0.0.1:${RECOVER_RPC_PORT:-8645}}"

# ---- 工具函数 ---------------------------------------------------------------
rpc() { # rpc <method> <params-json>
  curl -sf -m 30 -X POST "$RPC_URL" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}

hex_of() { printf '0x%x' "$1"; } # 十进制 -> 0x 十六进制

lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; } # 兼容 bash 3.2

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILED=1; }

FAILED=0

echo "目标节点: $RPC_URL"
echo

# ---- 0. 连通性 --------------------------------------------------------------
echo "[0] 节点连通性"
if ! rpc eth_blockNumber '[]' >/dev/null 2>&1; then
  fail "无法连接 $RPC_URL,节点是否已启动?"
  echo; echo "验证未通过"; exit 1
fi
pass "RPC 可用"

# ---- 1. batch 高度 ----------------------------------------------------------
echo "[1] zkevm_batchNumber 应 >= $EXPECTED_BATCH"
resp="$(rpc zkevm_batchNumber '[]' || true)"
got="$(echo "$resp" | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || true)"
want="$(hex_of "$EXPECTED_BATCH")"
if [[ -n "$got" && $((got)) -ge $EXPECTED_BATCH ]]; then
  pass "batchNumber = $got ($((got)))"
else
  fail "batchNumber = ${got:-无结果},期望 >= $want ($EXPECTED_BATCH)(还在同步中?)"
fi

# ---- 2. stateRoot 锚点 -------------------------------------------------------
echo "[2] batch $ANCHOR_BATCH 的 stateRoot 应等于 L1 已验证锚点"
resp="$(rpc zkevm_getBatchByNumber "[\"$(hex_of "$ANCHOR_BATCH")\",false]" || true)"
got_root="$(echo "$resp" | grep -o '"stateRoot":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || true)"
if [[ -n "$got_root" && "$(lower "$got_root")" == "$(lower "$ANCHOR_STATE_ROOT")" ]]; then
  pass "stateRoot = $got_root"
else
  fail "stateRoot = ${got_root:-无结果},期望 $ANCHOR_STATE_ROOT"
  echo "         stateRoot 不一致 = 重放结果与 L1 已验证状态分叉,禁止切换!"
fi

# ---- 3. 抽查 batch 数据 ------------------------------------------------------
echo "[3] batch $SPOT_CHECK_BATCH 应存在且包含区块"
resp="$(rpc zkevm_getBatchByNumber "[\"$(hex_of "$SPOT_CHECK_BATCH")\",false]" || true)"
if echo "$resp" | grep -q '"result":null'; then
  fail "batch $SPOT_CHECK_BATCH 为 null(旧节点的症状),恢复未覆盖该 batch"
elif echo "$resp" | grep -q '"blocks":\["0x'; then
  pass "batch $SPOT_CHECK_BATCH 存在且 blocks 非空"
else
  fail "batch $SPOT_CHECK_BATCH 存在但 blocks 为空,请人工检查: $resp"
fi

# ---- 4. witness 可生成 -------------------------------------------------------
echo "[4] batch $SPOT_CHECK_BATCH 的 witness 应可生成"
resp="$(rpc zkevm_getBatchWitness "[${SPOT_CHECK_BATCH},\"trimmed\"]" || true)"
if echo "$resp" | grep -q '"result":"0x'; then
  pass "witness 已生成"
else
  err="$(echo "$resp" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || true)"
  fail "witness 生成失败: ${err:-$resp}"
fi

# ---- 5. L1 virtual 一致性 ----------------------------------------------------
echo "[5] zkevm_virtualBatchNumber 应等于 $EXPECTED_BATCH"
resp="$(rpc zkevm_virtualBatchNumber '[]' || true)"
got="$(echo "$resp" | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || true)"
if [[ -n "$got" && $((got)) -eq $EXPECTED_BATCH ]]; then
  pass "virtualBatchNumber = $got ($((got)))"
else
  fail "virtualBatchNumber = ${got:-无结果},期望 $(hex_of "$EXPECTED_BATCH")($EXPECTED_BATCH)(L1 同步未完成?)"
fi

# ---- 汇总 --------------------------------------------------------------------
echo
if [[ $FAILED -eq 0 ]]; then
  echo "全部检查通过,可以执行切换: ./cutover.sh"
  exit 0
else
  echo "验证未通过,禁止切换。请根据上面的 FAIL 项排查(见 README.md 故障排查节)。"
  exit 1
fi
