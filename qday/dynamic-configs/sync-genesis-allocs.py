#!/bin/sh
""":"
# Shell bootstrap: this file is executable as ./sync-genesis-allocs.py.
# If Python is missing, fail here with a clear error instead of
# "env: python3: No such file or directory".
py=""
if command -v python3 >/dev/null 2>&1; then
  py=python3
elif command -v python >/dev/null 2>&1; then
  py=python
fi
if [ -z "$py" ]; then
  echo "error: Python is not installed / 未检测到 Python。" >&2
  echo "Please install Python 3 and retry / 请先安装 Python 3 后再运行此脚本。" >&2
  exit 1
fi
if ! "$py" -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
  echo "error: Python 3 is required, but '$py' is not Python 3 / 需要 Python 3，当前 '$py' 不是 Python 3。" >&2
  exit 1
fi
exec "$py" "$0" "$@"
":"""

__doc__ = """Convert a Polygon CDK genesis.json into cdk-erigon *-allocs.json.

Polygon deploy output (qday-agglayer-contracts) looks like:

    { "root": "0x...", "genesis": [ { "address": "0x...", "bytecode": "...", ... }, ... ] }

cdk-erigon loads the allocs file as a flat address -> account map (no wrapping
"alloc" key). See core/genesis_write_zkevm.go:dynamicPrealloc.

Usage (from repo root or this directory):

    ./qday/dynamic-configs/sync-genesis-allocs.py
    ./qday/dynamic-configs/sync-genesis-allocs.py --dry-run
    ./qday/dynamic-configs/sync-genesis-allocs.py \\
        --src /path/to/genesis.json \\
        --dest qday/dynamic-configs/dynamic-qday2-testnet-allocs.json

    # other allocs files (e.g. unwind test fixture):
    ./qday/dynamic-configs/sync-genesis-allocs.py \\
        --dest zk/tests/unwinds/config/dynamic-integration-allocs.json
"""

import argparse
import json
import shutil
import sys
from collections import OrderedDict
from datetime import datetime
from pathlib import Path
from typing import List, Optional

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent


def _default_src() -> Path:
    candidates = [
        REPO_ROOT.parent / "qday-agglayer-contracts" / "qday" / "output" / "genesis.json",
        Path("/Users/vikesun/workspace/QDAY2/qday-agglayer-contracts/qday/output/genesis.json"),
    ]
    for path in candidates:
        if path.is_file():
            return path
    return candidates[0]


DEFAULT_SRC = _default_src()
DEFAULT_DEST = SCRIPT_DIR / "dynamic-qday2-testnet-allocs.json"


def _as_str(value) -> Optional[str]:
    if value is None:
        return None
    return str(value)


def _empty_to_null(value: Optional[str]) -> Optional[str]:
    if value is None or value == "":
        return None
    return value


def genesis_entry_to_account(entry: dict) -> dict:
    """Map one Polygon genesis[] item to an erigon GenesisAccount object."""
    code = _empty_to_null(entry.get("bytecode") or entry.get("code"))
    storage = entry.get("storage")
    if not storage:
        storage = None

    account = OrderedDict()
    contract_name = _empty_to_null(entry.get("contractName"))
    account_name = _empty_to_null(entry.get("accountName"))
    # Always emit contractName so the file matches existing allocs fixtures.
    account["contractName"] = contract_name
    if account_name is not None:
        account["accountName"] = account_name
    account["balance"] = _as_str(entry.get("balance")) or "0"
    account["nonce"] = _as_str(entry.get("nonce")) or "0"
    account["code"] = code
    account["storage"] = storage
    return account


def convert_polygon_genesis(src: dict) -> OrderedDict:
    entries = src.get("genesis")
    if not isinstance(entries, list):
        raise ValueError(
            "expected Polygon genesis.json with a top-level 'genesis' array "
            "(got keys: %s)" % sorted(src.keys())
        )

    allocs = OrderedDict()
    for i, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValueError("genesis[%d] is not an object" % i)
        address = entry.get("address")
        if not address:
            raise ValueError("genesis[%d] is missing 'address'" % i)
        if address in allocs:
            raise ValueError("duplicate address in genesis: %s" % address)
        allocs[address] = genesis_entry_to_account(entry)
    return allocs


def backup_dest(dest: Path) -> Optional[Path]:
    """Copy dest to dest.<timestamp>.bak next to the original file."""
    if not dest.is_file():
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = dest.with_name("%s.%s.bak" % (dest.name, stamp))
    shutil.copy2(dest, backup)
    return backup


def load_existing_allocs(path: Path) -> OrderedDict:
    if not path.exists():
        return OrderedDict()
    with path.open() as f:
        data = json.load(f, object_pairs_hook=OrderedDict)
    if not isinstance(data, dict):
        return OrderedDict()
    # Polygon wrapper accidentally passed as dest; ignore.
    if "genesis" in data and "root" in data:
        return OrderedDict()
    return data


def summarize(allocs: dict) -> str:
    contracts = 0
    eoa = 0
    for acc in allocs.values():
        if acc.get("code"):
            contracts += 1
        else:
            eoa += 1
    return "%d accounts (%d contracts, %d EOA)" % (len(allocs), contracts, eoa)


def parse_args(argv: List[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Convert Polygon CDK genesis.json to cdk-erigon *-allocs.json"
    )
    p.add_argument(
        "--src",
        type=Path,
        default=DEFAULT_SRC,
        help="Polygon genesis.json (default: %(default)s)",
    )
    p.add_argument(
        "--dest",
        type=Path,
        default=DEFAULT_DEST,
        help="cdk-erigon allocs.json to overwrite (default: %(default)s)",
    )
    p.add_argument(
        "--merge",
        action="store_true",
        help="keep dest accounts that are not in genesis.json",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="print the conversion summary without writing dest",
    )
    return p.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    src = args.src.expanduser().resolve()
    dest = args.dest.expanduser().resolve()

    if not src.is_file():
        print("error: source not found: %s" % src, file=sys.stderr)
        return 1

    with src.open() as f:
        raw = json.load(f)

    if isinstance(raw, dict) and "genesis" in raw:
        allocs = convert_polygon_genesis(raw)
        root = raw.get("root")
    elif isinstance(raw, dict) and all(
        isinstance(k, str) and k.startswith("0x") for k in raw.keys()
    ):
        # Already in erigon allocs format; copy through.
        allocs = OrderedDict((k, v) for k, v in raw.items())
        root = None
    else:
        print(
            "error: %s is neither Polygon genesis.json nor an erigon allocs map"
            % src,
            file=sys.stderr,
        )
        return 1

    existing = load_existing_allocs(dest)
    extra = [addr for addr in existing if addr not in allocs]
    missing = [addr for addr in allocs if addr not in existing] if existing else list(allocs)

    if args.merge and extra:
        for addr in extra:
            allocs[addr] = existing[addr]

    print("src : %s" % src)
    if root:
        print("root: %s" % root)
    print("dest: %s" % dest)
    print("out : %s" % summarize(allocs))
    if existing:
        print("was : %s" % summarize(existing))
        if missing:
            print("  + %d new address(es)" % len(missing))
        dropped = extra if not args.merge else []
        if dropped:
            print("  - %d dest-only address(es) will be removed:" % len(dropped))
            for addr in dropped:
                name = (existing[addr] or {}).get("accountName") or (
                    existing[addr] or {}
                ).get("contractName")
                print("      %s  %s" % (addr, name or ""))
        if args.merge and extra:
            print("  ~ keeping %d dest-only address(es) (--merge)" % len(extra))

    if args.dry_run:
        print("dry-run: dest not written")
        return 0

    backup = backup_dest(dest)
    if backup is not None:
        print("backup: %s" % backup)
    else:
        print("backup: skipped (dest does not exist yet)")

    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w") as f:
        json.dump(allocs, f, indent=1)
        f.write("\n")

    print("wrote %s" % dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
