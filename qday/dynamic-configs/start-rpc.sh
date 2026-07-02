#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ ! -x "$ROOT/build/bin/cdk-erigon" ]]; then
  echo "Binary not found. Run from repo root: make cdk-erigon"
  exit 1
fi

# Default: local sequencer datastream on host
DATASTREAM_URL="${L2_DATASTREAM_URL:-127.0.0.1:6900}"

exec "$ROOT/build/bin/cdk-erigon" \
  --config="$ROOT/qday/dynamic-configs/dynamic-validium-rpc.yaml" \
  --datadir="$ROOT/qday/dynamic-configs/datadir-validium-rpc" \
  --zkevm.l2-datastreamer-url="$DATASTREAM_URL"
