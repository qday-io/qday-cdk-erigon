# Node Startup Guide (Usage)

This document explains how to start the two node types of the qday2-testnet using Docker Compose:

- **Sequencer node**: the sole block producer, which also runs the datastream server that RPC nodes sync from.
- **RPC node**: a read-only node that syncs blocks from the sequencer's datastream. It does not produce blocks or keep a local txpool; it forwards transactions to the sequencer via the tx-pool-manager.

The two nodes are managed by two separate compose files and can be deployed on the same host or split across hosts.

> All commands assume you have `cd`'d into `qday/dynamic-configs/`.

---

## 0. Prerequisites

### 0.0 External L1 + cdk-node (deployed by other projects)

This stack is a zkrollup that settles to an **external L1** and is orchestrated by an **external cdk-node**. Neither is started by this repo — both must already be running and reachable:

- **L1**: note its JSON-RPC endpoint and chain id → set `L1_RPC_URL` / `L1_CHAIN_ID` in `.env`. Copy the L1 contract addresses and `l1-first-block` from the L1 deploy's `deploy_output.json` / `create_rollup_output.json` into both `dynamic-validium.yaml` and `dynamic-validium-rpc.yaml`.
- **cdk-node**: consumes the sequencer datastream (`:6900`) and posts batches to L1. Operated externally; just make sure it can reach the sequencer's `:6900` and `:8123`.

This stack runs neither **cdk-dac** (data availability is on L1) nor **AggLayer** (settlement is direct to L1).

### 0.1 Prepare the `.env` file

```bash
cd qday/dynamic-configs
cp .env.example .env
```

**Purpose**: `.env` is auto-read by docker compose and parameterizes the image tag, host ports, and the two endpoints that point the RPC node at the sequencer.

**Notes**:

- The `cp` is required; compose does not read `.env.example` automatically.
- If the RPC node and sequencer run on the **same host**, the defaults in `.env.example` (`SEQUENCER_DATASTREAMER_URL=host.docker.internal:6900`, `SEQUENCER_RPC_URL=http://host.docker.internal:8545`) work as-is. `host.docker.internal` resolves to the Docker host from inside the container.
- If the RPC node runs on a **different host**, update the two values to the sequencer host's real address, e.g.:
  ```
  SEQUENCER_DATASTREAMER_URL=10.0.0.5:6900
  SEQUENCER_RPC_URL=http://10.0.0.5:8545
  ```
- Do **not** change `POOL_MANAGER_URL` (`http://tx-pool-manager:8545`) to a host port — it is how the RPC container reaches the pool manager over the Docker network, so it must use the container name plus the in-container port `8545`, not the `POOL_MANAGER_PORT` value in `.env` (which is the host-mapped port).

### 0.2 Port reference

| Service | In-container port | `.env` default host port | Purpose |
|---------|-------------------|--------------------------|---------|
| Sequencer HTTP RPC | 8123 | `SEQUENCER_RPC_PORT=8545` | JSON-RPC + WebSocket |
| Sequencer Datastream | 6900 | `SEQUENCER_DATASTREAM_PORT=6900` | Block stream for RPC nodes |
| RPC Node HTTP RPC | 8124 | `RPC_PORT=8546` | JSON-RPC + WebSocket |
| Pool Manager JSON-RPC | 8545 | `POOL_MANAGER_PORT=8547` | Receives `eth_sendRawTransaction` |

> Host ports are controlled by `.env`; in-container ports are fixed by the compose/yaml files. Cross-host traffic uses host ports; intra-container traffic uses in-container ports.

### 0.3 Pull images

```bash
docker compose pull
docker compose -f docker-compose.rpc.yml pull
```

**Purpose**: pre-pull the cdk-erigon image, the zkevm-pool-manager image, and the postgres image so `up` does not block on downloads and time out.

**Notes**:

- `CDK_ERIGON_IMAGE` (default `ghcr.io/qday-io/qday-cdk-erigon:qday-v2.61.19-sovereign`) must be reachable from `.env`. If pulls time out, configure a registry mirror or build locally with `Dockerfile.local`.
- Both compose files share `CDK_ERIGON_IMAGE`, so a single pull is reused by both stacks.

---

## 1. Start the Sequencer Node

```bash
docker compose up -d
```

**Purpose**: starts the sequencer service (`qday2-sequencer` container) using the default `docker-compose.yml`.

- Loads `dynamic-validium.yaml` as the run config.
- Injects `CDK_ERIGON_SEQUENCER=1` so cdk-erigon runs in sequencer mode (block production + datastream server).
- Injects the initial batch via `--zkevm.initial-batch.config=/config/empty-batch.json` (the `firstBatchData` from the zkEVM contract deployment).
- Mounts `./datadir-validium` as `/data` for chain state.
- Maps host `8545→8123` (RPC) and `6900→6900` (datastream).

**Notes**:

- The **sequencer must start first**; the RPC node and pool manager both depend on its datastream / RPC.
- `-d` runs detached; drop it to stream logs in the foreground for first-time debugging.
- The sequencer is a **single instance** — it is the only block producer for the chain. Do not scale sequencer replicas.
- The entrypoint auto-`chown`s `datadir-validium/` to UID 1000 and drops privileges on first start. **Do not manually change ownership** of that directory.
- On first start the node initializes genesis from `dynamic-qday2-testnet-{chainspec,conf,allocs}.json`. If you edit any of these three files, run `./cleanup.sh` to wipe the old datadir first, otherwise a genesis-hash mismatch will make the node refuse to start.

### 1.1 Watch sequencer logs

```bash
docker compose logs -f sequencer
```

A line like `HTTP endpoint opened http://0.0.0.0:8123` means the RPC is ready.

### 1.2 Verify the sequencer

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

Should return `{"jsonrpc":"2.0","id":1,"result":"0x..."}` with `result` growing over time (one block every 5s).

You can also use the built-in healthcheck:

```bash
docker compose ps
```

A `healthy` STATUS means the sequencer's JSON-RPC is up.

---

## 2. Start the RPC Node

The RPC stack is defined in `docker-compose.rpc.yml` and contains three services: `rpc`, `tx-pool-manager`, and `pool-db`.

```bash
docker compose -f docker-compose.rpc.yml up -d
```

**Purpose**: brings up the whole RPC stack at once.

- **pool-db** (postgres:15): the pool manager's persistence backend; stores the queued-tx backlog.
- **tx-pool-manager** (`zkevm-pool-manager`): receives `eth_sendRawTransaction` forwarded by the RPC node, queues it, and forwards it to the sequencer's HTTP RPC.
- **rpc** (cdk-erigon, read-only mode): syncs blocks from the sequencer datastream; runs with `txpool.disable=true`; `eth_sendRawTransaction` is redirected to `tx-pool-manager:8545`.

The dependency order is enforced by compose `depends_on`: `pool-db` healthy → `tx-pool-manager` started → `rpc` started.

**Notes**:

- Before starting, confirm `SEQUENCER_DATASTREAMER_URL` and `SEQUENCER_RPC_URL` in `.env` point to a **running** sequencer, otherwise the rpc node will retry forever and the pool manager's forwards will fail.
- The RPC node uses its own datadir `datadir-validium-rpc/`, independent of the sequencer; co-locating on the same host is safe.
- The RPC node's internal ports are offset from the sequencer (`8552`/`30305`/`42070`, see `dynamic-validium-rpc.yaml`) to avoid p2p/engine port collisions when sharing a host with the sequencer.
- `tx-pool-manager`'s `SEQUENCER_RPC_URL` comes from the same `.env`, so on cross-host deployments one change applies to both the rpc node and the pool manager.

### 2.1 Watch RPC node logs

```bash
docker compose -f docker-compose.rpc.yml logs -f rpc
docker compose -f docker-compose.rpc.yml logs -f tx-pool-manager
```

A healthy sync shows `StageSync` progress advancing in the rpc logs and `eth_blockNumber` catching up to the sequencer.

### 2.2 Verify the RPC node

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8546
```

The returned block number should equal the sequencer's, or be slightly behind (still catching up).

```bash
docker compose -f docker-compose.rpc.yml ps
```

All three services should be `Up` / `healthy`.

### 2.3 Submit transactions through the RPC node

The RPC node neither produces blocks nor queues locally; the `eth_sendRawTransaction` flow is:

```
client -> rpc(:8546) -> tx-pool-manager(:8545) -> sequencer(:8545)
```

Clients can submit directly to the RPC node with no changes:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["0x..."],"id":1}' \
  http://localhost:8546
```

**Notes**:

- If `tx-pool-manager` is down or `SEQUENCER_RPC_URL` is unreachable, submissions return a forwarding error, but **read-only queries** on the RPC node keep working.
- If you do not need the pool manager (want the RPC node to forward straight to the sequencer), remove `--zkevm.pool-manager-url` from the rpc service in the compose file; it will then fall back to `--zkevm.l2-sequencer-rpc-url` and connect to the sequencer directly.

---

## 3. Same-Host vs Cross-Host Deployment

### Same host (default, simplest)

The `.env.example` defaults work:

```
SEQUENCER_DATASTREAMER_URL=host.docker.internal:6900
SEQUENCER_RPC_URL=http://host.docker.internal:8545
```

The two compose stacks run on separate networks and reach each other via `host.docker.internal` (the compose files add `host.docker.internal:host-gateway`), coming back to the host ports.

**Note**: both stacks map host ports, so make sure `8545`/`8546`/`8547`/`6900` are not taken by other processes.

### Cross host

- Sequencer host: run only `docker compose up -d`; ensure `8545` and `6900` are reachable from the RPC host (open the firewall).
- RPC host: in `.env`, point the two URLs at the sequencer host IP, then `docker compose -f docker-compose.rpc.yml up -d`.
- You can scale out multiple RPC hosts, each pointing at the same single sequencer.

---

## 4. Stopping and Cleaning Up

### Stop

```bash
# Stop the RPC stack
docker compose -f docker-compose.rpc.yml down

# Stop the sequencer
docker compose down
```

`down` removes containers and networks but **keeps** the datadirs and pool-db data, so the next `up` resumes syncing.

### Full reset (wipe chain data)

```bash
./cleanup.sh
```

**Purpose**: deletes `datadir-validium/`, `datadir-validium-rpc/`, and `data/pool-db/` so the next start reinitializes from genesis.

**Notes**:

- Use this only when you need to change genesis (edited chainspec/conf/allocs) or restart from block 0.
- After cleanup, **start the sequencer first** (it rebuilds the chain), then the RPC stack.
- Cleanup discards all chain history and is irreversible.

---

## 5. Quick Troubleshooting

| Symptom | Check |
|---------|-------|
| Sequencer won't start, logs report genesis hash mismatch | Datadir not wiped after a genesis edit; run `./cleanup.sh` and restart |
| RPC node `eth_blockNumber` stuck at 0 | `SEQUENCER_DATASTREAMER_URL` unreachable; verify sequencer `:6900` is reachable and sequencer is `healthy` |
| `eth_sendRawTransaction` returns a forwarding error | `tx-pool-manager` not ready or `SEQUENCER_RPC_URL` wrong; check `docker compose -f docker-compose.rpc.yml logs tx-pool-manager` |
| Port already in use | Change the matching `*_PORT` in `.env`, or stop the occupying process |
| Image pull timeout | Configure a registry mirror, or build locally with `Dockerfile.local` and update `CDK_ERIGON_IMAGE` |

More in [troubleshooting.md](./troubleshooting.md).

---

## 6. Command Reference

```bash
# Prepare
cp .env.example .env
docker compose pull
docker compose -f docker-compose.rpc.yml pull

# Start sequencer
docker compose up -d
docker compose logs -f sequencer

# Start RPC stack
docker compose -f docker-compose.rpc.yml up -d
docker compose -f docker-compose.rpc.yml logs -f rpc

# Verify
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545   # sequencer
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8546   # rpc node

# Stop
docker compose -f docker-compose.rpc.yml down
docker compose down

# Full reset
./cleanup.sh
```

## 7. See Also

- [Sequencer config field reference](./dynamic-validium.md)
- [RPC node config field reference](./dynamic-validium-rpc.md)
- [Quick-start run guide](../dynamic-configs/README-validium.md)
- [Troubleshooting guide](./troubleshooting.md)
- [Upgrade guide](./upgrade-guide.md)
