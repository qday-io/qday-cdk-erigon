# dynamic-validium-rpc.yaml Reference

RPC node configuration for **qday2-testnet Validium** — read-only queries and transaction forwarding.

The RPC node does not produce blocks. It syncs from the sequencer **datastream** and forwards write requests (e.g. `eth_sendRawTransaction`) to the sequencer.

Config path: `qday/dynamic-configs/dynamic-validium-rpc.yaml`

How to start:

```bash
# Native
./qday/dynamic-configs/start-rpc.sh

# Docker (with tx pool manager)
cd qday/dynamic-configs && docker compose -f docker-compose.rpc.yml up
```

---

## Usage Scenarios

| Scenario | Key settings |
|----------|--------------|
| **Local standalone RPC** | `zkevm.skip-l1-sync: true`, connect to local sequencer via `zkevm.l2-datastreamer-url` |
| **Remote sequencer** | Point `l2-datastreamer-url` / `l2-sequencer-rpc-url` at the sequencer host |
| **Sequencer + RPC on same host** | Use distinct `http.port`, `private.api.addr`, `torrent.port` to avoid conflicts |
| **Docker + pool manager** | Compose sets `txpool.disable: true` and `zkevm.pool-manager-url` to forward txs to the pool manager |
| **Real L1 connection** | Fill in L1 / contract addresses, set `zkevm.skip-l1-sync: false` (or remove it), remove `zkevm.initial-fork-id` |

---

## Field Reference

### Core Node

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `datadir` | Locally synced chain data directory | — | `./qday/dynamic-configs/datadir-validium-rpc` | Separate from sequencer datadir; Docker compose overrides to `/data` |
| `chain` | Chain name | — | `dynamic-qday2-testnet` | Must match the sequencer |
| `http` | Enable HTTP JSON-RPC | `false` | `true` | Required for external API access |

### L2 Identity

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `zkevm.l2-chain-id` | L2 chain ID | `0` | `44005` | Must match sequencer / chainspec |

### L1 Connection

Same semantics as the sequencer config — see [dynamic-validium.md](./dynamic-validium.md#l1-connection).

| Field | Current value | Notes |
|-------|---------------|-------|
| `zkevm.l1-chain-id` | `11155111` | Ignored in standalone mode |
| `zkevm.l1-rpc-url` | Placeholder URL | Required when connected to L1 |
| `zkevm.l1-first-block` | `1` (placeholder) | Set to rollup start block when connected to L1 |
| `zkevm.l1-block-range` | `20000` | Same as sequencer |
| `zkevm.l1-query-delay` | `6000` | Same as sequencer |
| `zkevm.l1-cache-enabled` | `false` | Same as sequencer |
| `zkevm.l1-contract-address-check` | `false` | Same as sequencer |
| `zkevm.l1-contract-address-retrieve` | `false` | Same as sequencer |
| `zkevm.address-*` / `zkevm.l1-matic-contract-address` | `0x000…000` (placeholder) | Fill from deploy output |

### Standalone vs L1 Mode

| Field | Purpose | Code default | Standalone value | Real L1 value |
|-------|---------|--------------|------------------|---------------|
| `zkevm.skip-l1-sync` | Skip L1 sync; sync from datastream only | `false` | `true` | `false` (or remove the field) |
| `zkevm.initial-fork-id` | Fork ID for local bootstrap without L1 | `0` | `12` | Remove |

### Sequencer Connection (RPC core)

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `zkevm.l2-datastreamer-url` | Sequencer datastream address (`host:port`) | `""` | `127.0.0.1:6900` | **Read path**: sync blocks and batches; required |
| `zkevm.l2-sequencer-rpc-url` | Sequencer HTTP RPC URL | `""` | `http://127.0.0.1:8123` | **Write path**: forward `eth_sendRawTransaction`, etc.; required when clients submit txs |
| `zkevm.datastream-version` | Datastream protocol version | `2` | `2` | Must match the sequencer |

> The two URLs serve different roles: `l2-datastreamer-url` syncs data; `l2-sequencer-rpc-url` handles writes. With only datastream configured, the node is read-only.

Docker compose (`docker-compose.rpc.yml`) overrides via environment variables:

- `SEQUENCER_DATASTREAMER_URL` → `zkevm.l2-datastreamer-url`
- `SEQUENCER_RPC_URL` → `zkevm.l2-sequencer-rpc-url`
- `POOL_MANAGER_URL` → `zkevm.pool-manager-url` (when pool manager is enabled)

### Port Isolation (multi-node on same host)

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `private.api.addr` | Internal private API address | `127.0.0.1:9090` | `127.0.0.1:9091` | Offset from sequencer `:9090` |
| `authrpc.port` | Engine API authenticated RPC port | `8551` | `8552` | Avoid conflict with sequencer |
| `port` | P2P listen port | `30303` | `30305` | RPC nodes typically do not participate in block production P2P |
| `torrent.port` | BitTorrent snapshot port | `42069` | `42070` | Must be unique when co-located |

### HTTP / RPC Server

| Field | Purpose | Code default | Current value | When to use |
|-------|---------|--------------|---------------|-------------|
| `http.api` | Enabled JSON-RPC namespaces | `eth,erigon,engine` | Includes `debug,net,trace,web3,txpool,zkevm` | Public API gateway |
| `http.addr` | HTTP bind address | `127.0.0.1` | `0.0.0.0` | Remote / Docker access |
| `http.port` | HTTP RPC port | `8545` | `8124` | Distinct from sequencer `:8123` |
| `http.vhosts` | Allowed Host headers | `localhost` | `*` | Restrict in production |
| `http.corsdomain` | CORS allowed origins | — | `*` | Browser DApps |
| `ws` | Enable WebSocket | `false` | `true` | Subscription APIs |
| `ws.port` | WebSocket port (falls back to `http.port` if unset) | — | `8125` | Separate from HTTP port |
| `rpc.batch.limit` | Max requests per JSON-RPC batch | `100` | `500` | High-throughput scenarios |

---

## Sequencer vs RPC Config

| Capability | Sequencer (`dynamic-validium.yaml`) | RPC (`dynamic-validium-rpc.yaml`) |
|------------|-------------------------------------|-----------------------------------|
| Block / batch production | Yes | No |
| Datastream server | Yes (`:6900`) | No (connects as client) |
| Local txpool | Yes | No (forwards to sequencer or pool manager) |
| L1 sync | Optional | Optional (usually skipped in standalone) |
| `zkevm.executor-*` | Yes | No |
| `zkevm.data-stream-port/host` | Yes | No |

---

## See Also

- Sequencer config: [dynamic-validium.md](./dynamic-validium.md)
- Run guide: `qday/dynamic-configs/README-validium.md`
