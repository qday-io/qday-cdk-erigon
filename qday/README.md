# QDay  cdk-erigon Deployment

QDay is a customizable CDK chain deployment based on cdk-erigon, a fork of Erigon optimized for Polygon Hermez zkEVM / Polygon CDK chains.

This directory contains the complete configuration, documentation, and tooling for running the **qday2-testnet Validium** — a zkEVM L2 that settles to an external L1 and is orchestrated by an external cdk-node. The L1 and cdk-node are deployed and operated by other projects; this stack runs only the cdk-erigon side (sequencer + RPC node + tx pool manager) and does **not** include cdk-dac or AggLayer.

## Architecture

```
                          external projects (not in this repo)
┌──────────────────────────────────────────────────────────────────┐
│  L1 (chain id 31337)          cdk-node                            │
│  - rollup manager             - consumes sequencer datastream     │
│  - zkevm / sequencer ctrs     - posts batches to L1               │
│  - GER manager                - syncs state from L1               │
└──────────────▲───────────────────────▲───────────────────────────┘
               │                       │ datastream :6900 / RPC :8123
               │ batches               │
┌──────────────┴───────────────────────┴───────────────────────────┐
│                        this qday stack                           │
│                                                                  │
│  ┌──────────────────┐    datastream     ┌──────────────────────┐  │
│  │    Sequencer      │ ◄────:6900────── │      RPC Node        │  │
│  │                   │                  │                      │  │
│  │  Block producer   │                  │  Read-only queries    │  │
│  │  Datastream server│                  │  Tx forwarding        │  │
│  │  RPC :8123        │ ────tx fwd───►  │  Sync from datastream │  │
│  │  Txpool           │                  │  No local txpool      │  │
│  └──────────────────┘                  └───────────┬──────────┘  │
│                                                  │              │
│                                                  ▼              │
│                                        ┌──────────────────────┐ │
│                                        │  zkevm-pool-manager   │ │
│                                        │  (optional)           │ │
│                                        │  Queue & forward txs  │ │
│                                        └──────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Rollup mode (no cdk-dac)**: Data availability is on the external L1 via cdk-node; no Data Availability Committee is used. The sequencer's datastream is the live block feed consumed by both RPC nodes and the cdk-node.
- **Direct L1 settlement (no AggLayer)**: Batches settle to the external L1 rollup manager directly; the chain does not participate in AggLayer aggregation. The GER manager contract address is still configured on L1 for exit-root handling.
- **External L1 + cdk-node**: The L1 chain and the cdk-node are deployed and operated by other projects. This stack only configures cdk-erigon to connect to them — fill in `L1_RPC_URL` / `L1_CHAIN_ID` in `.env` and paste the L1 contract addresses + `l1-first-block` from the external deploy's `deploy_output.json` / `create_rollup_output.json` into the two yaml configs.
- **No external executor**: Uses virtual counters (`zkevm.disable-virtual-counters: true`) — no zkevm-prover required
- **Port isolation**: RPC node uses distinct ports (`:8124`, `:9091`, etc.) to co-exist with sequencer on the same host

## Directory Layout

```
qday/
├── README.md                              ← This file
├── docs/
│   ├── dynamic-validium.md                ← Sequencer config field reference
│   ├── dynamic-validium-rpc.md            ← RPC node config field reference
│   ├── troubleshooting.md                 ← Common issues and solutions
│   └── upgrade-guide.md                   ← How to upgrade versions
├── dynamic-configs/
│   ├── .env.example                       ← Docker environment template
│   ├── README-validium.md                 ← Quick-start run guide
│   ├── Dockerfile.local                   ← Build lightweight Docker image
│   ├── docker-entrypoint.sh               ← Docker entrypoint (chown + drop user)
│   ├── docker-compose.yml                 ← Sequencer Docker Compose stack
│   ├── docker-compose.rpc.yml             ← RPC node + pool manager stack
│   ├── dynamic-validium.yaml              ← Sequencer run config
│   ├── dynamic-validium-rpc.yaml          ← RPC node run config
│   ├── dynamic-qday2-testnet-chainspec.json ← Chain specification (chainId=44005)
│   ├── dynamic-qday2-testnet-conf.json    ← Genesis config
│   ├── dynamic-qday2-testnet-allocs.json  ← Genesis allocations
│   ├── empty-batch.json                   ← Initial batch injection
│   ├── poolmanager.toml                   ← Pool manager config
│   ├── start-sequencer.sh                 ← Native sequencer launcher
│   ├── start-rpc.sh                       ← Native RPC node launcher
│   ├── start-all.sh                       ← Launch both nodes together
│   ├── health-check.sh                    ← Node health verification
│   ├── cleanup.sh                         ← Reset data directories
│   └── validate-config.sh                 ← Validate config files
```

## Quick Start

### Docker (recommended)

```bash
cd qday/dynamic-configs
cp .env.example .env

# Start sequencer
docker compose up -d

# Start RPC node (in another terminal or same host)
docker compose -f docker-compose.rpc.yml up -d
```

### Native

```bash
# Build the binary (from repo root)
make cdk-erigon

# Start both sequencer and RPC
./qday/dynamic-configs/start-all.sh
```

Or start them individually:

```bash
./qday/dynamic-configs/start-sequencer.sh   # Terminal 1
./qday/dynamic-configs/start-rpc.sh         # Terminal 2
```

### Verify

```bash
# Sequencer
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8123

# RPC node
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8124
```

Both should return `{"jsonrpc":"2.0","id":1,"result":"0xabe5"}` (chainId 44005).

## Network Info

| Property | Value |
|----------|-------|
| Network name | qday2-testnet |
| Chain ID | 44005 (0xabe5) |
| Consensus | Ethash (L2 only) |
| Virtual currency | ETH (18 decimals) |
| Default gas price | 1 gwei |
| Block seal time | 5s |
| Datastream version | 2 (BigEndian) |

### Port Assignments

| Service | Port | Purpose |
|---------|------|---------|
| Sequencer HTTP RPC | 8123 | JSON-RPC, WebSocket |
| Sequencer Datastream | 6900 | Block data stream for RPC nodes |
| Sequencer Private API | 9090 | Internal gRPC API |
| Sequencer P2P | 30303 | Peer discovery |
| Sequencer Engine API | 8551 | Auth RPC (CL) |
| RPC Node HTTP RPC | 8124 | JSON-RPC, WebSocket |
| RPC Node WebSocket | 8125 | Dedicated WS port |
| RPC Node Private API | 9091 | Internal gRPC API |
| RPC Node P2P | 30305 | Offset from sequencer |
| RPC Node Engine API | 8552 | Offset from sequencer |
| RPC Node Torrent | 42070 | Offset from sequencer 42069 |
| Pool Manager JSON-RPC | 8546 | eth_sendRawTransaction endpoint |

### Pre-deployed Contracts

| Address | Contract |
|---------|----------|
| `0xD9E2C3...` | PolygonZkEVMDeployer |
| `0xA98eD9...` | ProxyAdmin |
| `0x27DAeD...` | PolygonZkEVMBridge (proxy) |
| `0x6d1ed7...` | PolygonZkEVMBridge (implementation) |
| `0xa40d5f...` | PolygonZkEVMGlobalExitRootL2 (proxy) |
| `0x6AeeF9...` | PolygonZkEVMGlobalExitRootL2 (implementation) |
| `0x3e7795...` | PolygonZkEVMTimelock |

### Funded Accounts

| Address | Balance | Nonce |
|---------|---------|-------|
| `0xe85927...` | 100 ETH | 8 |
| `0xf39Fd6...` | 1,000,000,000 ETH | 0 |

## Developer Workflow

```bash
# Validate all config files before starting
./qday/dynamic-configs/validate-config.sh

# Check node health
./qday/dynamic-configs/health-check.sh

# Reset data (wipe chain state, start fresh)
./qday/dynamic-configs/cleanup.sh

# Run the full stack
./qday/dynamic-configs/start-all.sh
```

## External L1 + cdk-node wiring

The stack defaults to connecting to an external L1 and external cdk-node (deployed by other projects). To point it at your external deployment:

1. In `.env`, set `L1_RPC_URL` to the external L1 JSON-RPC endpoint and `L1_CHAIN_ID` to the L1 chain id. (Compose passes both to cdk-erigon as command-line overrides.)
2. In **both** `dynamic-validium.yaml` and `dynamic-validium-rpc.yaml`, paste the L1 contract addresses and `l1-first-block` from the external deploy's `deploy_output.json` / `create_rollup_output.json`:
   - `zkevm.address-sequencer`, `zkevm.address-zkevm`, `zkevm.address-rollup`, `zkevm.address-ger-manager`, `zkevm.l1-matic-contract-address`, `zkevm.l1-first-block`
3. Confirm `zkevm.skip-l1-sync: false` (already the default) and that `zkevm.initial-fork-id` is unset — fork history comes from L1 sync.
4. Optionally set `zkevm.l1-contract-address-check: true` to validate the addresses at startup.

### Falling back to standalone (no L1) mode

To run the chain without the external L1 / cdk-node (e.g. for local dev), edit both `dynamic-validium.yaml` and `dynamic-validium-rpc.yaml`:

1. Set `zkevm.skip-l1-sync: true`
2. Set `zkevm.initial-fork-id: 12` (required when L1 sync is skipped)
3. Ignore the L1 contract addresses / `l1-first-block` (they are not read)

## See Also

- [Sequencer Config Reference](docs/dynamic-validium.md)
- [RPC Node Config Reference](docs/dynamic-validium-rpc.md)
- [Quick-Start Run Guide](dynamic-configs/README-validium.md)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [Upgrade Guide](docs/upgrade-guide.md)
- [Main cdk-erigon README](../README.md)
