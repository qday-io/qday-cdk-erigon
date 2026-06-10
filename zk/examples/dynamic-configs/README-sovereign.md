# Minimal Sovereign Chain (cdk-erigon only)

Standalone zkEVM L2 without L1, AggLayer, cdk-node, or cdk-dac.

## Start

```bash
make cdk-erigon

CDK_ERIGON_SEQUENCER=1 ./build/bin/cdk-erigon \
  --config=./zk/examples/dynamic-configs/dynamic-sovereign.yaml
```

## Key flags

- `zkevm.skip-l1-sync: true` — disable all L1 sync stages
- `zkevm.initial-fork-id: 12` — bootstrap fork history locally (required with skip-l1-sync)
- `zkevm.executor-strict: false` — no zkevm-prover/executor required

## RPC

```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8123
```
