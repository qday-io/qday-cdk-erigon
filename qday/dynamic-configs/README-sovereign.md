# Minimal Sovereign Chain (cdk-erigon only)

Standalone zkEVM L2 without L1, AggLayer, cdk-node, or cdk-dac.

## Docker Compose

The compose stack is split by role:

- `docker-compose.yml` — **sequencer** node only (block producer + datastream server)
- `compose.yml` — **RPC** node only (read-only, syncs from the sequencer datastream)

```bash
cd zk/examples/dynamic-configs
cp .env.example .env

# Sequencer host
docker compose up                     # uses docker-compose.yml by default

# RPC host (set SEQUENCER_DATASTREAMER_URL in .env to the sequencer endpoint)
docker compose -f compose.yml up
```

When the RPC node runs on the same host as the sequencer, the default
`SEQUENCER_DATASTREAMER_URL=host.docker.internal:6900` works as-is.

If `auth.docker.io ... i/o timeout`, use **native run** (no Docker):

```bash
# Terminal 1 — sequencer
chmod +x zk/examples/dynamic-configs/start-sequencer.sh
./zk/examples/dynamic-configs/start-sequencer.sh

# Terminal 2 — RPC (after sequencer is up)
chmod +x zk/examples/dynamic-configs/start-rpc.sh
./zk/examples/dynamic-configs/start-rpc.sh
```

## Start sequencer

```bash
make cdk-erigon

CDK_ERIGON_SEQUENCER=1 ./build/bin/cdk-erigon \
  --config=./zk/examples/dynamic-configs/dynamic-sovereign.yaml
```

## Start RPC node (follows sovereign sequencer, no L1 required)

```bash
./build/bin/cdk-erigon \
  --config=./zk/examples/dynamic-configs/dynamic-sovereign-rpc.yaml
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

- `zkevm.skip-l1-sync: true` — disable all L1 sync stages (sequencer **and** RPC node)
- `zkevm.initial-fork-id: 12` — bootstrap fork history locally (required with skip-l1-sync)
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
