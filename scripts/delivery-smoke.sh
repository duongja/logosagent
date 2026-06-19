#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/delivery-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
PRESET="${PRESET:-logos.dev}"
MODE="${MODE:-Core}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
TOPIC="${TOPIC:-/logos-agent/1/smoke-json/json}"
TIMEOUT_SEC="${TIMEOUT_SEC:-45}"
API_ONLY=0

usage() {
  cat <<'USAGE'
Usage: scripts/delivery-smoke.sh [--preset logos.dev|logos.test] [--mode Core|Edge|noMode] [--api-only]

Starts two isolated logoscore daemons, loads delivery_module in each, creates
Delivery nodes with the selected preset, subscribes the receiver to a LIP-23
content topic, sends a JSON payload from the sender, and waits for a
messageReceived event.

Options:
  --preset VALUE   Delivery preset to pass to createNode. Default: logos.dev.
  --mode VALUE     Delivery node mode. Default: Core.
  --log-level VAL  Delivery log level. Default: INFO.
  --topic VALUE    Content topic. Default: /logos-agent/1/smoke-json/json.
  --timeout SEC    Event wait timeout. Default: 45.
  --modules-dir P  Directory containing delivery_module.
  --logoscore P    logoscore binary path.
  --run-root P     Directory for logs and isolated config dirs.
  --api-only       Stop after createNode/start/subscribe/send succeeds.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preset) PRESET="$2"; shift ;;
    --mode) MODE="$2"; shift ;;
    --log-level) LOG_LEVEL="$2"; shift ;;
    --topic) TOPIC="$2"; shift ;;
    --timeout) TIMEOUT_SEC="$2"; shift ;;
    --modules-dir) MODULES_DIR="$2"; shift ;;
    --logoscore) LOGOSCORE="$2"; shift ;;
    --run-root) RUN_ROOT="$2"; shift ;;
    --api-only) API_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ ! -x "$LOGOSCORE" ]; then
  echo "logoscore not found or not executable: $LOGOSCORE" >&2
  exit 1
fi
if [ ! -d "$MODULES_DIR/delivery_module" ]; then
  echo "delivery_module not found under modules dir: $MODULES_DIR" >&2
  exit 1
fi

mkdir -p "$RUN_ROOT"
RX_CFG="$RUN_ROOT/receiver-core"
TX_CFG="$RUN_ROOT/sender-core"
mkdir -p "$RX_CFG" "$TX_CFG"
RX_LOG="$RUN_ROOT/receiver.log"
TX_LOG="$RUN_ROOT/sender.log"
EVENTS="$RUN_ROOT/receiver-events.ndjson"
WATCH_LOG="$RUN_ROOT/watch.stderr.log"
PAYLOAD="$(python3 -c 'import json,sys,time; print(json.dumps({"kind":"delivery.smoke","message":"hello","sent_at":time.time()}, separators=(",", ":")))')"
NODE_CFG="$(python3 - "$PRESET" "$MODE" "$LOG_LEVEL" <<'PY'
import json
import sys
print(json.dumps({"preset": sys.argv[1], "mode": sys.argv[2], "logLevel": sys.argv[3]}, separators=(",", ":")))
PY
)"

RX_PID=""
TX_PID=""
WATCH_PID=""

cleanup() {
  if [ -n "$WATCH_PID" ]; then
    kill "$WATCH_PID" >/dev/null 2>&1 || true
  fi
  "$LOGOSCORE" --config-dir "$RX_CFG" stop >/dev/null 2>&1 || true
  "$LOGOSCORE" --config-dir "$TX_CFG" stop >/dev/null 2>&1 || true
  if [ -n "$RX_PID" ]; then
    wait "$RX_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$TX_PID" ]; then
    wait "$TX_PID" >/dev/null 2>&1 || true
  fi
}

on_error() {
  local status=$?
  cat >&2 <<EOF
delivery smoke failed with exit status $status
run_root: $RUN_ROOT
receiver log: $RX_LOG
sender log: $TX_LOG
watch stderr: $WATCH_LOG
events: $EVENTS
EOF
  if [ -f "$RX_LOG" ]; then
    echo "--- receiver log tail ---" >&2
    tail -n 80 "$RX_LOG" >&2 || true
  fi
  if [ -f "$TX_LOG" ]; then
    echo "--- sender log tail ---" >&2
    tail -n 80 "$TX_LOG" >&2 || true
  fi
}

trap cleanup EXIT
trap on_error ERR

wait_for_daemon() {
  local cfg="$1"
  local deadline=$((SECONDS + 20))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "$LOGOSCORE" --config-dir "$cfg" status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "logoscore daemon did not become ready for $cfg" >&2
  return 1
}

call_delivery() {
  local cfg="$1"
  shift
  "$LOGOSCORE" --config-dir "$cfg" call delivery_module "$@"
}

"$LOGOSCORE" --config-dir "$RX_CFG" -D -m "$MODULES_DIR" >"$RX_LOG" 2>&1 &
RX_PID=$!
"$LOGOSCORE" --config-dir "$TX_CFG" -D -m "$MODULES_DIR" >"$TX_LOG" 2>&1 &
TX_PID=$!

wait_for_daemon "$RX_CFG"
wait_for_daemon "$TX_CFG"

"$LOGOSCORE" --config-dir "$RX_CFG" load-module delivery_module >/dev/null
"$LOGOSCORE" --config-dir "$TX_CFG" load-module delivery_module >/dev/null

call_delivery "$RX_CFG" createNode "$NODE_CFG" >/dev/null
call_delivery "$TX_CFG" createNode "$NODE_CFG" >/dev/null
call_delivery "$RX_CFG" start >/dev/null
call_delivery "$TX_CFG" start >/dev/null
call_delivery "$RX_CFG" subscribe "$TOPIC" >/dev/null

if [ "$API_ONLY" -eq 0 ]; then
  : > "$EVENTS"
  : > "$WATCH_LOG"
  timeout "$TIMEOUT_SEC" "$LOGOSCORE" --config-dir "$RX_CFG" watch delivery_module --event messageReceived --json >"$EVENTS" 2>"$WATCH_LOG" &
  WATCH_PID=$!
  sleep 2
fi

call_delivery "$TX_CFG" send "$TOPIC" "$PAYLOAD" >/dev/null

if [ "$API_ONLY" -eq 1 ]; then
  python3 - "$RUN_ROOT" "$PRESET" "$MODE" "$TOPIC" <<'PY'
import json
import sys
print(json.dumps({
    "ok": True,
    "mode": "api-only",
    "run_root": sys.argv[1],
    "preset": sys.argv[2],
    "node_mode": sys.argv[3],
    "topic": sys.argv[4],
}, indent=2))
PY
  exit 0
fi

deadline=$((SECONDS + TIMEOUT_SEC))
while [ "$SECONDS" -lt "$deadline" ]; do
  if grep -F "$TOPIC" "$EVENTS" >/dev/null 2>&1; then
    python3 - "$RUN_ROOT" "$PRESET" "$MODE" "$TOPIC" "$EVENTS" <<'PY'
import json
import sys
print(json.dumps({
    "ok": True,
    "mode": "end-to-end",
    "run_root": sys.argv[1],
    "preset": sys.argv[2],
    "node_mode": sys.argv[3],
    "topic": sys.argv[4],
    "events": sys.argv[5],
}, indent=2))
PY
    exit 0
  fi
  sleep 1
done

cat >&2 <<EOF
delivery smoke did not observe messageReceived for $TOPIC within ${TIMEOUT_SEC}s
run_root: $RUN_ROOT
receiver log: $RX_LOG
sender log: $TX_LOG
watch stderr: $WATCH_LOG
events: $EVENTS
EOF
exit 1
