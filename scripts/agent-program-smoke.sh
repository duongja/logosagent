#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-program-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
SCAFFOLD_PROJECT="${SCAFFOLD_PROJECT:-$ROOT/.local/localnet-integration/scaffold-project}"
SCAFFOLD_BIN="${SCAFFOLD_BIN:-}"
LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-$WORKSPACE/logos-blockchain-circuits}"
AGENT_LEZ="${AGENT_LEZ:-$ROOT/agent_lez/target/debug/agent_lez}"
PROGRAM_BINARY="${PROGRAM_BINARY:-$WORKSPACE/logos-execution-zone/artifacts/test_program_methods/noop.bin}"
FROM_ADDRESS="${FROM_ADDRESS:-CbgR6tj5kWx5oziiFptM7jMvrQeYY3Mzaao6ciuhSr2r}"
FROM_PRIVATE_KEY_HEX="${FROM_PRIVATE_KEY_HEX:-7f273098f25b71e6c005a9519f2678da8d1c7f01f6a27778e2d9948abdf901fb}"
LOCALNET_TIMEOUT_SEC="${LOCALNET_TIMEOUT_SEC:-180}"
DAEMON_TIMEOUT_SEC="${DAEMON_TIMEOUT_SEC:-45}"
KEEP_LOCALNET="${KEEP_LOCALNET:-0}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-program-smoke.sh [options]

Starts scaffold localnet and one logos_agent instance, then proves:
  - program.query via agent_lez wallet health
  - program.call via explicit wallet_args against the live wallet CLI
  - program.deploy via wallet deploy-program <binary>

Options:
  --run-root P            Directory for logs and isolated config.
  --modules-dir P         Directory containing live modules.
  --logoscore P           logoscore binary path.
  --scaffold-project P    Scaffold project containing .scaffold/wallet.
  --scaffold-bin P        logos-scaffold binary path.
  --circuits-dir P        logos-blockchain-circuits path for sequencer.
  --agent-lez P           agent_lez helper path.
  --program-binary P      Program binary for deploy.
  --from ADDRESS          Public account funded for program/wallet operations.
  --from-private-key HEX  Private signing key metadata for --from.
  --localnet-timeout SEC  Scaffold localnet readiness timeout. Default: 180.
  --daemon-timeout SEC    Logos Core readiness timeout. Default: 45.
  --keep-localnet         Leave localnet running on exit.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --modules-dir) MODULES_DIR="${2:-}"; shift ;;
    --logoscore) LOGOSCORE="${2:-}"; shift ;;
    --scaffold-project) SCAFFOLD_PROJECT="${2:-}"; shift ;;
    --scaffold-bin) SCAFFOLD_BIN="${2:-}"; shift ;;
    --circuits-dir) LOGOS_BLOCKCHAIN_CIRCUITS="${2:-}"; shift ;;
    --agent-lez) AGENT_LEZ="${2:-}"; shift ;;
    --program-binary) PROGRAM_BINARY="${2:-}"; shift ;;
    --from) FROM_ADDRESS="${2:-}"; shift ;;
    --from-private-key) FROM_PRIVATE_KEY_HEX="${2:-}"; shift ;;
    --localnet-timeout) LOCALNET_TIMEOUT_SEC="${2:-}"; shift ;;
    --daemon-timeout) DAEMON_TIMEOUT_SEC="${2:-}"; shift ;;
    --keep-localnet) KEEP_LOCALNET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ ! -x "$LOGOSCORE" ]; then
  echo "logoscore not found or not executable: $LOGOSCORE" >&2
  exit 1
fi
for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  if [ ! -d "$MODULES_DIR/$module" ]; then
    echo "missing module under modules dir: $MODULES_DIR/$module" >&2
    exit 1
  fi
done
if [ ! -x "$AGENT_LEZ" ]; then
  (cd "$ROOT/agent_lez" && cargo build --locked)
fi
if [ ! -x "$AGENT_LEZ" ]; then
  echo "agent_lez helper not found or not executable: $AGENT_LEZ" >&2
  exit 1
fi
if [ ! -f "$PROGRAM_BINARY" ]; then
  echo "program binary not found: $PROGRAM_BINARY" >&2
  exit 1
fi
if [ -z "$SCAFFOLD_BIN" ]; then
  if command -v logos-scaffold >/dev/null 2>&1; then
    SCAFFOLD_BIN="$(command -v logos-scaffold)"
  elif [ -x "$WORKSPACE/scaffold/target/release/logos-scaffold" ]; then
    SCAFFOLD_BIN="$WORKSPACE/scaffold/target/release/logos-scaffold"
  elif [ -x "$WORKSPACE/scaffold/target/debug/logos-scaffold" ]; then
    SCAFFOLD_BIN="$WORKSPACE/scaffold/target/debug/logos-scaffold"
  fi
fi
if [ -z "$SCAFFOLD_BIN" ] || [ ! -x "$SCAFFOLD_BIN" ]; then
  echo "logos-scaffold binary not found; pass --scaffold-bin" >&2
  exit 1
fi
if [ ! -d "$SCAFFOLD_PROJECT/.scaffold/wallet" ]; then
  echo "scaffold wallet home not found: $SCAFFOLD_PROJECT/.scaffold/wallet" >&2
  exit 1
fi

SCAFFOLD_BIN="$(cd "$(dirname "$SCAFFOLD_BIN")" && pwd)/$(basename "$SCAFFOLD_BIN")"
LOGOSCORE="$(cd "$(dirname "$LOGOSCORE")" && pwd)/$(basename "$LOGOSCORE")"
MODULES_DIR="$(cd "$MODULES_DIR" && pwd)"
SCAFFOLD_PROJECT="$(cd "$SCAFFOLD_PROJECT" && pwd)"
LOGOS_BLOCKCHAIN_CIRCUITS="$(cd "$LOGOS_BLOCKCHAIN_CIRCUITS" && pwd)"
AGENT_LEZ="$(cd "$(dirname "$AGENT_LEZ")" && pwd)/$(basename "$AGENT_LEZ")"
PROGRAM_BINARY="$(cd "$(dirname "$PROGRAM_BINARY")" && pwd)/$(basename "$PROGRAM_BINARY")"

mkdir -p "$RUN_ROOT"
RUN_ROOT="$(cd "$RUN_ROOT" && pwd)"
CORE_CFG="$RUN_ROOT/core"
CORE_LOG="$RUN_ROOT/logoscore.log"
CONFIG_JSON="$RUN_ROOT/agent-config.json"
WALLET_DIR="$RUN_ROOT/wallet"
mkdir -p "$CORE_CFG" "$WALLET_DIR"

CORE_PID=""
LOCALNET_STARTED=0

cleanup() {
  "$LOGOSCORE" --config-dir "$CORE_CFG" stop >/dev/null 2>&1 || true
  if [ -n "$CORE_PID" ]; then
    wait "$CORE_PID" >/dev/null 2>&1 || true
  fi
  if [ "$LOCALNET_STARTED" -eq 1 ] && [ "$KEEP_LOCALNET" -eq 0 ]; then
    (cd "$SCAFFOLD_PROJECT" && LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" "$SCAFFOLD_BIN" localnet stop >/dev/null 2>&1) || true
  fi
}

on_error() {
  local status=$?
  cat >&2 <<EOF
agent program smoke failed with exit status $status
run_root: $RUN_ROOT
core log: $CORE_LOG
agent config: $CONFIG_JSON
EOF
  if [ -f "$CORE_LOG" ]; then
    echo "--- core log tail ---" >&2
    tail -n 160 "$CORE_LOG" >&2 || true
  fi
}

trap cleanup EXIT
trap on_error ERR

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
            print(json.dumps(json.loads(result), separators=(",", ":")))
        except json.JSONDecodeError:
            print(json.dumps({"ok": False, "status": "error", "message": result}, separators=(",", ":")))
    else:
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

assert_json_ok() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
label = sys.argv[2]
payload = json.loads(path.read_text())
if not isinstance(payload, dict) or payload.get("ok") is not True:
    raise SystemExit(f"{label}: expected ok=true, got: {json.dumps(payload, indent=2)[:2000]}")
PY
}

assert_helper_mode_ok() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
label = sys.argv[2]
if payload.get("ok") is not True:
    raise SystemExit(f"{label}: expected ok=true, got: {json.dumps(payload, indent=2)[:2000]}")
if payload.get("mode") != "wallet-cli":
    raise SystemExit(f"{label}: expected wallet-cli mode, got: {json.dumps(payload, indent=2)[:1200]}")
PY
}

assert_deploy_ok() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
if payload.get("ok") is not True:
    raise SystemExit(f"program.deploy failed: {json.dumps(payload, indent=2)[:2400]}")
program_id = payload.get("program_id")
if not isinstance(program_id, str) or len(program_id) < 32:
    raise SystemExit(f"program.deploy did not return a program_id: {json.dumps(payload, indent=2)[:1600]}")
PY
}

wait_for_daemon() {
  local deadline=$((SECONDS + DAEMON_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "$LOGOSCORE" --config-dir "$CORE_CFG" status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "logoscore daemon did not become ready for $CORE_CFG" >&2
  return 1
}

wait_for_localnet() {
  local deadline=$((SECONDS + LOCALNET_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if (cd "$SCAFFOLD_PROJECT" && LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" "$SCAFFOLD_BIN" localnet status --json >"$RUN_ROOT/localnet-status.json" 2>"$RUN_ROOT/localnet-status.err"); then
      if python3 - "$RUN_ROOT/localnet-status.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
status = str(payload.get("status", "")).lower()
if payload.get("ready") is True or status in {"running", "ready"} or payload.get("managed") is True:
    raise SystemExit(0)
raise SystemExit(1)
PY
      then
        return 0
      fi
    fi
    sleep 1
  done
  echo "scaffold localnet did not become ready" >&2
  return 1
}

normalize_public_address() {
  local address="$1"
  case "$address" in
    Public/*|Private/*) printf '%s\n' "$address" ;;
    *) printf 'Public/%s\n' "$address" ;;
  esac
}

topup_sender() {
  local funded_address
  funded_address="$(normalize_public_address "$FROM_ADDRESS")"
  (
    cd "$SCAFFOLD_PROJECT"
    LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" \
      "$SCAFFOLD_BIN" wallet topup --json "$funded_address"
  ) >"$RUN_ROOT/wallet-topup.json" 2>"$RUN_ROOT/wallet-topup.err"
  python3 - "$RUN_ROOT/wallet-topup.json" "$funded_address" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = sys.argv[2]
if str(payload.get("status", "")).lower() != "success":
    raise SystemExit(f"wallet topup did not report success: {json.dumps(payload, indent=2)[:1600]}")
if payload.get("address") and payload.get("address") != expected:
    raise SystemExit(f"wallet topup funded {payload.get('address')}, expected {expected}")
PY
}

wallet_bin() {
  python3 - "$SCAFFOLD_PROJECT" <<'PY'
import pathlib
import tomllib
import sys

project = pathlib.Path(sys.argv[1])
cfg = tomllib.loads((project / "scaffold.toml").read_text())
cache_root = pathlib.Path(cfg["scaffold"]["cache_root"])
if not cache_root.is_absolute():
    cache_root = project / cache_root
pin = cfg["repos"]["lez"]["pin"]
candidate = cache_root / "repos" / "lez" / pin / "target" / "release" / "wallet"
print(candidate)
PY
}

write_config() {
  local wallet_bin_path="$1"
  python3 - "$CONFIG_JSON" "$RUN_ROOT" "$WALLET_DIR" "$AGENT_LEZ" "$wallet_bin_path" "$FROM_ADDRESS" "$FROM_PRIVATE_KEY_HEX" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
run_root = pathlib.Path(sys.argv[2])
wallet_dir = pathlib.Path(sys.argv[3])
agent_lez, wallet_bin, from_address, from_private_key = sys.argv[4:8]
config = {
    "identity": {
        "agent_id": "program-smoke-agent",
        "messaging_address": "program-smoke-agent",
        "lez_account": from_address,
        "lez_account_is_public": True,
    },
    "persistence_path": str(run_root / "agent-state"),
    "policy": {
        "per_transaction_limit": "1",
        "period_limit": "100",
        "period_seconds": 86400,
    },
    "security": {
        "allow_dev_file_cipher": False,
        "allow_dev_a2a_secret": False,
    },
    "wallet": {
        "config_path": str(wallet_dir / "wallet_config.json"),
        "storage_path": str(wallet_dir / "storage.json"),
        "password": "wallet-smoke",
        "create": True,
        "public_import_account": from_address,
        "public_import_private_key_hex": from_private_key,
        "create_agent_account": False,
    },
    "program": {
        "helper_path": agent_lez,
        "wallet_bin": wallet_bin,
        "wallet_home": str(wallet_dir),
    },
}
path.write_text(json.dumps(config, separators=(",", ":")))
PY
}

program_query_params() {
  local wallet_bin_path="$1"
  python3 - "$AGENT_LEZ" "$wallet_bin_path" "$WALLET_DIR" <<'PY'
import json
import sys

print(json.dumps({
    "helper_path": sys.argv[1],
    "wallet_bin": sys.argv[2],
    "wallet_home": sys.argv[3],
    "target": "health",
    "timeout_ms": 120000,
}, separators=(",", ":")))
PY
}

program_call_params() {
  local wallet_bin_path="$1"
  python3 - "$AGENT_LEZ" "$wallet_bin_path" "$WALLET_DIR" <<'PY'
import json
import sys

print(json.dumps({
    "helper_path": sys.argv[1],
    "wallet_bin": sys.argv[2],
    "wallet_home": sys.argv[3],
    "wallet_args": ["check-health"],
    "amount": "0",
    "timeout_ms": 45000,
}, separators=(",", ":")))
PY
}

program_deploy_params() {
  local wallet_bin_path="$1"
  python3 - "$AGENT_LEZ" "$wallet_bin_path" "$WALLET_DIR" "$PROGRAM_BINARY" <<'PY'
import json
import sys

print(json.dumps({
    "helper_path": sys.argv[1],
    "wallet_bin": sys.argv[2],
    "wallet_home": sys.argv[3],
    "binary_path": sys.argv[4],
    "amount": "0",
    "timeout_ms": 180000,
}, separators=(",", ":")))
PY
}

"$SCAFFOLD_BIN" localnet stop >/dev/null 2>&1 || true
(cd "$SCAFFOLD_PROJECT" && LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" "$SCAFFOLD_BIN" localnet start --timeout-sec "$LOCALNET_TIMEOUT_SEC" >"$RUN_ROOT/localnet-start.out" 2>"$RUN_ROOT/localnet-start.err")
LOCALNET_STARTED=1
wait_for_localnet
topup_sender

cp "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" "$WALLET_DIR/wallet_config.json"
WALLET_BIN="$(wallet_bin)"
if [ ! -x "$WALLET_BIN" ]; then
  echo "wallet binary not found: $WALLET_BIN" >&2
  exit 1
fi
write_config "$WALLET_BIN"

"$LOGOSCORE" --config-dir "$CORE_CFG" -D -m "$MODULES_DIR" >"$CORE_LOG" 2>&1 &
CORE_PID=$!
wait_for_daemon

for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  "$LOGOSCORE" --config-dir "$CORE_CFG" load-module "$module" >"$RUN_ROOT/load-$module.out"
done

call_agent init "$(cat "$CONFIG_JSON")" >"$RUN_ROOT/init.json"
assert_json_ok "$RUN_ROOT/init.json" "init"
call_agent start >"$RUN_ROOT/start.json"
assert_json_ok "$RUN_ROOT/start.json" "start"

call_agent invoke program.query "$(program_query_params "$WALLET_BIN")" >"$RUN_ROOT/program-query-health.json"
assert_helper_mode_ok "$RUN_ROOT/program-query-health.json" "program.query health"

call_agent invoke program.call "$(program_call_params "$WALLET_BIN")" >"$RUN_ROOT/program-call-wallet-health.json"
assert_helper_mode_ok "$RUN_ROOT/program-call-wallet-health.json" "program.call wallet health"

call_agent invoke program.deploy "$(program_deploy_params "$WALLET_BIN")" >"$RUN_ROOT/program-deploy.json"
assert_deploy_ok "$RUN_ROOT/program-deploy.json"

call_agent invoke wallet.history '{}' >"$RUN_ROOT/wallet-history.json"
assert_json_ok "$RUN_ROOT/wallet-history.json" "wallet.history"

python3 - "$RUN_ROOT" "$PROGRAM_BINARY" <<'PY'
import json
import pathlib
import sys

run_root = pathlib.Path(sys.argv[1])
deploy = json.loads((run_root / "program-deploy.json").read_text())
print(json.dumps({
    "ok": True,
    "run_root": str(run_root),
    "program_binary": sys.argv[2],
    "program_id": deploy.get("program_id"),
    "program_id_source": deploy.get("program_id_source"),
    "proofs": {
        "query": str(run_root / "program-query-health.json"),
        "call": str(run_root / "program-call-wallet-health.json"),
        "deploy": str(run_root / "program-deploy.json"),
        "history": str(run_root / "wallet-history.json"),
    },
}, indent=2))
PY
