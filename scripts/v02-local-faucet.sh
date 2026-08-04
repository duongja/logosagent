#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD_PROJECT=""
ADDRESS=""
WALLET_PASSWORD="${LOGOS_SCAFFOLD_WALLET_PASSWORD:-logos-scaffold-v0}"

usage() {
  cat <<'USAGE'
Usage: scripts/v02-local-faucet.sh --scaffold-project DIR --address ADDRESS

Claims the local v0.2 Pinata faucet directly after logos_agent has registered
the destination account. Emits a JSON result with public transaction data.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scaffold-project) SCAFFOLD_PROJECT="${2:-}"; shift ;;
    --address) ADDRESS="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SCAFFOLD_PROJECT" ] || [ -z "$ADDRESS" ]; then
  usage >&2
  exit 2
fi
SCAFFOLD_PROJECT="$(cd "$SCAFFOLD_PROJECT" && pwd)"

WALLET_BIN="$(python3 - "$SCAFFOLD_PROJECT" <<'PY'
import pathlib
import sys
import tomllib

project = pathlib.Path(sys.argv[1])
cfg = tomllib.loads((project / "scaffold.toml").read_text())
repo = cfg["repos"]["lez"]
if repo.get("path"):
    lez = pathlib.Path(repo["path"])
    if not lez.is_absolute():
        lez = project / lez
else:
    cache = pathlib.Path(cfg["scaffold"]["cache_root"])
    if not cache.is_absolute():
        cache = project / cache
    lez = cache / "repos" / "lez" / repo["pin"]
print(lez / "target" / "release" / "wallet")
PY
)"
if [ ! -x "$WALLET_BIN" ]; then
  echo "v0.2 wallet binary not found: $WALLET_BIN" >&2
  exit 1
fi

case "$ADDRESS" in
  Public/*|Private/*) NORMALIZED_ADDRESS="$ADDRESS" ;;
  *) NORMALIZED_ADDRESS="Public/$ADDRESS" ;;
esac

python3 - "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" "$NORMALIZED_ADDRESS" <<'PY'
import json
import pathlib
import sys
import time
import urllib.request

config = json.loads(pathlib.Path(sys.argv[1]).read_text())
endpoint = config.get("sequencer_addr", "http://127.0.0.1:3040")
account = sys.argv[2].split("/", 1)[-1]
deadline = time.monotonic() + 90
while time.monotonic() < deadline:
    body = json.dumps({
        "jsonrpc": "2.0",
        "method": "getAccount",
        "params": [account],
        "id": 1,
    }).encode()
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.loads(response.read().decode())
        owner = payload.get("result", {}).get("program_owner", [])
        if isinstance(owner, list) and any(int(value) != 0 for value in owner):
            raise SystemExit(0)
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    time.sleep(2)
raise SystemExit(f"registered account was not confirmed within 90 seconds: {sys.argv[2]}")
PY

TMP_DIR="$(mktemp -d "$ROOT/.local/v02-faucet.XXXXXX")"
cleanup() {
  rm -f "$TMP_DIR/stdout" "$TMP_DIR/stderr"
  rmdir "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

if ! printf '%s\n' "$WALLET_PASSWORD" \
  | LEE_WALLET_HOME_DIR="$SCAFFOLD_PROJECT/.scaffold/wallet" \
      NSSA_WALLET_HOME_DIR="$SCAFFOLD_PROJECT/.scaffold/wallet" \
      "$WALLET_BIN" pinata claim --to "$NORMALIZED_ADDRESS" \
      >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
  cat "$TMP_DIR/stderr" >&2
  exit 1
fi

python3 - "$NORMALIZED_ADDRESS" "$TMP_DIR/stdout" "$TMP_DIR/stderr" <<'PY'
import json
import pathlib
import re
import sys

address = sys.argv[1]
stdout = pathlib.Path(sys.argv[2]).read_text()
stderr = pathlib.Path(sys.argv[3]).read_text()
match = re.search(r"Transaction hash is ([0-9a-f]{64})", stdout + "\n" + stderr, re.I)
if not match:
    raise SystemExit("v0.2 faucet completed without a transaction hash")
print(json.dumps({
    "status": "success",
    "address": address,
    "method": "pinata faucet claim",
    "network": "http://127.0.0.1:3040",
    "tx_hash": match.group(1).lower(),
}, indent=2))
PY
