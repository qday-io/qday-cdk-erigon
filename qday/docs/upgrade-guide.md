# Upgrade Guide

How to upgrade the qday2-testnet Validium stack between versions.

## Upgrading the cdk-erigon Binary

### Native (local build)

```bash
# Stop running nodes
pkill -f cdk-erigon

# Pull latest code
git pull origin <branch>

# Rebuild the binary
make cdk-erigon

# Validate configs
./qday/dynamic-configs/validate-config.sh

# Restart
./qday/dynamic-configs/start-sequencer.sh &  # Terminal 1
./qday/dynamic-configs/start-rpc.sh          # Terminal 2
```

### Docker

```bash
cd qday/dynamic-configs

# Update .env with the new image tag
# Edit CDK_ERIGON_IMAGE=ghcr.io/qday-io/qday-cdk-erigon:<new-tag>

# Pull new image
docker compose pull
docker compose -f docker-compose.rpc.yml pull

# Stop old containers
docker compose down
docker compose -f docker-compose.rpc.yml down

# Start new containers
docker compose up -d
docker compose -f docker-compose.rpc.yml up -d
```

## Upgrading the Pool Manager

```bash
cd qday/dynamic-configs

# Update .env
# POOL_MANAGER_IMAGE=hermeznetwork/zkevm-pool-manager:<new-version>

# Stop RPC stack
docker compose -f docker-compose.rpc.yml down

# Pull and restart
docker compose -f docker-compose.rpc.yml pull
docker compose -f docker-compose.rpc.yml up -d
```

## Database Compatibility

### MDBX Schema Versions

cdk-erigon uses MDBX databases under `<datadir>/`. Schema upgrades between versions are **automatic** — the node will migrate data on first startup. However:

- **Downgrades are not supported**. Once started on a newer version, the database cannot be opened by an older binary.
- **Always back up data before upgrading**:

```bash
cp -r qday/dynamic-configs/datadir-validium qday/dynamic-configs/datadir-validium.bak.$(date +%Y%m%d)
cp -r qday/dynamic-configs/datadir-validium-rpc qday/dynamic-configs/datadir-validium-rpc.bak.$(date +%Y%m%d)
```

### Reset After Major Version Bumps

If a major version bump introduces incompatible database changes:

```bash
# Wipe data and start fresh
./qday/dynamic-configs/cleanup.sh
./qday/dynamic-configs/start-all.sh
```

This is a **testnet** — resetting loses only local test data. In production, coordinate upgrades with rollbacks in mind.

## Configuration Changes

### New Flags in New Versions

When upgrading, compare your config YAML files against the template configs. New cdk-erigon versions may introduce new flags or change defaults.

Check for breaking changes:

```bash
# Diff your configs against a fresh checkout
git diff HEAD -- qday/dynamic-configs/dynamic-validium.yaml
git diff HEAD -- qday/dynamic-configs/dynamic-validium-rpc.yaml
```

### Standalone to L1-Connected Migration

To switch from standalone mode to real L1 connection:

1. Stop both nodes
2. Update both YAML configs:
   - Set `zkevm.skip-l1-sync: false`
   - Remove `zkevm.initial-fork-id`
   - Fill in real contract addresses from `deploy_output.json` / `create_rollup_output.json`
   - Set `zkevm.l1-rpc-url` to your L1 RPC endpoint
   - Set `zkevm.l1-first-block` to the rollup start block
3. Wipe data directories (sync from L1 requires fresh state):
   ```bash
   ./qday/dynamic-configs/cleanup.sh
   ```
4. Restart
   ```bash
   ./qday/dynamic-configs/start-sequencer.sh
   ```

## Zero-Downtime Upgrades

For environments with multiple RPC nodes, you can upgrade with minimal downtime:

1. Stop RPC node #1, upgrade, restart
2. Wait for `eth_blockNumber` to match the sequencer
3. Stop RPC node #2, upgrade, restart
4. (If needed) Stop the sequencer, upgrade, restart

> **Note**: A sequencer restart causes a brief gap in block production (a few seconds). RPC nodes will resume syncing when the sequencer comes back up.

## Rollback Procedure

If an upgrade causes issues:

1. Stop all nodes:
   ```bash
   pkill -f cdk-erigon
   docker compose down
   docker compose -f docker-compose.rpc.yml down
   ```

2. Restore the previous database backup:
   ```bash
   rm -rf qday/dynamic-configs/datadir-validium
   cp -r qday/dynamic-configs/datadir-validium.bak.YYYYMMDD qday/dynamic-configs/datadir-validium
   ```

3. Revert to the previous binary/image tag

4. Restart

## Upgrade Checklist

- [ ] Read release notes for the target version
- [ ] Review config diffs: `git diff` on YAML files
- [ ] Backup data directories
- [ ] Run `./qday/dynamic-configs/validate-config.sh`
- [ ] Pull/build new binary/image
- [ ] Stop old nodes gracefully
- [ ] Start new nodes
- [ ] Run `./qday/dynamic-configs/health-check.sh`
- [ ] Verify `eth_chainId`, `eth_blockNumber` return expected values
- [ ] Submit a test transaction and verify it gets sealed
