#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules-v02}"
RUN_ROOT=""
WALLET_DIR=""
WALLET_CONFIG=""
AGENT_ID="wallet-provision-$(date -u +%Y%m%dT%H%M%SZ)"
DAEMON_TIMEOUT_SEC="${DAEMON_TIMEOUT_SEC:-45}"

usage() {
  cat <<'USAGE'
Usage: scripts/provision-v02-wallet.sh --wallet-dir DIR --wallet-config FILE --run-root DIR [options]

Creates and registers one isolated public wallet through the released v0.2
LEZ Core and logos_agent modules. The JSON result contains public account
identifiers only; wallet storage remains in --wallet-dir.

Options:
  --agent-id ID          Agent identity recorded during provisioning.
  --logoscore PATH       Exact logoscore v0.2 executable.
  --modules-dir DIR      Prepared v0.2 module directory.
  --daemon-timeout SEC   Core readiness timeout. Default: 45.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --wallet-dir) WALLET_DIR="${2:-}"; shift ;;
    --wallet-config) WALLET_CONFIG="${2:-}"; shift ;;
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --agent-id) AGENT_ID="${2:-}"; shift ;;
    --logoscore) LOGOSCORE="${2:-}"; shift ;;
    --modules-dir) MODULES_DIR="${2:-}"; shift ;;
    --daemon-timeout) DAEMON_TIMEOUT_SEC="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$LOGOSCORE" ] && [ -s "$ROOT/.local/tools-v02/logoscore.path" ]; then
  LOGOSCORE="$(<"$ROOT/.local/tools-v02/logoscore.path")"
fi
if [ -z "$RUN_ROOT" ] || [ -z "$WALLET_DIR" ] || [ -z "$WALLET_CONFIG" ]; then
  usage >&2
  exit 2
fi
if [ ! -x "$LOGOSCORE" ]; then
  echo "logoscore not found or not executable: $LOGOSCORE" >&2
  exit 1
fi
for module in lez_core logos_agent; do
  if [ ! -d "$MODULES_DIR/$module" ]; then
    echo "missing module under modules dir: $MODULES_DIR/$module" >&2
    exit 1
  fi
done
if [ ! -f "$WALLET_CONFIG" ]; then
  echo "wallet config not found: $WALLET_CONFIG" >&2
  exit 1
fi

mkdir -p "$RUN_ROOT" "$WALLET_DIR"
RUN_ROOT="$(cd "$RUN_ROOT" && pwd)"
WALLET_DIR="$(cd "$WALLET_DIR" && pwd)"
MODULES_DIR="$(cd "$MODULES_DIR" && pwd)"
LOGOSCORE="$(cd "$(dirname "$LOGOSCORE")" && pwd)/$(basename "$LOGOSCORE")"
CORE_CFG="$RUN_ROOT/core"
CORE_LOG="$RUN_ROOT/logoscore.log"
CONFIG_JSON="$RUN_ROOT/agent-config.json"
START_JSON="$RUN_ROOT/start.json"
mkdir -p "$CORE_CFG"
cp "$WALLET_CONFIG" "$WALLET_DIR/wallet_config.json"

if [ -e "$WALLET_DIR/storage.json" ]; then
  echo "refusing to overwrite existing wallet storage: $WALLET_DIR/storage.json" >&2
  exit 1
fi

python3 - "$CONFIG_JSON" "$RUN_ROOT" "$WALLET_DIR" "$AGENT_ID" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
run_root = pathlib.Path(sys.argv[2])
wallet_dir = pathlib.Path(sys.argv[3])
agent_id = sys.argv[4]
config = {
    "identity": {
        "agent_id": agent_id,
        "messaging_address": agent_id,
    },
    "persistence_path": str(run_root / "agent-state"),
    "security": {
        "allow_dev_file_cipher": False,
        "allow_dev_a2a_secret": False,
    },
    "wallet": {
        "config_path": str(wallet_dir / "wallet_config.json"),
        "storage_path": str(wallet_dir / "storage.json"),
        "password": "wallet-smoke",
        "create": True,
        "create_agent_account": True,
        "create_agent_account_type": "public",
        "register_agent_account": True,
    },
}
path.write_text(json.dumps(config, separators=(",", ":")))
PY

CORE_PID=""
cleanup() {
  "$LOGOSCORE" --config-dir "$CORE_CFG" stop >/dev/null 2>&1 || true
  if [ -n "$CORE_PID" ]; then
    wait "$CORE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

unwrap_core_response() {
  python3 -c '
import json
import sys

text = sys.stdin.read().strip()
try:
    payload = json.loads(text)
except json.JSONDecodeError:
    payload = {"ok": False, "status": "error", "message": text}
if isinstance(payload, dict) and payload.get("status") == "ok" and "result" in payload:
    result = payload["result"]
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except json.JSONDecodeError:
            result = {"ok": False, "status": "error", "message": result}
    print(json.dumps(result, separators=(",", ":")))
else:
    print(json.dumps(payload, separators=(",", ":")))
'
}

call_agent() {
  local method="$1"
  shift
  "$LOGOSCORE" --config-dir "$CORE_CFG" call logos_agent "$method" "$@" | unwrap_core_response
}

"$LOGOSCORE" --config-dir "$CORE_CFG" -D -m "$MODULES_DIR" >"$CORE_LOG" 2>&1 &
CORE_PID=$!
deadline=$((SECONDS + DAEMON_TIMEOUT_SEC))
until "$LOGOSCORE" --config-dir "$CORE_CFG" status >/dev/null 2>&1; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "logoscore daemon did not become ready" >&2
    tail -n 120 "$CORE_LOG" >&2 || true
    exit 1
  fi
  sleep 1
done

for module in lez_core logos_agent; do
  "$LOGOSCORE" --config-dir "$CORE_CFG" load-module "$module" >"$RUN_ROOT/load-$module.out"
done
call_agent init "$(cat "$CONFIG_JSON")" >"$RUN_ROOT/init.json"
call_agent start >"$START_JSON"

python3 - "$START_JSON" "$WALLET_DIR/storage.json" "$AGENT_ID" <<'PY'
import json
import pathlib
import sys

start_path = pathlib.Path(sys.argv[1])
storage_path = pathlib.Path(sys.argv[2])
payload = json.loads(start_path.read_text())
wallet = payload.get("adapters", {}).get("wallet", {})
account = wallet.get("account", {}) if isinstance(wallet, dict) else {}
registration = wallet.get("registration", {}) if isinstance(wallet, dict) else {}
if wallet.get("ok") is not True or wallet.get("wallet_open") is not True:
    raise SystemExit(f"wallet provisioning failed: {json.dumps(payload, indent=2)[:2400]}")
if account.get("is_public") is not True or not account.get("account"):
    raise SystemExit(f"wallet provisioning did not return a public account: {json.dumps(payload, indent=2)[:2000]}")
if not storage_path.exists():
    raise SystemExit(f"wallet provisioning did not create storage: {storage_path}")
print(json.dumps({
    "ok": True,
    "agent_id": sys.argv[3],
    "account": account["account"],
    "account_hex": registration.get("account", ""),
    "is_public": True,
    "wallet_config": str(storage_path.with_name("wallet_config.json")),
    "wallet_storage": str(storage_path),
}, separators=(",", ":")))
PY
