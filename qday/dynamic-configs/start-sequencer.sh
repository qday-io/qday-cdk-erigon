#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ ! -x "$ROOT/build/bin/cdk-erigon" ]]; then
  echo "Binary not found. Run from repo root: make cdk-erigon"
  exit 1
fi

export CDK_ERIGON_SEQUENCER=1
exec "$ROOT/build/bin/cdk-erigon" \
  --config="$ROOT/qday/dynamic-configs/dynamic-validium.yaml" \
  --datadir="$ROOT/qday/dynamic-configs/datadir-validium" \
  --zkevm.initial-batch.config="$ROOT/qday/dynamic-configs/empty-batch.json"
