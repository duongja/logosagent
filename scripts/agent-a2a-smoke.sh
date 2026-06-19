#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-a2a-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
PRESET="${PRESET:-logos.dev}"
MODE="${MODE:-Core}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DAEMON_TIMEOUT_SEC="${DAEMON_TIMEOUT_SEC:-30}"
TASK_TIMEOUT_SEC="${TASK_TIMEOUT_SEC:-90}"
CALL_TIMEOUT_SEC="${CALL_TIMEOUT_SEC:-8}"
DISCOVERY_TOPIC="${DISCOVERY_TOPIC:-/logos-agent/1/a2a-smoke-discovery/json}"
TASK_ID="${TASK_ID:-task-a2a-smoke-$(date -u +%Y%m%dT%H%M%SZ)}"
CLIENT_ADDRESS="${CLIENT_ADDRESS:-a2a-smoke-client-agent}"
SERVER_ADDRESS="${SERVER_ADDRESS:-a2a-smoke-server-agent}"
TASK_AMOUNT="${TASK_AMOUNT:-0}"
PAYMENT_RECIPIENT="${PAYMENT_RECIPIENT:-}"
PAYMENT_MODE="${PAYMENT_MODE:-public}"
CLIENT_WALLET_CONFIG="${CLIENT_WALLET_CONFIG:-}"
CLIENT_WALLET_STORAGE="${CLIENT_WALLET_STORAGE:-}"
CLIENT_WALLET_PASSWORD="${CLIENT_WALLET_PASSWORD:-wallet-smoke}"
CLIENT_WALLET_ACCOUNT="${CLIENT_WALLET_ACCOUNT:-}"
CLIENT_WALLET_ACCOUNT_IS_PUBLIC="${CLIENT_WALLET_ACCOUNT_IS_PUBLIC:-1}"
CLIENT_WALLET_PRIVATE_KEY_HEX="${CLIENT_WALLET_PRIVATE_KEY_HEX:-}"
SERVER_LEZ_ACCOUNT="${SERVER_LEZ_ACCOUNT:-}"
SERVER_WALLET_CONFIG="${SERVER_WALLET_CONFIG:-}"
SERVER_WALLET_STORAGE="${SERVER_WALLET_STORAGE:-}"
SERVER_WALLET_PASSWORD="${SERVER_WALLET_PASSWORD:-wallet-smoke}"
SERVER_WALLET_PRIVATE_KEY_HEX="${SERVER_WALLET_PRIVATE_KEY_HEX:-}"
CANCEL_AFTER_SUBMIT="${CANCEL_AFTER_SUBMIT:-0}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-a2a-smoke.sh [options]

Starts two isolated Logos Core daemons, loads logos_agent and dependencies,
starts Delivery in both agents, subscribes the client to a fixed A2A status
topic, submits a task to the server agent, and waits until the A2A task
lifecycle reaches TASK_STATE_COMPLETED on both sides.

Options:
  --preset VALUE        Delivery preset. Default: logos.dev.
  --mode VALUE          Delivery node mode. Default: Core.
  --log-level VALUE     Delivery log level. Default: INFO.
  --task-timeout SEC    A2A task completion timeout. Default: 90.
  --daemon-timeout SEC  Daemon readiness timeout. Default: 30.
  --task-id VALUE       Fixed task id for reproducible status topic.
  --amount VALUE        Optional LEZ payment amount. Default: 0.
  --payment-recipient P LEZ recipient for paid A2A task.
  --payment-mode MODE   Wallet transfer mode for paid task. Default: public.
  --client-wallet-config P
                        Wallet config path for paid client task.
  --client-wallet-storage P
                        Wallet storage path for paid client task.
  --client-wallet-password P
                        Wallet password when creating client wallet storage.
  --client-wallet-account P
                        Client LEZ account used for payment.
  --client-wallet-private-key HEX
                        Optional public account private key metadata.
  --server-lez-account P
                        Server LEZ account advertised in Agent Card.
  --server-wallet-config P
                        Wallet config path for paid server refund task.
  --server-wallet-storage P
                        Wallet storage path for paid server refund task.
  --server-wallet-password P
                        Wallet password when creating server wallet storage.
  --server-wallet-private-key HEX
                        Optional server public account private key metadata.
  --cancel-after-submit  Submit a paid task that waits for approval, cancel it,
                        and verify refund evidence instead of completion.
  --modules-dir P       Directory containing live modules.
  --logoscore P         logoscore binary path.
  --run-root P          Directory for logs and isolated config.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preset) PRESET="${2:-}"; shift ;;
    --mode) MODE="${2:-}"; shift ;;
    --log-level) LOG_LEVEL="${2:-}"; shift ;;
    --task-timeout) TASK_TIMEOUT_SEC="${2:-}"; shift ;;
    --daemon-timeout) DAEMON_TIMEOUT_SEC="${2:-}"; shift ;;
    --task-id) TASK_ID="${2:-}"; shift ;;
    --amount) TASK_AMOUNT="${2:-}"; shift ;;
    --payment-recipient) PAYMENT_RECIPIENT="${2:-}"; shift ;;
    --payment-mode) PAYMENT_MODE="${2:-}"; shift ;;
    --client-wallet-config) CLIENT_WALLET_CONFIG="${2:-}"; shift ;;
    --client-wallet-storage) CLIENT_WALLET_STORAGE="${2:-}"; shift ;;
    --client-wallet-password) CLIENT_WALLET_PASSWORD="${2:-}"; shift ;;
    --client-wallet-account) CLIENT_WALLET_ACCOUNT="${2:-}"; shift ;;
    --client-wallet-private-key) CLIENT_WALLET_PRIVATE_KEY_HEX="${2:-}"; shift ;;
    --server-lez-account) SERVER_LEZ_ACCOUNT="${2:-}"; shift ;;
    --server-wallet-config) SERVER_WALLET_CONFIG="${2:-}"; shift ;;
    --server-wallet-storage) SERVER_WALLET_STORAGE="${2:-}"; shift ;;
    --server-wallet-password) SERVER_WALLET_PASSWORD="${2:-}"; shift ;;
    --server-wallet-private-key) SERVER_WALLET_PRIVATE_KEY_HEX="${2:-}"; shift ;;
    --cancel-after-submit) CANCEL_AFTER_SUBMIT=1 ;;
    --modules-dir) MODULES_DIR="${2:-}"; shift ;;
    --logoscore) LOGOSCORE="${2:-}"; shift ;;
    --run-root) RUN_ROOT="${2:-}"; shift ;;
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

mkdir -p "$RUN_ROOT"
CLIENT_CFG="$RUN_ROOT/client-core"
SERVER_CFG="$RUN_ROOT/server-core"
CLIENT_LOG="$RUN_ROOT/client.log"
SERVER_LOG="$RUN_ROOT/server.log"
CLIENT_CONFIG_JSON="$RUN_ROOT/client-agent-config.json"
SERVER_CONFIG_JSON="$RUN_ROOT/server-agent-config.json"
mkdir -p "$CLIENT_CFG" "$SERVER_CFG"

CLIENT_PID=""
SERVER_PID=""

cleanup() {
  "$LOGOSCORE" --config-dir "$CLIENT_CFG" stop >/dev/null 2>&1 || true
  "$LOGOSCORE" --config-dir "$SERVER_CFG" stop >/dev/null 2>&1 || true
  if [ -n "$CLIENT_PID" ]; then
    wait "$CLIENT_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$SERVER_PID" ]; then
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}

on_error() {
  local status=$?
  cat >&2 <<EOF
agent A2A smoke failed with exit status $status
run_root: $RUN_ROOT
client log: $CLIENT_LOG
server log: $SERVER_LOG
client config: $CLIENT_CONFIG_JSON
server config: $SERVER_CONFIG_JSON
EOF
  if [ -f "$CLIENT_LOG" ]; then
    echo "--- client log tail ---" >&2
    tail -n 120 "$CLIENT_LOG" >&2 || true
  fi
  if [ -f "$SERVER_LOG" ]; then
    echo "--- server log tail ---" >&2
    tail -n 120 "$SERVER_LOG" >&2 || true
  fi
}

trap cleanup EXIT
trap on_error ERR

wait_for_daemon() {
  local cfg="$1"
  local label="$2"
  local deadline=$((SECONDS + DAEMON_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "$LOGOSCORE" --config-dir "$cfg" status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "logoscore daemon did not become ready for $label: $cfg" >&2
  return 1
}

call_agent() {
  local cfg="$1"
  local method="$2"
  shift 2
  local output
  output="$("$LOGOSCORE" --config-dir "$cfg" call logos_agent "$method" "$@" 2>&1)" || {
    printf '%s\n' "$output" | python3 -c '
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
    return 0
  }
  printf '%s\n' "$output" | python3 -c '
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

call_agent_timeout() {
  local timeout_sec="$1"
  local cfg="$2"
  local method="$3"
  shift 3
  local output
  output="$(timeout "${timeout_sec}s" "$LOGOSCORE" --config-dir "$cfg" call logos_agent "$method" "$@" 2>&1)" || {
    local status=$?
    if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
      printf '{"ok":false,"status":"timeout","message":"logoscore call timed out"}\n'
      return 0
    fi
    printf '%s\n' "$output" | python3 -c '
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
    return 0
  }
  printf '%s\n' "$output" | python3 -c '
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

write_persisted_status_snapshot() {
  local cfg="$1"
  local latest="$2"
  python3 - "$cfg" "$latest" <<'PY'
import json
import pathlib
import sys

cfg = pathlib.Path(sys.argv[1])
latest = pathlib.Path(sys.argv[2])
state_root = cfg / "data" / "logos_agent"
states = sorted(
    state_root.glob("*/state.json"),
    key=lambda path: path.stat().st_mtime,
    reverse=True,
)
if not states:
    raise SystemExit(1)

state_file = states[0]
state = json.loads(state_file.read_text())
payload = {
    "ok": True,
    "source": "persisted_state",
    "state_file": str(state_file),
    "active_tasks": state.get("tasks", []),
    "transactions": state.get("transactions", []),
    "approvals": state.get("approvals", []),
}
latest.write_text(json.dumps(payload, separators=(",", ":")))
PY
}

fetch_status_snapshot() {
  local cfg="$1"
  local label="$2"
  local latest="$3"
  call_agent_timeout "$CALL_TIMEOUT_SEC" "$cfg" invoke meta.status '{}' >"$latest"
  if assert_json_ok "$latest" "$label meta.status" >/dev/null 2>&1; then
    return 0
  fi
  write_persisted_status_snapshot "$cfg" "$latest"
}

write_config() {
  local path="$1"
  local agent_id="$2"
  local address="$3"
  local label="$4"
  local role="$5"
  python3 - "$path" "$agent_id" "$address" "$label" "$role" "$PRESET" "$MODE" "$LOG_LEVEL" "$DISCOVERY_TOPIC" "$TASK_AMOUNT" "$PAYMENT_RECIPIENT" "$CLIENT_WALLET_CONFIG" "$CLIENT_WALLET_STORAGE" "$CLIENT_WALLET_PASSWORD" "$CLIENT_WALLET_ACCOUNT" "$CLIENT_WALLET_ACCOUNT_IS_PUBLIC" "$CLIENT_WALLET_PRIVATE_KEY_HEX" "$SERVER_LEZ_ACCOUNT" "$SERVER_WALLET_CONFIG" "$SERVER_WALLET_STORAGE" "$SERVER_WALLET_PASSWORD" "$SERVER_WALLET_PRIVATE_KEY_HEX" "$CANCEL_AFTER_SUBMIT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
agent_id, address, label, role = sys.argv[2:6]
preset, mode, log_level, discovery_topic = sys.argv[6:10]
amount, payment_recipient = sys.argv[10:12]
client_wallet_config, client_wallet_storage, client_wallet_password = sys.argv[12:15]
client_wallet_account, client_wallet_is_public, client_wallet_private_key = sys.argv[15:18]
server_lez_account = sys.argv[18]
server_wallet_config, server_wallet_storage, server_wallet_password, server_wallet_private_key = sys.argv[19:23]
cancel_after_submit = sys.argv[23] == "1"
client_wallet_exists = pathlib.Path(client_wallet_storage).exists() if client_wallet_storage else False
server_wallet_exists = pathlib.Path(server_wallet_storage).exists() if server_wallet_storage else False
lez_account = client_wallet_account if role == "client" and client_wallet_account else ""
if role == "server" and server_lez_account:
    lez_account = server_lez_account
config = {
    "identity": {
        "agent_id": agent_id,
        "messaging_address": address,
        "lez_account": lez_account,
        "lez_account_is_public": (client_wallet_is_public == "1") if role == "client" else bool(server_lez_account),
    },
    "policy": {
        "per_transaction_limit": "0" if role == "server" and cancel_after_submit else "1",
        "period_limit": "100",
        "period_seconds": 86400,
    },
    "security": {
        "allow_dev_file_cipher": False,
        "allow_dev_a2a_secret": False,
    },
    "delivery": {
        "preset": preset,
        "mode": mode,
        "logLevel": log_level,
    },
    "a2a": {
        "discovery_topic": discovery_topic,
        "publish_on_start": False,
    },
    "agent_card": {
        "name": label,
        "description": "LP-0008 A2A smoke agent",
        "version": "0.1.0",
    },
}
if role == "client" and client_wallet_config and client_wallet_storage:
    config["wallet"] = {
        "config_path": client_wallet_config,
        "storage_path": client_wallet_storage,
        "password": client_wallet_password,
        "create": not client_wallet_exists,
        "create_agent_account": False,
    }
    if client_wallet_account:
        config["wallet"]["public_import_account"] = client_wallet_account
    if client_wallet_private_key:
        config["wallet"]["public_import_private_key_hex"] = client_wallet_private_key
if role == "server" and server_wallet_config and server_wallet_storage:
    config["wallet"] = {
        "config_path": server_wallet_config,
        "storage_path": server_wallet_storage,
        "password": server_wallet_password,
        "create": not server_wallet_exists,
        "create_agent_account": not bool(server_lez_account),
        "create_agent_account_type": "public",
        "register_agent_account": not bool(server_lez_account),
    }
    if server_lez_account:
        config["wallet"]["public_import_account"] = server_lez_account
    if server_wallet_private_key:
        config["wallet"]["public_import_private_key_hex"] = server_wallet_private_key
if role == "server" and amount not in ("", "0") and payment_recipient:
    config["agent_card"]["payment"] = {
        "currency": "LEZ",
        "price": amount,
        "recipient": payment_recipient,
    }
path.write_text(json.dumps(config, separators=(",", ":")))
PY
}

json_field() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text())
for part in sys.argv[2].split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
    if value is None:
        break
if isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
elif value is not None:
    print(value)
PY
}

assert_start_adapters() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
label = sys.argv[2]
adapters = payload.get("adapters", {})
delivery = adapters.get("messaging", {}).get("delivery", {})
a2a = adapters.get("a2a", {})
if delivery.get("ok") is not True:
    raise SystemExit(f"{label}: Delivery did not start cleanly: {json.dumps(payload, indent=2)[:1600]}")
if a2a.get("ok") is not True:
    raise SystemExit(f"{label}: A2A task subscription did not start cleanly: {json.dumps(payload, indent=2)[:1600]}")
PY
}

task_params() {
  python3 - "$SERVER_ADDRESS" "$TASK_ID" "$TASK_AMOUNT" "$PAYMENT_RECIPIENT" "$PAYMENT_MODE" "$CANCEL_AFTER_SUBMIT" <<'PY'
import json
import sys

payload = {
    "agent_address": sys.argv[1],
    "task_id": sys.argv[2],
    "skill": "wallet.send" if sys.argv[6] == "1" else "meta.status",
    "params": {
        "recipient": sys.argv[4],
        "amount": "1",
        "mode": sys.argv[5] or "public",
    } if sys.argv[6] == "1" else {},
    "amount": sys.argv[3],
}
if sys.argv[4]:
    payload["payment_recipient"] = sys.argv[4]
if sys.argv[5]:
    payload["payment_mode"] = sys.argv[5]
print(json.dumps(payload, separators=(",", ":")))
PY
}

cancel_params() {
  python3 - "$SERVER_ADDRESS" "$TASK_ID" <<'PY'
import json
import sys

print(json.dumps({
    "agent_address": sys.argv[1],
    "task_id": sys.argv[2],
    "reason": "paid A2A cancellation/refund smoke",
}, separators=(",", ":")))
PY
}

subscribe_params() {
  python3 - "$TASK_ID" <<'PY'
import json
import sys

print(json.dumps({"task_id": sys.argv[1]}, separators=(",", ":")))
PY
}

wait_for_completed_task() {
  local cfg="$1"
  local label="$2"
  local latest="$3"
  local deadline=$((SECONDS + TASK_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    fetch_status_snapshot "$cfg" "$label" "$latest"
    if python3 - "$latest" "$TASK_ID" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
task_id = sys.argv[2]
for task in payload.get("active_tasks", []):
    if task.get("task_id") == task_id and task.get("state") == "TASK_STATE_COMPLETED":
        result = task.get("result", {})
        if isinstance(result, dict) and result.get("ok") is True:
            raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for $label to record completed task $TASK_ID" >&2
  return 1
}

wait_for_task_state() {
  local cfg="$1"
  local label="$2"
  local state="$3"
  local latest="$4"
  local deadline=$((SECONDS + TASK_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    fetch_status_snapshot "$cfg" "$label" "$latest"
    if assert_json_ok "$latest" "$label meta.status" >/dev/null 2>&1 && python3 - "$latest" "$TASK_ID" "$state" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
task_id, state = sys.argv[2:4]
for task in payload.get("active_tasks", []):
    if task.get("task_id") == task_id and task.get("state") == state:
        raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for $label to record task $TASK_ID state $state" >&2
  return 1
}

assert_paid_task() {
  local client_status="$1"
  local server_status="$2"
  python3 - "$client_status" "$server_status" "$TASK_ID" "$TASK_AMOUNT" "$PAYMENT_RECIPIENT" <<'PY'
import json
import pathlib
import sys

client_status = json.loads(pathlib.Path(sys.argv[1]).read_text())
server_status = json.loads(pathlib.Path(sys.argv[2]).read_text())
task_id, amount, recipient = sys.argv[3:6]
if amount in ("", "0"):
    raise SystemExit(0)

def task_from(payload):
    for task in payload.get("active_tasks", []):
        if task.get("task_id") == task_id:
            return task
    raise SystemExit(f"task {task_id} not found in {json.dumps(payload, indent=2)[:1600]}")

for label, payload in (("client", client_status), ("server", server_status)):
    task = task_from(payload)
    payment = task.get("payment", {})
    if payment.get("ok") is not True:
        raise SystemExit(f"{label}: missing paid A2A payment receipt: {json.dumps(task, indent=2)[:1800]}")
    if str(payment.get("amount")) != amount or payment.get("recipient") != recipient:
        raise SystemExit(f"{label}: payment receipt mismatch: {json.dumps(payment, indent=2)[:1800]}")
    transfer = payment.get("transfer", {})
    tx = transfer.get("transaction", {})
    result = tx.get("result", {})
    if result.get("success") is not True or not result.get("tx_hash"):
        raise SystemExit(f"{label}: payment transfer did not include successful tx hash: {json.dumps(payment, indent=2)[:1800]}")
PY
}

assert_refunded_task() {
  local server_status="$1"
  python3 - "$server_status" "$TASK_ID" "$TASK_AMOUNT" "$CLIENT_WALLET_ACCOUNT" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
task_id, amount, payer = sys.argv[2:5]
for task in payload.get("active_tasks", []):
    if task.get("task_id") != task_id:
        continue
    if task.get("state") != "TASK_STATE_CANCELED":
        raise SystemExit(f"server task was not canceled: {json.dumps(task, indent=2)[:1800]}")
    payment = task.get("payment", {})
    if payment.get("ok") is not True or str(payment.get("amount")) != amount:
        raise SystemExit(f"server canceled task missing original payment: {json.dumps(task, indent=2)[:1800]}")
    refund = task.get("refund", {})
    if refund.get("ok") is not True:
        raise SystemExit(f"server canceled task missing successful refund: {json.dumps(task, indent=2)[:2200]}")
    if str(refund.get("amount")) != amount or refund.get("recipient") != payer:
        raise SystemExit(f"refund receipt mismatch: {json.dumps(refund, indent=2)[:1800]}")
    result = refund.get("transfer", {}).get("transaction", {}).get("result", {})
    if result.get("success") is not True or not result.get("tx_hash"):
        raise SystemExit(f"refund transfer missing successful tx hash: {json.dumps(refund, indent=2)[:1800]}")
    raise SystemExit(0)
raise SystemExit(f"task {task_id} not found in server status: {json.dumps(payload, indent=2)[:1600]}")
PY
}

"$LOGOSCORE" --config-dir "$CLIENT_CFG" -D -m "$MODULES_DIR" >"$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!
"$LOGOSCORE" --config-dir "$SERVER_CFG" -D -m "$MODULES_DIR" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

wait_for_daemon "$CLIENT_CFG" "client"
wait_for_daemon "$SERVER_CFG" "server"

for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  "$LOGOSCORE" --config-dir "$CLIENT_CFG" load-module "$module" >"$RUN_ROOT/client-load-$module.out"
  "$LOGOSCORE" --config-dir "$SERVER_CFG" load-module "$module" >"$RUN_ROOT/server-load-$module.out"
done

write_config "$CLIENT_CONFIG_JSON" "a2a-smoke-client" "$CLIENT_ADDRESS" "A2A Smoke Client" "client"
write_config "$SERVER_CONFIG_JSON" "a2a-smoke-server" "$SERVER_ADDRESS" "A2A Smoke Server" "server"

call_agent "$CLIENT_CFG" init "$(cat "$CLIENT_CONFIG_JSON")" >"$RUN_ROOT/client-init.json"
assert_json_ok "$RUN_ROOT/client-init.json" "client init"
call_agent "$SERVER_CFG" init "$(cat "$SERVER_CONFIG_JSON")" >"$RUN_ROOT/server-init.json"
assert_json_ok "$RUN_ROOT/server-init.json" "server init"

call_agent "$SERVER_CFG" start >"$RUN_ROOT/server-start.json"
assert_json_ok "$RUN_ROOT/server-start.json" "server start"
assert_start_adapters "$RUN_ROOT/server-start.json" "server"

call_agent "$CLIENT_CFG" start >"$RUN_ROOT/client-start.json"
assert_json_ok "$RUN_ROOT/client-start.json" "client start"
assert_start_adapters "$RUN_ROOT/client-start.json" "client"

if [ "$CANCEL_AFTER_SUBMIT" -eq 1 ] && [ -z "$PAYMENT_RECIPIENT" ]; then
  PAYMENT_RECIPIENT="$(json_field "$RUN_ROOT/server-start.json" "adapters.wallet.account.account")"
  if [ -z "$PAYMENT_RECIPIENT" ]; then
    echo "server did not expose a LEZ payment account" >&2
    exit 1
  fi
fi

call_agent "$CLIENT_CFG" invoke agent.subscribe "$(subscribe_params)" >"$RUN_ROOT/client-subscribe.json"
assert_json_ok "$RUN_ROOT/client-subscribe.json" "client agent.subscribe"

sleep 2

call_agent "$CLIENT_CFG" invoke agent.task "$(task_params)" >"$RUN_ROOT/client-task-submit.json"
assert_json_ok "$RUN_ROOT/client-task-submit.json" "client agent.task"

if [ "$CANCEL_AFTER_SUBMIT" -eq 1 ]; then
  wait_for_task_state "$SERVER_CFG" "server" "TASK_STATE_INPUT_REQUIRED" "$RUN_ROOT/server-meta-status-input-required.json"
  call_agent "$CLIENT_CFG" invoke agent.cancel "$(cancel_params)" >"$RUN_ROOT/client-cancel.json"
  assert_json_ok "$RUN_ROOT/client-cancel.json" "client agent.cancel"
  wait_for_task_state "$SERVER_CFG" "server" "TASK_STATE_CANCELED" "$RUN_ROOT/server-meta-status-canceled.json"
  assert_refunded_task "$RUN_ROOT/server-meta-status-canceled.json"
else
  wait_for_completed_task "$SERVER_CFG" "server" "$RUN_ROOT/server-meta-status-completed.json"
  wait_for_completed_task "$CLIENT_CFG" "client" "$RUN_ROOT/client-meta-status-completed.json"
  assert_paid_task "$RUN_ROOT/client-meta-status-completed.json" "$RUN_ROOT/server-meta-status-completed.json"
fi

python3 - "$RUN_ROOT" "$PRESET" "$MODE" "$TASK_ID" "$CLIENT_ADDRESS" "$SERVER_ADDRESS" "$TASK_AMOUNT" "$CANCEL_AFTER_SUBMIT" <<'PY'
import json
import sys

run_root, preset, mode, task_id, client, server, amount, canceled = sys.argv[1:9]
print(json.dumps({
    "ok": True,
    "run_root": run_root,
    "preset": preset,
    "node_mode": mode,
    "task_id": task_id,
    "client_address": client,
    "server_address": server,
    "paid": amount not in ("", "0"),
    "canceled": canceled == "1",
    "proofs": {
        "client_init": f"{run_root}/client-init.json",
        "server_init": f"{run_root}/server-init.json",
        "client_start": f"{run_root}/client-start.json",
        "server_start": f"{run_root}/server-start.json",
        "client_subscribe": f"{run_root}/client-subscribe.json",
        "client_task_submit": f"{run_root}/client-task-submit.json",
        "client_completed_status": f"{run_root}/client-meta-status-completed.json",
        "server_completed_status": f"{run_root}/server-meta-status-completed.json",
        "client_cancel": f"{run_root}/client-cancel.json",
        "server_canceled_status": f"{run_root}/server-meta-status-canceled.json",
    },
}, indent=2))
PY
