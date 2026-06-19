#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-wallet-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
DAEMON_TIMEOUT_SEC="${DAEMON_TIMEOUT_SEC:-30}"
LOCALNET_TIMEOUT_SEC="${LOCALNET_TIMEOUT_SEC:-180}"
START_LOCALNET="${START_LOCALNET:-1}"
KEEP_LOCALNET="${KEEP_LOCALNET:-0}"
AUTO_TOPUP="${AUTO_TOPUP:-1}"
SCAFFOLD_PROJECT="${SCAFFOLD_PROJECT:-$ROOT/.local/localnet-integration/scaffold-project}"
SCAFFOLD_BIN="${SCAFFOLD_BIN:-}"
LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-$WORKSPACE/logos-blockchain-circuits}"
FROM_ADDRESS="${FROM_ADDRESS:-CbgR6tj5kWx5oziiFptM7jMvrQeYY3Mzaao6ciuhSr2r}"
FROM_PRIVATE_KEY_HEX="${FROM_PRIVATE_KEY_HEX:-7f273098f25b71e6c005a9519f2678da8d1c7f01f6a27778e2d9948abdf901fb}"
# Scaffold public B. Use hex here because this pinned LEZ FFI lists and accepts
# the account by hex, while its base58 decoder rejects the same account.
TO_ADDRESS="${TO_ADDRESS:-15145aee2e6c9c57d2847b8ca2e100937f11ee76fdfd75fcb588488aa2064547}"
TRANSFER_AMOUNT="${TRANSFER_AMOUNT:-1}"
POLICY_LIMIT="${POLICY_LIMIT:-1000}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-wallet-smoke.sh [options]

Starts one isolated Logos Core daemon, loads logos_agent and LEZ, opens a
scaffold wallet through the agent config, verifies the spending-threshold
approval path, checks wallet.balance, then submits wallet.send against the
local sequencer when localnet is available.

Options:
  --modules-dir P         Directory containing live modules.
  --logoscore P           logoscore binary path.
  --run-root P            Directory for logs and isolated config.
  --daemon-timeout SEC    Daemon readiness timeout. Default: 30.
  --localnet-timeout SEC  Scaffold localnet readiness timeout. Default: 180.
  --scaffold-project P    Scaffold project containing .scaffold/wallet.
  --scaffold-bin P        logos-scaffold binary path.
  --circuits-dir P        logos-blockchain-circuits path for sequencer.
  --from ADDRESS          Funded sender account. Default: scaffold public A.
  --from-private-key HEX  Private signing key for --from. Default: scaffold public A.
  --to ADDRESS            Recipient account. Default: scaffold public B.
  --amount N              Token units to send. Default: 1.
  --no-topup              Do not fund --from before the transfer.
  --no-start-localnet     Do not start scaffold localnet; require it already live.
  --keep-localnet         Leave localnet running on exit.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --modules-dir) MODULES_DIR="${2:-}"; shift ;;
    --logoscore) LOGOSCORE="${2:-}"; shift ;;
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --daemon-timeout) DAEMON_TIMEOUT_SEC="${2:-}"; shift ;;
    --localnet-timeout) LOCALNET_TIMEOUT_SEC="${2:-}"; shift ;;
    --scaffold-project) SCAFFOLD_PROJECT="${2:-}"; shift ;;
    --scaffold-bin) SCAFFOLD_BIN="${2:-}"; shift ;;
    --circuits-dir) LOGOS_BLOCKCHAIN_CIRCUITS="${2:-}"; shift ;;
    --from) FROM_ADDRESS="${2:-}"; shift ;;
    --from-private-key) FROM_PRIVATE_KEY_HEX="${2:-}"; shift ;;
    --to) TO_ADDRESS="${2:-}"; shift ;;
    --amount) TRANSFER_AMOUNT="${2:-}"; shift ;;
    --no-topup) AUTO_TOPUP=0 ;;
    --no-start-localnet) START_LOCALNET=0 ;;
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
for module in logos_execution_zone logos_agent; do
  if [ ! -d "$MODULES_DIR/$module" ]; then
    echo "missing module under modules dir: $MODULES_DIR/$module" >&2
    exit 1
  fi
done
if [ ! -d "$SCAFFOLD_PROJECT/.scaffold/wallet" ]; then
  echo "scaffold wallet home not found: $SCAFFOLD_PROJECT/.scaffold/wallet" >&2
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
  cat >&2 <<EOF
logos-scaffold binary not found.

Build it first:
  cd "$WORKSPACE/scaffold"
  cargo build --release --bin logos-scaffold

Then rerun this script or pass --scaffold-bin.
EOF
  exit 1
fi
SCAFFOLD_BIN="$(cd "$(dirname "$SCAFFOLD_BIN")" && pwd)/$(basename "$SCAFFOLD_BIN")"
LOGOSCORE="$(cd "$(dirname "$LOGOSCORE")" && pwd)/$(basename "$LOGOSCORE")"
MODULES_DIR="$(cd "$MODULES_DIR" && pwd)"
SCAFFOLD_PROJECT="$(cd "$SCAFFOLD_PROJECT" && pwd)"
LOGOS_BLOCKCHAIN_CIRCUITS="$(cd "$LOGOS_BLOCKCHAIN_CIRCUITS" && pwd)"

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
agent wallet smoke failed with exit status $status
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

call_agent() {
  local method="$1"
  shift
  local output
  output="$("$LOGOSCORE" --config-dir "$CORE_CFG" call logos_agent "$method" "$@" 2>&1)" || {
    printf '%s\n' "$output" | unwrap_core_response
    return 0
  }
  printf '%s\n' "$output" | unwrap_core_response
}

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

assert_json_ok() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
label = sys.argv[2]
text = path.read_text().strip()
try:
    payload = json.loads(text)
except json.JSONDecodeError as exc:
    raise SystemExit(f"{label}: output is not JSON: {exc}: {text[:300]}")
if not isinstance(payload, dict) or payload.get("ok") is not True:
    raise SystemExit(f"{label}: expected ok=true, got: {json.dumps(payload, indent=2)[:1600]}")
PY
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
ready = payload.get("ready")
managed = payload.get("managed")
if ready is True or status in {"running", "ready"} or managed is True:
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

prepare_wallet_files() {
  cp "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" "$WALLET_DIR/wallet_config.json"
}

write_config() {
  python3 - "$CONFIG_JSON" "$RUN_ROOT" "$WALLET_DIR" "$FROM_ADDRESS" "$FROM_PRIVATE_KEY_HEX" "$POLICY_LIMIT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
run_root = pathlib.Path(sys.argv[2])
wallet_dir = pathlib.Path(sys.argv[3])
from_address = sys.argv[4]
from_private_key = sys.argv[5]
policy_limit = sys.argv[6]
config = {
    "identity": {
        "agent_id": "wallet-smoke-agent",
        "messaging_address": "wallet-smoke-agent",
        "lez_account": from_address,
        "lez_account_is_public": True,
    },
    "persistence_path": str(run_root / "agent-state"),
    "policy": {
        "per_transaction_limit": policy_limit,
        "period_limit": policy_limit,
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
}
path.write_text(json.dumps(config, separators=(",", ":")))
PY
}

wallet_send_params() {
  python3 - "$TO_ADDRESS" "$TRANSFER_AMOUNT" <<'PY'
import json
import sys

print(json.dumps({
    "recipient": sys.argv[1],
    "amount": sys.argv[2],
    "mode": "public",
}, separators=(",", ":")))
PY
}

assert_approval_gate() {
  local file="$1"
  python3 - "$file" "$TRANSFER_AMOUNT" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
amount = sys.argv[2]
if payload.get("requires_approval") is not True:
    raise SystemExit(f"expected requires_approval=true, got: {json.dumps(payload, indent=2)[:1200]}")
approval = payload.get("approval", {})
if approval.get("skill") != "wallet.send" or str(approval.get("amount")) != amount:
    raise SystemExit(f"approval does not describe wallet.send amount {amount}: {json.dumps(payload, indent=2)[:1200]}")
PY
}

assert_wallet_open() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
wallet = payload.get("adapters", {}).get("wallet", {})
if wallet.get("ok") is not True or wallet.get("wallet_open") is not True:
    raise SystemExit(f"wallet adapter did not open cleanly: {json.dumps(payload, indent=2)[:1600]}")
account = wallet.get("account", {})
if not isinstance(account, dict) or account.get("is_public") is not True or not account.get("account"):
    raise SystemExit(f"wallet adapter did not configure a public agent account: {json.dumps(payload, indent=2)[:1600]}")
PY
}

assert_balance_result() {
  local file="$1"
  python3 - "$file" "$FROM_ADDRESS" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
if payload.get("account") == "":
    raise SystemExit(f"wallet.balance returned an empty account: {json.dumps(payload, indent=2)[:1200]}")
balance = payload.get("balance")
if balance in ("", None):
    raise SystemExit(f"wallet.balance returned an empty balance: {json.dumps(payload, indent=2)[:1200]}")
try:
    int(str(balance))
except ValueError as exc:
    raise SystemExit(f"wallet.balance is not numeric: {balance!r}") from exc
PY
}

assert_transfer_result() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
tx = payload.get("transaction", {})
result = tx.get("result", {})
if result.get("success") is not True:
    raise SystemExit(f"wallet.send did not report success: {json.dumps(payload, indent=2)[:1800]}")
tx_hash = result.get("tx_hash")
if not isinstance(tx_hash, str) or not tx_hash:
    raise SystemExit(f"wallet.send did not return a tx_hash: {json.dumps(payload, indent=2)[:1800]}")
print(tx_hash)
PY
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

path = pathlib.Path(sys.argv[1])
expected_address = sys.argv[2]
try:
    payload = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    raise SystemExit(f"wallet topup output is not JSON: {exc}: {path.read_text()[:500]}")
status = str(payload.get("status", "")).lower()
if status != "success":
    raise SystemExit(f"wallet topup did not report success: {json.dumps(payload, indent=2)[:1600]}")
actual_address = str(payload.get("address", ""))
if actual_address and actual_address != expected_address:
    raise SystemExit(f"wallet topup funded {actual_address}, expected {expected_address}")
tx_hash = payload.get("tx_hash")
tx = payload.get("tx")
if tx_hash is not None and not isinstance(tx_hash, str):
    raise SystemExit(f"wallet topup tx_hash must be a string when present: {json.dumps(payload, indent=2)[:1600]}")
if tx is not None and not isinstance(tx, (str, dict)):
    raise SystemExit(f"wallet topup tx must be a string/object/null when present: {json.dumps(payload, indent=2)[:1600]}")
PY
}

if [ "$START_LOCALNET" -eq 1 ]; then
  (cd "$SCAFFOLD_PROJECT" && LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" "$SCAFFOLD_BIN" localnet start --timeout-sec "$LOCALNET_TIMEOUT_SEC" >"$RUN_ROOT/localnet-start.out" 2>"$RUN_ROOT/localnet-start.err")
  LOCALNET_STARTED=1
fi
wait_for_localnet
if [ "$AUTO_TOPUP" -eq 1 ]; then
  topup_sender
fi
prepare_wallet_files

"$LOGOSCORE" --config-dir "$CORE_CFG" -D -m "$MODULES_DIR" >"$CORE_LOG" 2>&1 &
CORE_PID=$!
wait_for_daemon

for module in logos_execution_zone logos_agent; do
  "$LOGOSCORE" --config-dir "$CORE_CFG" load-module "$module" >"$RUN_ROOT/load-$module.out"
done

write_config

call_agent init "$(cat "$CONFIG_JSON")" >"$RUN_ROOT/init.json"
assert_json_ok "$RUN_ROOT/init.json" "init"

call_agent start >"$RUN_ROOT/start.json"
assert_json_ok "$RUN_ROOT/start.json" "start"
assert_wallet_open "$RUN_ROOT/start.json"

call_agent invoke meta.configure '{"key":"policy","value":{"per_transaction_limit":"0","period_limit":"0","period_seconds":86400}}' >"$RUN_ROOT/policy-zero.json"
assert_json_ok "$RUN_ROOT/policy-zero.json" "meta.configure policy zero"

call_agent invoke wallet.send "$(wallet_send_params)" >"$RUN_ROOT/wallet-send-approval-required.json"
assert_json_ok "$RUN_ROOT/wallet-send-approval-required.json" "wallet.send approval required"
assert_approval_gate "$RUN_ROOT/wallet-send-approval-required.json"

call_agent invoke meta.configure "{\"key\":\"policy\",\"value\":{\"per_transaction_limit\":\"$POLICY_LIMIT\",\"period_limit\":\"$POLICY_LIMIT\",\"period_seconds\":86400}}" >"$RUN_ROOT/policy-allow.json"
assert_json_ok "$RUN_ROOT/policy-allow.json" "meta.configure policy allow"

call_agent invoke wallet.balance '{}' >"$RUN_ROOT/balance-before.json"
assert_json_ok "$RUN_ROOT/balance-before.json" "wallet.balance before"
assert_balance_result "$RUN_ROOT/balance-before.json"

call_agent invoke wallet.send "$(wallet_send_params)" >"$RUN_ROOT/wallet-send.json"
assert_json_ok "$RUN_ROOT/wallet-send.json" "wallet.send"
TX_HASH="$(assert_transfer_result "$RUN_ROOT/wallet-send.json")"

call_agent invoke wallet.history '{}' >"$RUN_ROOT/wallet-history.json"
assert_json_ok "$RUN_ROOT/wallet-history.json" "wallet.history"

call_agent invoke wallet.balance '{}' >"$RUN_ROOT/balance-after.json"
assert_json_ok "$RUN_ROOT/balance-after.json" "wallet.balance after"
assert_balance_result "$RUN_ROOT/balance-after.json"

python3 - "$RUN_ROOT" "$FROM_ADDRESS" "$TO_ADDRESS" "$TRANSFER_AMOUNT" "$TX_HASH" <<'PY'
import json
import pathlib
import sys

run_root = pathlib.Path(sys.argv[1])
summary = {
    "ok": True,
    "run_root": str(run_root),
    "from": sys.argv[2],
    "to": sys.argv[3],
    "amount": sys.argv[4],
    "topup": json.loads((run_root / "wallet-topup.json").read_text()) if (run_root / "wallet-topup.json").exists() else None,
    "tx_hash": sys.argv[5],
    "balance_before": json.loads((run_root / "balance-before.json").read_text()).get("balance"),
    "balance_after": json.loads((run_root / "balance-after.json").read_text()).get("balance"),
}
print(json.dumps(summary, indent=2))
PY
