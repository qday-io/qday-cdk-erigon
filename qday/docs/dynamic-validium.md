# dynamic-validium.yaml Reference

Sequencer node configuration for **qday2-testnet Validium** — block production and datastream server.

Config path: `qday/dynamic-configs/dynamic-validium.yaml`

How to start:

```bash
# Native
CDK_ERIGON_SEQUENCER=1 ./qday/dynamic-configs/start-sequencer.sh

# Docker
cd qday/dynamic-configs && docker compose up
```

---

## Usage Scenarios

| Scenario | Key settings |
|----------|--------------|
| **External L1 + cdk-node (current default)** | `zkevm.skip-l1-sync: false`, L1 addresses filled from `deploy_output.json` / `create_rollup_output.json`, `L1_RPC_URL` / `L1_CHAIN_ID` in `.env` |
| **Local standalone (no L1)** | `zkevm.skip-l1-sync: true` + `zkevm.initial-fork-id: 12` — no real L1 or prover required |
| **Docker deployment** | Compose overrides `--datadir=/data` and `--zkevm.initial-batch.config=/config/empty-batch.json`, and passes `--zkevm.l1-rpc-url` / `--zkevm.l1-chain-id` from `.env` |
| **With executor verification** | Set `zkevm.executor-urls` and `zkevm.executor-strict: true` |

---

## Field Reference

### Core Node

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `datadir` | Persistent directory for chain data, state, SMT, etc. | — | `./qday/dynamic-configs/datadir-validium` | Used when starting from repo root; Docker compose overrides to `/data` |
| `chain` | Chain name; dynamic chains use `dynamic-{network}` | — | `dynamic-qday2-testnet` | Loads `dynamic-qday2-testnet-*.json` from the same directory |
| `http` | Enable HTTP JSON-RPC | `false` | `true` | Required for external RPC / WebSocket access |

### L2 Identity

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `zkevm.l2-chain-id` | L2 chain ID | `0` | `44005` | Must match chainspec and wallet network config |

### L1 Connection

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `zkevm.l1-chain-id` | L1 chain ID | `0` | `31337` | Required when connected to L1; overridden by compose from `L1_CHAIN_ID` in `.env` |
| `zkevm.l1-rpc-url` | L1 JSON-RPC endpoint | `""` | `http://host.docker.internal:1545` | Sync batches and read contract events; overridden by compose from `L1_RPC_URL` in `.env` |
| `zkevm.l1-first-block` | First L1 block to sync the rollup from | `0` | `88224` | Set to the L1 block where the rollup starts; for AggLayer networks, use the GER Manager deployment block |
| `zkevm.l1-block-range` | Block range per L1 query | `20000` | `20000` | Larger values speed sync but may hit RPC rate limits |
| `zkevm.l1-query-delay` | Delay between L1 queries (ms) | `6000` | `6000` | Increase if the L1 RPC is rate-limited |
| `zkevm.l1-cache-enabled` | Enable L1 request cache | `false` | `false` | Set to `true` when many repeated L1 lookups occur |
| `zkevm.l1-contract-address-check` | Validate L1 contract addresses at startup | `true` | `false` | Set to `true` to validate the addresses against L1 at startup |
| `zkevm.l1-contract-address-retrieve` | Fetch contract addresses from L1 automatically | `true` | `false` | Set to `false` when addresses are fixed in the yaml |

### L1 Contract Addresses

See the repo README: values come from `deploy_output.json` / `create_rollup_output.json`.

| Field | Purpose | Code default | Current value | Deploy mapping |
|-------|---------|--------------|---------------|----------------|
| `zkevm.address-sequencer` | Sequencer contract address | `""` | `0xf39Fd6…2266` | `create_rollup_output.json` → `sequencer` |
| `zkevm.address-zkevm` | Rollup logic contract address | `""` | `0x24B3c7…0FC34` | `create_rollup_output.json` → `rollupAddress` |
| `zkevm.address-rollup` | Rollup Manager address | `""` | `0x959922…07B1` | `deploy_output.json` → `polygonRollupManagerAddress` |
| `zkevm.address-ger-manager` | Global Exit Root Manager address | `""` | `0xB7f8BC…84F5e` | `deploy_output.json` → `polygonZkEVMGlobalExitRootAddress` |
| `zkevm.l1-matic-contract-address` | L1 Matic / POL token contract | `0x0` | `0x9fE467…a6e0` | Set per L1 network |

> The values above are from the external L1 deploy. Replace them with your deploy's output if you point at a different L1.

### Standalone vs L1 Mode

| Field | Purpose | Code default | External L1 (current) | Local standalone |
|-------|---------|--------------|------------------------|-------------------|
| `zkevm.skip-l1-sync` | Skip all L1 sync stages | `false` | `false` (or remove the field) | `true` |
| `zkevm.initial-fork-id` | Fork ID for local bootstrap without L1 | `0` | unset (fork history comes from L1 sync) | `12` |

> When `skip-l1-sync: true`, `initial-fork-id` must be non-zero or the node panics at startup.

### Sequencer Behavior

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `zkevm.allow-free-transactions` | Accept transactions with zero gas price | `false` | `false` | Enable on testnets that allow free txs |
| `zkevm.executor-strict` | Require executor URLs to be configured | `true` | `false` | Use `false` for local dev without a prover; production should use `true` with `zkevm.executor-urls` |
| `zkevm.disable-virtual-counters` | Disable virtual counter estimation | `false` | `true` | Required without an external executor; conflicts with `executor-strict: true` |
| `zkevm.initial-batch.config` | JSON file for the injected initial batch | `""` | `./qday/dynamic-configs/empty-batch.json` | Used when the chain boots from a genesis batch |
| `zkevm.sequencer-block-seal-time` | Block seal interval | `6s` | `5s` | Controls block production rate |
| `zkevm.sequencer-batch-seal-time` | Batch seal interval | `12s` | `15m` | Controls batch cadence (validium still produces batch metadata) |
| `zkevm.allow-pre-eip155-transactions` | Accept pre-EIP155 signed transactions | `false` | `true` | Enable for legacy transaction formats |
| `zkevm.default-gas-price` | Default / minimum gas price (wei) | `10000000` (0.01 gwei) | `1000000000` (1 gwei) | Affects txpool pricing |

### Datastream (for RPC nodes)

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `zkevm.data-stream-port` | Datastream listen port | `0` (disabled) | `6900` | RPC nodes sync blocks through this port |
| `zkevm.data-stream-host` | Datastream bind address | `""` | `0.0.0.0` | Must be set together with port to enable the server |
| `zkevm.datastream-version` | Stream protocol version (1=PreBigEndian, 2=BigEndian) | `2` | `2` | Must match RPC nodes |

### HTTP / RPC Server

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `http.api` | Enabled JSON-RPC namespaces | `eth,erigon,engine` | Includes `debug,net,trace,web3,txpool,zkevm` | Sequencer needs `txpool` to accept transactions |
| `http.addr` | HTTP bind address | `127.0.0.1` | `0.0.0.0` | Use `0.0.0.0` for Docker / remote access |
| `http.port` | HTTP RPC port | `8545` | `8123` | Align with RPC nodes and compose port mappings |
| `http.vhosts` | Allowed Host headers | `localhost` | `*` | Restrict in production |
| `http.corsdomain` | CORS allowed origins | — | `*` | Required for browser DApp access |
| `ws` | Enable WebSocket | `false` | `true` | Required for block / log subscriptions |
| `rpc.batch.limit` | Max requests per JSON-RPC batch | `100` | `500` | Increase for high-throughput API gateways |

---

## Related Files

| File | Description |
|------|-------------|
| `dynamic-qday2-testnet-chainspec.json` | Chain spec (chainId, hard-fork heights) |
| `dynamic-qday2-testnet-conf.json` | Genesis timestamp, gasLimit, etc. |
| `dynamic-qday2-testnet-allocs.json` | Initial account allocations |
| `empty-batch.json` | Initial batch injection data |

---

## See Also

- RPC node config: [dynamic-validium-rpc.md](./dynamic-validium-rpc.md)
- Run guide: `qday/dynamic-configs/README-validium.md`
