#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-}"
LGPM="${LGPM:-}"
BASECAMP_LGX_ROOT="${BASECAMP_LGX_ROOT:-$ROOT/.local/artifacts/basecamp-lgx}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/owner-chat-agent/$(date -u +%Y%m%dT%H%M%SZ)-live}"
CHAT_PORT="${CHAT_PORT:-60115}"
SYSTEMD_UNIT="${SYSTEMD_UNIT:-logos-agent-owner-chat-$(date -u +%Y%m%dT%H%M%SZ)}"
AGENT_ID="${AGENT_ID:-owner-chat-agent}"
AGENT_NAME="${AGENT_NAME:-Owner Chat Agent}"
AGENT_DESCRIPTION="${AGENT_DESCRIPTION:-LP-0008 owner-channel test agent}"

usage() {
  cat <<'USAGE'
Usage: scripts/start-owner-chat-agent.sh [options]

Starts a live headless logos_agent instance for the Basecamp owner-chat proof
and prints a fresh chat intro bundle for Basecamp.

Options:
  --run-root PATH       Output/run directory. Default: .local/owner-chat-agent/<timestamp>-live
  --chat-port PORT      First Chat port to try. Default: 60115
  --logoscore PATH      logoscore binary path.
  --lgpm PATH           lgpm binary path.
  --basecamp-lgx-root P Basecamp LGX artifact root. Default: .local/artifacts/basecamp-lgx
  --no-systemd          Use nohup instead of systemd-run --user.

Environment variables with the same names are also supported:
  RUN_ROOT, CHAT_PORT, LOGOSCORE, LGPM, BASECAMP_LGX_ROOT, SYSTEMD_UNIT
USAGE
}

USE_SYSTEMD=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-root)
      shift
      RUN_ROOT="${1:-}"
      ;;
    --chat-port)
      shift
      CHAT_PORT="${1:-}"
      ;;
    --logoscore)
      shift
      LOGOSCORE="${1:-}"
      ;;
    --lgpm)
      shift
      LGPM="${1:-}"
      ;;
    --basecamp-lgx-root)
      shift
      BASECAMP_LGX_ROOT="${1:-}"
      ;;
    --no-systemd)
      USE_SYSTEMD=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

find_logoscore() {
  if [ -n "$LOGOSCORE" ] && [ -x "$LOGOSCORE" ]; then
    printf '%s\n' "$LOGOSCORE"
    return 0
  fi
  if [ -x "$ROOT/.local/logoscore-bin/bin/logoscore" ]; then
    printf '%s\n' "$ROOT/.local/logoscore-bin/bin/logoscore"
    return 0
  fi
  if command -v logoscore >/dev/null 2>&1; then
    command -v logoscore
    return 0
  fi
  return 1
}

find_lgpm() {
  if [ -n "$LGPM" ] && [ -x "$LGPM" ]; then
    printf '%s\n' "$LGPM"
    return 0
  fi
  if command -v lgpm >/dev/null 2>&1; then
    command -v lgpm
    return 0
  fi
  for candidate in /nix/store/*-logos-package-manager-cli-*/bin/lgpm; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

LOGOSCORE="$(find_logoscore)" || {
  echo "logoscore not found. Set LOGOSCORE=/path/to/logoscore." >&2
  exit 1
}
LOGOSCORE="$(cd "$(dirname "$LOGOSCORE")" && pwd)/$(basename "$LOGOSCORE")"

LGPM="$(find_lgpm)" || {
  echo "lgpm not found. Set LGPM=/path/to/lgpm." >&2
  exit 1
}
LGPM="$(cd "$(dirname "$LGPM")" && pwd)/$(basename "$LGPM")"

RUN_ROOT="$(mkdir -p "$(dirname "$RUN_ROOT")" && cd "$(dirname "$RUN_ROOT")" && pwd)/$(basename "$RUN_ROOT")"
BASECAMP_LGX_ROOT="$(mkdir -p "$BASECAMP_LGX_ROOT" && cd "$BASECAMP_LGX_ROOT" && pwd)"

if [ ! -d "$BASECAMP_LGX_ROOT" ]; then
  if [ -x "$ROOT/scripts/package-live-modules-lgx.sh" ]; then
    "$ROOT/scripts/package-live-modules-lgx.sh" --out-root "$BASECAMP_LGX_ROOT"
  fi
fi

modules=(delivery_module storage_module chat_module logos_execution_zone logos_agent)
for module in "${modules[@]}"; do
  lgx="$BASECAMP_LGX_ROOT/$module/$module.lgx"
  if [ ! -f "$lgx" ]; then
    echo "missing LGX: $lgx" >&2
    echo "Run: ./scripts/package-live-modules-lgx.sh" >&2
    exit 1
  fi
done

mkdir -p "$RUN_ROOT/core" "$RUN_ROOT/modules"

port="$CHAT_PORT"
if command -v ss >/dev/null 2>&1; then
  while ss -ltn "sport = :$port" | grep -q LISTEN; do
    port=$((port + 1))
  done
fi

for module in "${modules[@]}"; do
  "$LGPM" --modules-dir "$RUN_ROOT/modules" install \
    --file "$BASECAMP_LGX_ROOT/$module/$module.lgx" \
    >"$RUN_ROOT/install-$module.out" 2>&1
done

python3 - "$RUN_ROOT/agent-config.json" "$RUN_ROOT" "$AGENT_ID" "$AGENT_NAME" "$AGENT_DESCRIPTION" "$port" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
agent_id = sys.argv[3]
agent_name = sys.argv[4]
description = sys.argv[5]
port = int(sys.argv[6])

config = {
    "identity": {
        "agent_id": agent_id,
        "messaging_address": agent_id,
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
    "runtime": {
        "async_start": True,
    },
    "autostart_storage": False,
    "chat": {
        "name": agent_name,
        "port": port,
        "clusterId": 2,
        "shardId": 1,
        "create_intro_bundle": True,
        "owner_conversation_id": "",
        "owner_intro_bundle": "",
    },
    "agent_card": {
        "name": agent_name,
        "description": description,
        "version": "0.1.0",
    },
}

path.write_text(json.dumps(config, separators=(",", ":")), encoding="utf-8")
PY

launcher="nohup"
if [ "$USE_SYSTEMD" -eq 1 ] && command -v systemd-run >/dev/null 2>&1 \
    && systemctl --user is-system-running >/dev/null 2>&1; then
  systemd-run --user \
    --unit "$SYSTEMD_UNIT" \
    --collect \
    --property=StandardOutput=append:"$RUN_ROOT/logoscore.log" \
    --property=StandardError=append:"$RUN_ROOT/logoscore.log" \
    "$LOGOSCORE" --config-dir "$RUN_ROOT/core" -m "$RUN_ROOT/modules" daemon \
    >"$RUN_ROOT/systemd-run.out"
  printf '%s\n' "$SYSTEMD_UNIT" >"$RUN_ROOT/systemd-unit.txt"
  launcher="systemd-run"
else
  nohup "$LOGOSCORE" --config-dir "$RUN_ROOT/core" -m "$RUN_ROOT/modules" daemon \
    >"$RUN_ROOT/logoscore.log" 2>&1 &
  echo "$!" >"$RUN_ROOT/logoscore.pid"
fi

daemon_ready=0
for _ in $(seq 1 30); do
  if "$LOGOSCORE" --config-dir "$RUN_ROOT/core" status >"$RUN_ROOT/daemon-status.json" 2>"$RUN_ROOT/daemon-status.err"; then
    if grep -q '"status":"running"' "$RUN_ROOT/daemon-status.json"; then
      daemon_ready=1
      break
    fi
  fi
  sleep 1
done

if [ "$daemon_ready" -ne 1 ]; then
  echo "logoscore daemon did not become ready. Log tail:" >&2
  tail -n 80 "$RUN_ROOT/logoscore.log" >&2 || true
  exit 1
fi

for module in "${modules[@]}"; do
  "$LOGOSCORE" --config-dir "$RUN_ROOT/core" load-module "$module" \
    >"$RUN_ROOT/load-$module.out" 2>&1
done

"$LOGOSCORE" --config-dir "$RUN_ROOT/core" call logos_agent init \
  "$(cat "$RUN_ROOT/agent-config.json")" >"$RUN_ROOT/init.raw.json"
"$LOGOSCORE" --config-dir "$RUN_ROOT/core" call logos_agent start \
  >"$RUN_ROOT/start.raw.json"

bundle_ready=0
for _ in $(seq 1 30); do
  "$LOGOSCORE" --config-dir "$RUN_ROOT/core" call logos_agent status \
    >"$RUN_ROOT/status.raw.json" 2>"$RUN_ROOT/status.err" || true
  if python3 - "$RUN_ROOT/status.raw.json" "$RUN_ROOT/chat-intro-bundle.txt" <<'PY'
import json
import pathlib
import sys

outer = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
inner = json.loads(outer.get("result", "{}"))
messaging = inner.get("messaging", {})
bundle = messaging.get("chat_intro_bundle", "")
if not bundle or not messaging.get("chat_started", False):
    raise SystemExit(1)
pathlib.Path(sys.argv[2]).write_text(bundle + "\n", encoding="utf-8")
PY
  then
    bundle_ready=1
    break
  fi
  sleep 1
done

if [ "$bundle_ready" -ne 1 ]; then
  echo "chat intro bundle was not created. Log tail:" >&2
  tail -n 120 "$RUN_ROOT/logoscore.log" >&2 || true
  exit 1
fi

sleep 3
"$LOGOSCORE" --config-dir "$RUN_ROOT/core" status >"$RUN_ROOT/daemon-status-after.json" || true
if ! grep -q '"status":"running"' "$RUN_ROOT/daemon-status-after.json"; then
  echo "logoscore daemon stopped after startup. Log tail:" >&2
  tail -n 120 "$RUN_ROOT/logoscore.log" >&2 || true
  exit 1
fi

printf '%s\n' "$RUN_ROOT" >"$ROOT/.local/owner-chat-agent/latest-run-root.txt"

python3 - "$RUN_ROOT" "$port" <<'PY'
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])
port = sys.argv[2]
bundle = (run / "chat-intro-bundle.txt").read_text(encoding="utf-8").strip()
daemon_status = json.loads((run / "daemon-status-after.json").read_text(encoding="utf-8"))
outer = json.loads((run / "status.raw.json").read_text(encoding="utf-8"))
inner = json.loads(outer["result"])
unit_file = run / "systemd-unit.txt"

summary = {
    "ok": True,
    "run_root": str(run),
    "pid": daemon_status.get("daemon", {}).get("pid"),
    "launcher": "systemd-run" if unit_file.exists() else "nohup",
    "systemd_unit": unit_file.read_text(encoding="utf-8").strip() if unit_file.exists() else "",
    "chat_port": port,
    "modules_loaded": daemon_status.get("modules_summary", {}).get("loaded"),
    "chat_started": inner.get("messaging", {}).get("chat_started"),
    "intro_bundle_file": str(run / "chat-intro-bundle.txt"),
    "intro_bundle": bundle,
}
(run / "owner-chat-live-summary.json").write_text(
    json.dumps(summary, indent=2) + "\n",
    encoding="utf-8",
)
print(json.dumps(summary, indent=2))
PY
