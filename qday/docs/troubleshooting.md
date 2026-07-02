# Troubleshooting Guide

Common issues when running the qday2-testnet Validium stack and their solutions.

## Node Won't Start

### "Binary not found"

```
Binary not found. Run from repo root: make cdk-erigon
```

**Resolution**: Build the binary first:

```bash
make cdk-erigon
```

For Docker, make sure the image is pulled:

```bash
cd qday/dynamic-configs && docker compose pull
```

### "fork id 0. Must use positive integer"

```
fork id 0. Must use positive integer
```

**Cause**: `zkevm.skip-l1-sync: true` is set but `zkevm.initial-fork-id` is missing or zero.

**Resolution**: In standalone mode, `zkevm.initial-fork-id` must be a non-zero positive integer. Ensure both config YAML files have:

```yaml
zkevm.initial-fork-id: 12
```

### "panic: runtime error" at startup with skip-l1-sync

**Cause**: The node boots without L1 sync but has no fork history. This usually means `zkevm.initial-fork-id` was not set.

**Resolution**: Add `zkevm.initial-fork-id: 12` (or appropriate fork ID) to the YAML config. The fork ID must match the intended fork version for the chain.

### "error loading config file: no such file"

**Cause**: The `--config` flag points to a path that doesn't exist, often because you're running from the wrong working directory.

**Resolution**: Always run start scripts from the repo root, or use absolute paths. The `start-sequencer.sh` and `start-rpc.sh` scripts handle this automatically by resolving paths relative to the repo root.

```bash
# Correct — run from repo root
./qday/dynamic-configs/start-sequencer.sh

# Incorrect — running from qday/dynamic-configs/
cd qday/dynamic-configs && ./start-sequencer.sh   # will fail
```

## Sync Issues

### RPC node not syncing / stuck at block 0

**Symptoms**: `eth_blockNumber` returns `0x0` or an unchanging value on the RPC node.

**Checklist**:

1. Is the sequencer running and producing blocks?
   ```bash
   curl -s -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     http://localhost:8123
   ```

2. Is the datastream port accessible from the RPC node?
   ```bash
   # On the RPC host, test connectivity to the sequencer datastream
   nc -zv <sequencer-host> 6900
   ```

3. Is `zkevm.l2-datastreamer-url` correct?
   - Same host: `127.0.0.1:6900`
   - Docker to host: `host.docker.internal:6900`
   - Remote: `<sequencer-ip>:6900`

4. Check RPC node logs for connection errors:
   ```bash
   docker logs qday2-rpc   # Docker
   # Or check the terminal output for native runs
   ```

### "datastream connection refused" in RPC logs

**Cause**: The sequencer is not running, or the datastream port is not reachable.

**Resolution**:

- Ensure the sequencer is running and healthy
- Verify firewall rules allow port 6900
- For Docker: ensure the `extra_hosts` mapping is correct in `docker-compose.rpc.yml`
- For Linux Docker: `host.docker.internal` requires `extra_hosts: ["host.docker.internal:host-gateway"]`

### Sequencer not producing blocks

**Checklist**:

1. Is `CDK_ERIGON_SEQUENCER=1` set?
   ```bash
   env | grep CDK_ERIGON_SEQUENCER
   ```

2. Check the sequencer logs for errors

3. Verify the sequencer health:
   ```bash
   curl -s -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     http://localhost:8123
   ```

4. Has the `empty-batch.json` been properly loaded? Check logs for initial batch injection errors.

## Port Conflicts

### "bind: address already in use"

**Symptoms**: Node fails to start with an error about an address already being in use.

**Common conflicts** when running sequencer + RPC on the same host:

| Port | Sequencer | RPC Node | Conflict Check |
|------|-----------|----------|----------------|
| HTTP RPC | 8123 | 8124 | Different ✓ |
| Datastream | 6900 | — | — |
| Private API | 9090 | 9091 | Different ✓ |
| Engine API | 8551 | 8552 | Different ✓ |
| P2P | 30303 | 30305 | Different ✓ |
| Torrent | 42069 | 42070 | Different ✓ |

**Check which process is using a port**:

```bash
lsof -i :8123   # macOS
ss -tlnp | grep 8123   # Linux
```

**Resolution**: Either stop the conflicting process or change the port in the YAML config.

### Docker port already allocated

```bash
docker compose down   # Clean up previous containers
docker compose up -d
```

## Docker Issues

### Docker Hub rate limiting / pull failures

```
Error response from daemon: toomanyrequests: You have reached your pull rate limit
```

**Resolution**: Either:

1. Log in to Docker Hub: `docker login`
2. Use a mirror registry
3. Run natively instead (no Docker): `./qday/dynamic-configs/start-sequencer.sh`

### "host.docker.internal" not resolving

**Symptoms**: RPC node can't connect to sequencer with `host.docker.internal` errors.

**Cause**: `host.docker.internal` is not available by default on Linux Docker.

**Resolution**: The `docker-compose.rpc.yml` already includes `extra_hosts` for this. If you're running Docker on Linux and still see issues, ensure:

1. You're using Docker 20.10+ with `host-gateway` support
2. The `extra_hosts` section in the compose file is present

For Podman or older Docker, replace `host.docker.internal` with the actual host IP:

```bash
# In .env
SEQUENCER_DATASTREAMER_URL=172.17.0.1:6900
SEQUENCER_RPC_URL=http://172.17.0.1:8123
```

### Permission errors on /data volume

```
Permission denied: /data
```

**Cause**: Named Docker volumes are created as root; cdk-erigon runs as UID 1000.

**Resolution**: The `docker-entrypoint.sh` handles this by `chown`-ing `/data`. If this still fails:

```bash
# Manually fix permissions
sudo chown -R 1000:1000 qday/dynamic-configs/datadir-validium
docker compose down && docker compose up -d
```

## Transaction Issues

### eth_sendRawTransaction returning 0 tx hash or error on RPC node

**Checklist**:

1. Is `zkevm.l2-sequencer-rpc-url` set correctly?
   ```bash
   grep l2-sequencer-rpc-url qday/dynamic-configs/dynamic-validium-rpc.yaml
   ```

2. For pool manager setups: is `zkevm.pool-manager-url` set and the pool manager running?
   ```bash
   docker logs qday2-tx-pool-manager
   ```

3. Is the sequencer's RPC reachable from the RPC node?
   ```bash
   curl http://<sequencer-host>:8123
   ```

4. Check if `txpool.disable: true` is causing issues. Without `zkevm.l2-sequencer-rpc-url` or `zkevm.pool-manager-url`, transactions have nowhere to go.

### "insufficient funds" for pre-funded accounts on fresh start

**Cause**: Genesis allocs specify initial balances. If you started the sequencer without the correct allocs file, the accounts won't be funded.

**Resolution**: Clean up and restart:

```bash
./qday/dynamic-configs/cleanup.sh
./qday/dynamic-configs/start-sequencer.sh
```

## Resource Issues

### High memory usage

**Cause**: cdk-erigon uses MDBX-backed storage which memory-maps the database. This can appear as high RSS.

**Resolution**:

- Ensure at least 16GB RAM for a standalone sequencer
- For Docker, set memory limits:
  ```yaml
  deploy:
    resources:
      limits:
        memory: 8G
  ```

### Disk space growing quickly

**Cause**: The MDBX database grows with chain data. Even a testnet with no user activity generates blocks every 5 seconds.

**Monitor disk usage**:

```bash
du -sh qday/dynamic-configs/datadir-validium
```

**Resolution**: Periodically clean up old data:

```bash
./qday/dynamic-configs/cleanup.sh
```

## Getting Help

1. Check the node logs for detailed error messages
2. Run the health check: `./qday/dynamic-configs/health-check.sh`
3. Validate configs: `./qday/dynamic-configs/validate-config.sh`
4. See the [upgrade guide](upgrade-guide.md) for version-specific issues
