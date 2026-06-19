#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-core-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
PRESET="${PRESET:-logos.dev}"
MODE="${MODE:-Core}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
TIMEOUT_SEC="${TIMEOUT_SEC:-20}"
START_AGENT=1

usage() {
  cat <<'USAGE'
Usage: scripts/agent-core-smoke.sh [--preset logos.dev|logos.test] [--no-start-agent]

Starts one isolated Logos Core daemon, loads the LP-0008 dependency modules and
logos_agent, initializes a minimal agent config, optionally starts the runtime,
and verifies representative skills via logoscore call.

Options:
  --preset VALUE     Delivery preset for the agent runtime. Default: logos.dev.
  --mode VALUE       Delivery node mode. Default: Core.
  --log-level VALUE  Delivery log level. Default: INFO.
  --timeout SEC      Daemon readiness timeout. Default: 20.
  --modules-dir P    Directory containing live modules.
  --logoscore P      logoscore binary path.
  --run-root P       Directory for logs and isolated config.
  --no-start-agent   Only prove load/init/skill metadata, without Delivery start.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preset) PRESET="${2:-}"; shift ;;
    --mode) MODE="${2:-}"; shift ;;
    --log-level) LOG_LEVEL="${2:-}"; shift ;;
    --timeout) TIMEOUT_SEC="${2:-}"; shift ;;
    --modules-dir) MODULES_DIR="${2:-}"; shift ;;
    --logoscore) LOGOSCORE="${2:-}"; shift ;;
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --no-start-agent) START_AGENT=0 ;;
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
CORE_CFG="$RUN_ROOT/core"
CORE_LOG="$RUN_ROOT/logoscore.log"
CONFIG_JSON="$RUN_ROOT/agent-config.json"
mkdir -p "$CORE_CFG"

CORE_PID=""

cleanup() {
  "$LOGOSCORE" --config-dir "$CORE_CFG" stop >/dev/null 2>&1 || true
  if [ -n "$CORE_PID" ]; then
    wait "$CORE_PID" >/dev/null 2>&1 || true
  fi
}

on_error() {
  local status=$?
  cat >&2 <<EOF
agent core smoke failed with exit status $status
run_root: $RUN_ROOT
core log: $CORE_LOG
agent config: $CONFIG_JSON
EOF
  if [ -f "$CORE_LOG" ]; then
    echo "--- core log tail ---" >&2
    tail -n 120 "$CORE_LOG" >&2 || true
  fi
}

trap cleanup EXIT
trap on_error ERR

wait_for_daemon() {
  local deadline=$((SECONDS + TIMEOUT_SEC))
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
  "$LOGOSCORE" --config-dir "$CORE_CFG" call logos_agent "$method" "$@" | python3 -c '
import json
import sys

text = sys.stdin.read().strip()
payload = json.loads(text)
if isinstance(payload, dict) and payload.get("status") == "ok" and "result" in payload:
    result = payload["result"]
    if isinstance(result, str):
        print(json.dumps(json.loads(result), separators=(",", ":")))
    else:
        print(json.dumps(result, separators=(",", ":")))
else:
    print(json.dumps(payload, separators=(",", ":")))
'
}

write_config() {
  python3 - "$CONFIG_JSON" "$RUN_ROOT" "$PRESET" "$MODE" "$LOG_LEVEL" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
preset, mode, log_level = sys.argv[3:6]
config = {
    "identity": {
        "agent_id": "core-smoke-agent",
        "messaging_address": "core-smoke-agent",
        "lez_account": "",
        "lez_account_is_public": False,
    },
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
    "a2a": {
        "discovery_topic": "/logos-agent/1/core-smoke-discovery/json",
        "publish_on_start": False,
    },
    "agent_card": {
        "name": "Core Smoke Agent",
        "description": "LP-0008 Logos Core smoke agent",
        "version": "0.1.0",
    },
}
path.write_text(json.dumps(config, separators=(",", ":")))
PY
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
    raise SystemExit(f"{label}: expected ok=true, got: {json.dumps(payload, indent=2)[:1000]}")
PY
}

assert_start_adapters() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
adapters = payload.get("adapters", {})
delivery = adapters.get("messaging", {}).get("delivery", {})
a2a = adapters.get("a2a", {})
if delivery.get("ok") is not True:
    raise SystemExit(f"agent start did not start Delivery cleanly: {json.dumps(payload, indent=2)[:1200]}")
if a2a.get("ok") is not True:
    raise SystemExit(f"agent start did not subscribe A2A task topic cleanly: {json.dumps(payload, indent=2)[:1200]}")
PY
}

assert_skill_surface() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

required = {
    "storage.upload", "storage.download", "storage.list", "storage.share",
    "messaging.send", "messaging.join", "messaging.create_group",
    "wallet.balance", "wallet.send", "wallet.history",
    "program.query", "program.call", "program.deploy",
    "agent.card", "agent.discover", "agent.task", "agent.subscribe", "agent.cancel",
    "meta.skills", "meta.status", "meta.configure",
}
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
skills = payload.get("skills", [])
names = {item.get("name") or item.get("id") for item in skills if isinstance(item, dict)}
missing = sorted(required - names)
if missing:
    raise SystemExit(f"missing required skills: {missing}")
PY
}

"$LOGOSCORE" --config-dir "$CORE_CFG" -D -m "$MODULES_DIR" >"$CORE_LOG" 2>&1 &
CORE_PID=$!
wait_for_daemon

for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  "$LOGOSCORE" --config-dir "$CORE_CFG" load-module "$module" >"$RUN_ROOT/load-$module.out"
done

write_config

call_agent init "$(cat "$CONFIG_JSON")" >"$RUN_ROOT/init.json"
assert_json_ok "$RUN_ROOT/init.json" "init"

call_agent skills >"$RUN_ROOT/skills.json"
assert_json_ok "$RUN_ROOT/skills.json" "skills"
assert_skill_surface "$RUN_ROOT/skills.json"

call_agent invoke meta.skills '{}' >"$RUN_ROOT/meta-skills.json"
assert_json_ok "$RUN_ROOT/meta-skills.json" "meta.skills"

call_agent invoke agent.card '{}' >"$RUN_ROOT/agent-card.json"
assert_json_ok "$RUN_ROOT/agent-card.json" "agent.card"

if [ "$START_AGENT" -eq 1 ]; then
  call_agent start >"$RUN_ROOT/start.json"
  assert_json_ok "$RUN_ROOT/start.json" "start"
  assert_start_adapters "$RUN_ROOT/start.json"

  call_agent invoke meta.status '{}' >"$RUN_ROOT/meta-status.json"
  assert_json_ok "$RUN_ROOT/meta-status.json" "meta.status"
fi

python3 - "$RUN_ROOT" "$PRESET" "$START_AGENT" <<'PY'
import json
import sys

print(json.dumps({
    "ok": True,
    "run_root": sys.argv[1],
    "preset": sys.argv[2],
    "started_agent": sys.argv[3] == "1",
    "proofs": {
        "init": f"{sys.argv[1]}/init.json",
        "skills": f"{sys.argv[1]}/skills.json",
        "meta_skills": f"{sys.argv[1]}/meta-skills.json",
        "agent_card": f"{sys.argv[1]}/agent-card.json",
        "start": f"{sys.argv[1]}/start.json" if sys.argv[3] == "1" else None,
        "meta_status": f"{sys.argv[1]}/meta-status.json" if sys.argv[3] == "1" else None,
    }
}, indent=2))
PY
