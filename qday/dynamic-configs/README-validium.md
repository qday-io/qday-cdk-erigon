# Validium Chain (cdk-erigon only; external L1 + cdk-node)

zkEVM L2 that settles to an external L1 and is orchestrated by an external cdk-node, deployed by other projects. This stack runs the cdk-erigon sequencer + RPC node (+ optional tx pool manager) and does **not** include cdk-dac or AggLayer.

## Prerequisites (external projects)

Before starting this stack, the following must already be running and reachable:

- **L1** — an EVM L1 with the CDK rollup contracts deployed (rollup manager, zkevm, sequencer, GER manager, POL token). Note its JSON-RPC endpoint and chain id for `.env` (`L1_RPC_URL`, `L1_CHAIN_ID`), and copy the contract addresses + `l1-first-block` from its `deploy_output.json` / `create_rollup_output.json` into both yaml configs.
- **cdk-node** — the Polygon CDK node that consumes the sequencer's datastream (`:6900`) and posts batches to the L1. It is operated externally; no configuration is required in this repo beyond exposing the sequencer datastream + RPC to it.

This stack does **not** run cdk-dac (data availability is on L1 via cdk-node) or AggLayer (settlement is direct to L1).

## Docker Compose

The compose stack is split by role:

- `docker-compose.yml` — **sequencer** node only (block producer + datastream server)
- `docker-compose.rpc.yml` — **RPC** node + tx pool manager (read-only, syncs from the sequencer datastream)

```bash
cd qday/dynamic-configs
cp .env.example .env

# Sequencer host
docker compose up                     # uses docker-compose.yml by default

# RPC host (set SEQUENCER_DATASTREAMER_URL in .env to the sequencer endpoint)
docker compose -f docker-compose.rpc.yml up
```

When the RPC node runs on the same host as the sequencer, the default
`SEQUENCER_DATASTREAMER_URL=host.docker.internal:6900` works as-is.

If `auth.docker.io ... i/o timeout`, use **native run** (no Docker):

```bash
# Terminal 1 — sequencer
chmod +x qday/dynamic-configs/start-sequencer.sh
./qday/dynamic-configs/start-sequencer.sh

# Terminal 2 — RPC (after sequencer is up)
chmod +x qday/dynamic-configs/start-rpc.sh
./qday/dynamic-configs/start-rpc.sh
```

## Start sequencer

```bash
make cdk-erigon

CDK_ERIGON_SEQUENCER=1 ./build/bin/cdk-erigon \
  --config=./qday/dynamic-configs/dynamic-validium.yaml
```

## Start RPC node (follows the sequencer datastream; also syncs L1)

```bash
./build/bin/cdk-erigon \
  --config=./qday/dynamic-configs/dynamic-validium-rpc.yaml
```

Point `zkevm.l2-datastreamer-url` to the sequencer's datastream endpoint
(`<host>:<data-stream-port>`).

## Sending transactions to an RPC node

The RPC node has no txpool and produces no blocks. When a client sends
`eth_sendRawTransaction` to the RPC node, it transparently **forwards** the tx to
the sequencer's HTTP RPC, where it is queued and sealed. Clients need no change.

Two URLs serve different roles — both must point at the sequencer:

- `zkevm.l2-datastreamer-url` (`:6900`) — **read**: sync blocks from the sequencer
- `zkevm.l2-sequencer-rpc-url` (`:8123`) — **write**: forward txs to the sequencer

Without `zkevm.l2-sequencer-rpc-url` the RPC node still syncs, but submitting a
transaction to it fails (forwards to an empty URL).

### With a tx pool manager (docker-compose.rpc.yml)

`docker-compose.rpc.yml` runs an [zkevm-pool-manager](https://github.com/0xPolygon/zkevm-pool-manager)
alongside the RPC node. Instead of forwarding each tx straight to the sequencer,
the RPC node redirects `eth_sendRawTransaction` to the pool manager, which queues
txs in its own Postgres DB and forwards them to the sequencer:

```
client -> rpc (eth_sendRawTransaction) -> tx-pool-manager -> sequencer
```

RPC node flags (set in the compose file):

- `txpool.disable: true` — the RPC node keeps no local txpool
- `zkevm.pool-manager-url: http://tx-pool-manager:8545` — redirect target

When `zkevm.pool-manager-url` is set it takes precedence over
`zkevm.l2-sequencer-rpc-url` for `eth_sendRawTransaction`.

Pool manager config lives in `poolmanager.toml`; `Sender.SequencerURL` /
`Monitor.L2NodeURL` point at the sequencer and can be overridden with
`SEQUENCER_RPC_URL` in `.env`.

## Key flags

- `zkevm.skip-l1-sync: false` — L1 sync is enabled; the node reads batches / fork history from the external L1. Set to `true` only for standalone dev without an L1 (then also set `zkevm.initial-fork-id: 12`).
- `zkevm.executor-strict: false` — no zkevm-prover/executor required (sequencer only)

## RPC

```bash
# Sequencer
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8123

# RPC node
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8124
```
