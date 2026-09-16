# PQC Verify scripts

Call QDay’s PQCVERIFY precompile (`0x1000`) from a Solidity wrapper. The default algorithm is **ML-DSA-65** (`ALG=2`).

## Files

| File | Purpose |
|------|---------|
| [`genvector.go`](genvector.go) | Generate an ML-DSA-65 key pair and signature, write them to `qday/example/.env` |
| [`Verify.s.sol`](Verify.s.sol) | Read `.env` and send `verifyAndEmit` to a deployed `PqcVerify` |

Contract sources live one directory up: [`PqcVerify.sol`](../PqcVerify.sol), [`PqcPrecompile.sol`](../PqcPrecompile.sol).

## Prerequisites

- Foundry (`forge` / `cast`)
- Go with **CGO** and **liboqs 0.16** (`genvector.go` uses `qday-pqc-sdk`)
- A funded private key and a reachable RPC

On macOS, reuse `PKG_CONFIG_PATH` / `CGO_LDFLAGS` from the repo-root Makefile.

## Call order

```
1. forge create PqcVerify     → contract address
2. genvector.go               → write .env (ALG / PUBKEY / SIGNATURE / MESSAGE)
3. forge script Verify.s.sol  → on-chain verifyAndEmit
```

Step 1 is once per deployment. For a new signature, repeat 2 → 3.

### 1. Deploy the wrapper

From the repo root, or `cd qday/example`:

```bash
cd qday/example

forge create PqcVerify.sol:PqcVerify \
  --root . \
  --rpc-url "$RPC_URL" \
  --chain 44005 \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --legacy
```

Copy `Deployed to: 0x...` into `PQC_VERIFY=` in `qday/example/.env`. If `.env` does not exist yet, step 2 creates it and fills a default address.

### 2. Generate a vector into `.env`

Run from the **repo root** (uses the root `go.mod`):

```bash
export CGO_ENABLED=1
# macOS example:
export PKG_CONFIG_PATH="$(pwd)/build/pkgconfig:/opt/homebrew/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CGO_LDFLAGS="-Wl,-rpath,/opt/homebrew/lib -L/opt/homebrew/opt/openssl@3/lib -Wl,-rpath,/opt/homebrew/opt/openssl@3/lib"

go run -tags pqcgen ./qday/example/script/genvector.go
```

On success it prints `wrote .../qday/example/.env`. An existing `.env` is merged: vector fields are overwritten, keys such as `PQC_VERIFY` are kept.

Optional environment variables:

| Variable | Meaning |
|----------|---------|
| `ENV_FILE` | Path to `.env`; default is the directory that contains `foundry.toml` |
| `PQC_VERIFY` | Written only if that key is not already in `.env` |
| `MESSAGE_TEXT` | Message to sign; default `qday pqcVerify` |

`.env` fields:

| Key | Purpose |
|-----|---------|
| `PQC_VERIFY` | Wrapper contract address |
| `ALG` | Algorithm id; default `2` (ML-DSA-65) |
| `PUBKEY` / `SIGNATURE` / `MESSAGE` | Arguments for `Verify.s.sol` → `verifyAndEmit` |
| `INPUT` | Raw precompile payload: `alg(8B BE) \|\| pubkey \|\| signature \|\| message` |

Foundry loads `qday/example/.env` automatically. `.env` is gitignored.

### 3. Run the verify script

Foundry’s local EVM does **not** implement the `0x1000` precompile. You must pass `--broadcast --skip-simulation` so the real node executes the call.

```bash
cd qday/example

forge script script/Verify.s.sol:VerifyScript \
  --sig "run()" \
  --root . \
  --rpc-url "$RPC_URL" \
  --chain 44005 \
  --legacy \
  --broadcast \
  --skip-simulation \
  --gas-limit 5000000 \
  --private-key "$PRIVATE_KEY"
```

Success looks like `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL`, receipt `status = 0x1`, and event `PqcVerified(alg=2, valid=true)`.

Broadcast artifacts are under `qday/example/broadcast/Verify.s.sol/<chainId>/`.

## Read-only check (optional, between steps 2 and 3)

`eth_call` against the live RPC, no transaction:

```bash
cd qday/example
set -a && source .env && set +a

cast call "$PQC_VERIFY" \
  "verify(uint64,bytes,bytes,bytes)(bool)" \
  "$ALG" "$PUBKEY" "$SIGNATURE" "$MESSAGE" \
  --rpc-url "$RPC_URL"
```

This should return `true`. For `verifyRaw`, pass `INPUT` from `.env`.

## Precompile layout

- Address: `0x1000`
- Input: `alg (uint64 big-endian, 8 bytes) || pubkey || signature || message` (no length prefixes)
- Success: 32-byte left-padded `0x01`; invalid or malformed input: empty return (no revert)

Algorithm ids: `1` ML-DSA-44, `2` ML-DSA-65, `3` ML-DSA-87, `7/8` Falcon-512/1024, `9/10` Falcon-padded.
