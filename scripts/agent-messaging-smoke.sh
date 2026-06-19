#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-messaging-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
PRESET="${PRESET:-logos.dev}"
MODE="${MODE:-Core}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DAEMON_TIMEOUT_SEC="${DAEMON_TIMEOUT_SEC:-30}"
MESSAGE_TIMEOUT_SEC="${MESSAGE_TIMEOUT_SEC:-60}"
GROUP_ID="${GROUP_ID:-/logos-agent/1/messaging-smoke-group/json}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-messaging-smoke.sh [options]

Starts one logos_agent instance and one raw Delivery receiver. The agent creates
a Delivery-backed group, joins it, sends a JSON message through messaging.send,
and the receiver proves the message arrived through Delivery.

Options:
  --preset VALUE           Delivery preset. Default: logos.dev.
  --mode VALUE             Delivery node mode. Default: Core.
  --log-level VALUE        Delivery log level. Default: INFO.
  --group-id VALUE         Delivery topic/group id.
  --message-timeout SEC    Message receive timeout. Default: 60.
  --daemon-timeout SEC     Daemon readiness timeout. Default: 30.
  --modules-dir P          Directory containing live modules.
  --logoscore P            logoscore binary path.
  --run-root P             Directory for logs and isolated config.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preset) PRESET="${2:-}"; shift ;;
    --mode) MODE="${2:-}"; shift ;;
    --log-level) LOG_LEVEL="${2:-}"; shift ;;
    --group-id) GROUP_ID="${2:-}"; shift ;;
    --message-timeout) MESSAGE_TIMEOUT_SEC="${2:-}"; shift ;;
    --daemon-timeout) DAEMON_TIMEOUT_SEC="${2:-}"; shift ;;
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
AGENT_CFG="$RUN_ROOT/agent-core"
RECEIVER_CFG="$RUN_ROOT/receiver-core"
AGENT_LOG="$RUN_ROOT/agent.log"
RECEIVER_LOG="$RUN_ROOT/receiver.log"
AGENT_CONFIG_JSON="$RUN_ROOT/agent-config.json"
EVENTS="$RUN_ROOT/receiver-events.ndjson"
WATCH_LOG="$RUN_ROOT/watch.stderr.log"
mkdir -p "$AGENT_CFG" "$RECEIVER_CFG"

AGENT_PID=""
RECEIVER_PID=""
WATCH_PID=""

cleanup() {
  if [ -n "$WATCH_PID" ]; then
    kill "$WATCH_PID" >/dev/null 2>&1 || true
  fi
  "$LOGOSCORE" --config-dir "$AGENT_CFG" stop >/dev/null 2>&1 || true
  "$LOGOSCORE" --config-dir "$RECEIVER_CFG" stop >/dev/null 2>&1 || true
  if [ -n "$AGENT_PID" ]; then
    wait "$AGENT_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$RECEIVER_PID" ]; then
    wait "$RECEIVER_PID" >/dev/null 2>&1 || true
  fi
}

on_error() {
  local status=$?
  cat >&2 <<EOF
agent messaging smoke failed with exit status $status
run_root: $RUN_ROOT
agent log: $AGENT_LOG
receiver log: $RECEIVER_LOG
events: $EVENTS
watch stderr: $WATCH_LOG
agent config: $AGENT_CONFIG_JSON
EOF
  if [ -f "$AGENT_LOG" ]; then
    echo "--- agent log tail ---" >&2
    tail -n 120 "$AGENT_LOG" >&2 || true
  fi
  if [ -f "$RECEIVER_LOG" ]; then
    echo "--- receiver log tail ---" >&2
    tail -n 120 "$RECEIVER_LOG" >&2 || true
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
  local method="$1"
  shift
  "$LOGOSCORE" --config-dir "$AGENT_CFG" call logos_agent "$method" "$@" | unwrap_core_response
}

call_delivery() {
  local cfg="$1"
  shift
  "$LOGOSCORE" --config-dir "$cfg" call delivery_module "$@"
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

write_agent_config() {
  python3 - "$AGENT_CONFIG_JSON" "$RUN_ROOT" "$PRESET" "$MODE" "$LOG_LEVEL" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
run_root = pathlib.Path(sys.argv[2])
preset, mode, log_level = sys.argv[3:6]
config = {
    "identity": {
        "agent_id": "messaging-smoke-agent",
        "messaging_address": "messaging-smoke-agent",
        "lez_account": "",
        "lez_account_is_public": False,
    },
    "persistence_path": str(run_root / "agent-state"),
    "policy": {
        "per_transaction_limit": "0",
        "period_limit": "0",
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
    "agent_card": {
        "name": "Messaging Smoke Agent",
        "description": "LP-0008 messaging smoke agent",
        "version": "0.1.0",
    },
}
path.write_text(json.dumps(config, separators=(",", ":")))
PY
}

node_cfg() {
  python3 - "$PRESET" "$MODE" "$LOG_LEVEL" <<'PY'
import json
import sys

print(json.dumps({"preset": sys.argv[1], "mode": sys.argv[2], "logLevel": sys.argv[3]}, separators=(",", ":")))
PY
}

create_group_params() {
  python3 - "$GROUP_ID" <<'PY'
import json
import sys

print(json.dumps({
    "group_id": sys.argv[1],
    "members": ["messaging-smoke-agent", "raw-delivery-receiver"],
}, separators=(",", ":")))
PY
}

join_params() {
  python3 - "$GROUP_ID" <<'PY'
import json
import sys

print(json.dumps({"group_id": sys.argv[1]}, separators=(",", ":")))
PY
}

send_params() {
  python3 - "$GROUP_ID" <<'PY'
import json
import sys

print(json.dumps({
    "recipient": sys.argv[1],
    "transport": "delivery",
    "message": {
        "kind": "messaging.smoke",
        "text": "hello from logos_agent messaging.send",
    },
}, separators=(",", ":")))
PY
}

assert_start_adapters() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
delivery = payload.get("adapters", {}).get("messaging", {}).get("delivery", {})
if delivery.get("ok") is not True:
    raise SystemExit(f"agent start did not start Delivery cleanly: {json.dumps(payload, indent=2)[:1600]}")
PY
}

assert_group_result() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" "$GROUP_ID" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
label = sys.argv[2]
expected = sys.argv[3]
if payload.get("group_id") != expected:
    raise SystemExit(f"{label}: expected group_id {expected}, got {json.dumps(payload, indent=2)[:1200]}")
if payload.get("transport") != "delivery_topic":
    raise SystemExit(f"{label}: expected delivery_topic transport, got {json.dumps(payload, indent=2)[:1200]}")
PY
}

assert_send_result() {
  local file="$1"
  python3 - "$file" "$GROUP_ID" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = sys.argv[2]
if payload.get("topic") != expected:
    raise SystemExit(f"messaging.send returned wrong topic: {json.dumps(payload, indent=2)[:1200]}")
request_id = payload.get("request_id")
if not isinstance(request_id, str) or not request_id:
    raise SystemExit(f"messaging.send did not return request_id: {json.dumps(payload, indent=2)[:1200]}")
PY
}

wait_for_delivery_message() {
  local deadline=$((SECONDS + MESSAGE_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if python3 - "$EVENTS" "$GROUP_ID" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
topic = sys.argv[2]
if not path.exists():
    raise SystemExit(1)
for line in path.read_text(errors="replace").splitlines():
    if topic not in line or "messaging.smoke" not in line:
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        raise SystemExit(0)
    if topic in json.dumps(payload) and "messaging.smoke" in json.dumps(payload):
        raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for Delivery message on $GROUP_ID" >&2
  return 1
}

"$LOGOSCORE" --config-dir "$AGENT_CFG" -D -m "$MODULES_DIR" >"$AGENT_LOG" 2>&1 &
AGENT_PID=$!
"$LOGOSCORE" --config-dir "$RECEIVER_CFG" -D -m "$MODULES_DIR" >"$RECEIVER_LOG" 2>&1 &
RECEIVER_PID=$!

wait_for_daemon "$AGENT_CFG" "agent"
wait_for_daemon "$RECEIVER_CFG" "receiver"

for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  "$LOGOSCORE" --config-dir "$AGENT_CFG" load-module "$module" >"$RUN_ROOT/agent-load-$module.out"
done
"$LOGOSCORE" --config-dir "$RECEIVER_CFG" load-module delivery_module >"$RUN_ROOT/receiver-load-delivery_module.out"

write_agent_config
call_agent init "$(cat "$AGENT_CONFIG_JSON")" >"$RUN_ROOT/agent-init.json"
assert_json_ok "$RUN_ROOT/agent-init.json" "agent init"
call_agent start >"$RUN_ROOT/agent-start.json"
assert_json_ok "$RUN_ROOT/agent-start.json" "agent start"
assert_start_adapters "$RUN_ROOT/agent-start.json"

call_delivery "$RECEIVER_CFG" createNode "$(node_cfg)" >"$RUN_ROOT/receiver-create-node.out"
call_delivery "$RECEIVER_CFG" start >"$RUN_ROOT/receiver-start.out"
call_delivery "$RECEIVER_CFG" subscribe "$GROUP_ID" >"$RUN_ROOT/receiver-subscribe.out"

: > "$EVENTS"
: > "$WATCH_LOG"
timeout "$MESSAGE_TIMEOUT_SEC" "$LOGOSCORE" --config-dir "$RECEIVER_CFG" watch delivery_module --event messageReceived --json >"$EVENTS" 2>"$WATCH_LOG" &
WATCH_PID=$!
sleep 2

call_agent invoke messaging.create_group "$(create_group_params)" >"$RUN_ROOT/messaging-create-group.json"
assert_json_ok "$RUN_ROOT/messaging-create-group.json" "messaging.create_group"
assert_group_result "$RUN_ROOT/messaging-create-group.json" "messaging.create_group"

call_agent invoke messaging.join "$(join_params)" >"$RUN_ROOT/messaging-join.json"
assert_json_ok "$RUN_ROOT/messaging-join.json" "messaging.join"
assert_group_result "$RUN_ROOT/messaging-join.json" "messaging.join"

call_agent invoke messaging.send "$(send_params)" >"$RUN_ROOT/messaging-send.json"
assert_json_ok "$RUN_ROOT/messaging-send.json" "messaging.send"
assert_send_result "$RUN_ROOT/messaging-send.json"

wait_for_delivery_message

call_agent invoke meta.status '{}' >"$RUN_ROOT/meta-status.json"
assert_json_ok "$RUN_ROOT/meta-status.json" "meta.status"

python3 - "$RUN_ROOT" "$PRESET" "$MODE" "$GROUP_ID" "$EVENTS" <<'PY'
import json
import pathlib
import sys

run_root, preset, mode, group_id, events = sys.argv[1:6]
meta_status = json.loads((pathlib.Path(run_root) / "meta-status.json").read_text())
persistence_path = pathlib.Path(meta_status["persistence_path"])
state_path = persistence_path / "state.json"
state = json.loads(state_path.read_text())
messages = state.get("messages", [])
if not any(
    msg.get("transport") == "delivery"
    and msg.get("direction") == "out"
    and msg.get("topic") == group_id
    and msg.get("payload", {}).get("kind") == "messaging.smoke"
    for msg in messages
):
    raise SystemExit("agent state did not record the outbound messaging.send payload")

print(json.dumps({
    "ok": True,
    "run_root": run_root,
    "preset": preset,
    "node_mode": mode,
    "group_id": group_id,
    "events": events,
    "proofs": {
        "create_group": f"{run_root}/messaging-create-group.json",
        "join": f"{run_root}/messaging-join.json",
        "send": f"{run_root}/messaging-send.json",
        "meta_status": f"{run_root}/meta-status.json",
        "state": str(state_path),
    },
}, indent=2))
PY
