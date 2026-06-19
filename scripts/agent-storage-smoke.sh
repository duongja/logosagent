#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/logoscore-bin/bin/logoscore}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-storage-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
DAEMON_TIMEOUT_SEC="${DAEMON_TIMEOUT_SEC:-30}"
UPLOAD_TIMEOUT_SEC="${UPLOAD_TIMEOUT_SEC:-90}"
STORAGE_READY_TIMEOUT_SEC="${STORAGE_READY_TIMEOUT_SEC:-75}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-storage-smoke.sh [options]

Starts one isolated Logos Core daemon, loads logos_agent and dependencies,
initializes Storage through the agent config, uploads a local file using the
agent's storage.upload skill, waits for the storageUploadDone event to update
agent state, downloads the content address using storage.download, and compares
the recovered bytes with the original input.

Options:
  --modules-dir P          Directory containing live modules.
  --logoscore P            logoscore binary path.
  --run-root P             Directory for logs and isolated config.
  --daemon-timeout SEC     Daemon readiness timeout. Default: 30.
  --storage-ready-timeout SEC
                           Storage node startup timeout. Default: 75.
  --upload-timeout SEC     Upload event timeout. Default: 90.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --modules-dir) MODULES_DIR="${2:-}"; shift ;;
    --logoscore) LOGOSCORE="${2:-}"; shift ;;
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --daemon-timeout) DAEMON_TIMEOUT_SEC="${2:-}"; shift ;;
    --storage-ready-timeout) STORAGE_READY_TIMEOUT_SEC="${2:-}"; shift ;;
    --upload-timeout) UPLOAD_TIMEOUT_SEC="${2:-}"; shift ;;
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
INPUT_FILE="$RUN_ROOT/input.txt"
OUTPUT_FILE="$RUN_ROOT/downloaded.txt"
LABEL="agent-storage-smoke.txt"
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
agent storage smoke failed with exit status $status
run_root: $RUN_ROOT
core log: $CORE_LOG
storage log: $RUN_ROOT/storage.log
agent config: $CONFIG_JSON
EOF
  if [ -f "$CORE_LOG" ]; then
    echo "--- core log tail ---" >&2
    tail -n 120 "$CORE_LOG" >&2 || true
  fi
  if [ -f "$RUN_ROOT/storage.log" ]; then
    echo "--- storage log tail ---" >&2
    tail -n 120 "$RUN_ROOT/storage.log" >&2 || true
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

wait_for_storage_ready() {
  local deadline=$((SECONDS + STORAGE_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$RUN_ROOT/storage.log" ] && grep -F "Started Storage node" "$RUN_ROOT/storage.log" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for Storage node startup" >&2
  return 1
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
    raise SystemExit(f"{label}: expected ok=true, got: {json.dumps(payload, indent=2)[:1200]}")
PY
}

write_config() {
  python3 - "$CONFIG_JSON" "$RUN_ROOT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
config = {
    "identity": {
        "agent_id": "storage-smoke-agent",
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
    "storage": {
        "data-dir": str(root / "storage"),
        "log-level": "INFO",
        "log-file": str(root / "storage.log"),
    },
}
path.write_text(json.dumps(config, separators=(",", ":")))
PY
}

write_input() {
  python3 - "$INPUT_FILE" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text("LP-0008 agent storage smoke payload\nAES-GCM round trip\n", encoding="utf-8")
PY
}

json_params() {
  python3 - "$@" <<'PY'
import json
import sys

mode = sys.argv[1]
if mode == "upload":
    print(json.dumps({"path": sys.argv[2], "label": sys.argv[3]}, separators=(",", ":")))
elif mode == "download":
    print(json.dumps({"address": sys.argv[2], "path": sys.argv[3]}, separators=(",", ":")))
elif mode == "share":
    print(json.dumps({
        "address": sys.argv[2],
        "recipient": "storage-smoke-recipient",
        "recipient_public_key_hex": sys.argv[3],
    }, separators=(",", ":")))
else:
    raise SystemExit(f"unknown json params mode: {mode}")
PY
}

recipient_public_key() {
  python3 - "$RUN_ROOT/meta-status.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
key = payload.get("identity", {}).get("encryption", {}).get("public_key_hex", "")
if not isinstance(key, str) or len(bytes.fromhex(key)) != 32:
    raise SystemExit(f"could not extract a 32-byte encryption public key from meta.status: {json.dumps(payload, indent=2)[:1200]}")
print(key)
PY
}

assert_share_ok() {
  local file="$1"
  python3 - "$file" "$ADDRESS" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
address = sys.argv[2]
if payload.get("ok") is not True:
    raise SystemExit(f"storage.share failed: {json.dumps(payload, indent=2)[:1600]}")
share = payload.get("share", {})
if share.get("address") != address:
    raise SystemExit(f"storage.share returned wrong address: {json.dumps(payload, indent=2)[:1600]}")
encryption = share.get("encryption", {})
if "key_hex" in encryption:
    raise SystemExit("storage.share exposed raw key_hex")
key_wrap = encryption.get("key_wrap", {})
if not key_wrap.get("sender_ephemeral_public_key_hex") or not key_wrap.get("wrapped_key_hex"):
    raise SystemExit(f"storage.share missing wrapped key material: {json.dumps(payload, indent=2)[:1600]}")
PY
}

wait_for_uploaded_address() {
  local deadline=$((SECONDS + UPLOAD_TIMEOUT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    call_agent invoke storage.list '{}' >"$RUN_ROOT/storage-list-latest.json"
    assert_json_ok "$RUN_ROOT/storage-list-latest.json" "storage.list"
    local address
    address=$(python3 - "$RUN_ROOT/storage-list-latest.json" "$LABEL" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
label = sys.argv[2]
for item in payload.get("files", []):
    if item.get("label") == label and item.get("status") == "uploaded":
        address = item.get("address", "")
        session = item.get("upload_session", "")
        if address and address != session:
            print(address)
            raise SystemExit(0)
raise SystemExit(1)
PY
    ) && {
      printf '%s\n' "$address"
      return 0
    }
    sleep 1
  done
  echo "timed out waiting for storage upload completion event" >&2
  return 1
}

"$LOGOSCORE" --config-dir "$CORE_CFG" -D -m "$MODULES_DIR" >"$CORE_LOG" 2>&1 &
CORE_PID=$!
wait_for_daemon

for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  "$LOGOSCORE" --config-dir "$CORE_CFG" load-module "$module" >"$RUN_ROOT/load-$module.out"
done

write_config
write_input

call_agent init "$(cat "$CONFIG_JSON")" >"$RUN_ROOT/init.json"
assert_json_ok "$RUN_ROOT/init.json" "init"

call_agent start >"$RUN_ROOT/start.json"
assert_json_ok "$RUN_ROOT/start.json" "start"
python3 - "$RUN_ROOT/start.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
storage = payload.get("adapters", {}).get("storage", {})
if storage.get("ok") is not True or storage.get("configured") is not True:
    raise SystemExit(f"storage adapter did not start cleanly: {json.dumps(payload, indent=2)[:1200]}")
PY

wait_for_storage_ready

call_agent invoke storage.upload "$(json_params upload "$INPUT_FILE" "$LABEL")" >"$RUN_ROOT/upload.json"
assert_json_ok "$RUN_ROOT/upload.json" "storage.upload"

ADDRESS="$(wait_for_uploaded_address)"
cp "$RUN_ROOT/storage-list-latest.json" "$RUN_ROOT/storage-list-uploaded.json"

call_agent invoke meta.status '{}' >"$RUN_ROOT/meta-status.json"
assert_json_ok "$RUN_ROOT/meta-status.json" "meta.status"
RECIPIENT_PUBLIC_KEY="$(recipient_public_key)"
call_agent invoke storage.share "$(json_params share "$ADDRESS" "$RECIPIENT_PUBLIC_KEY")" >"$RUN_ROOT/share.json"
assert_share_ok "$RUN_ROOT/share.json"

call_agent invoke storage.download "$(json_params download "$ADDRESS" "$OUTPUT_FILE")" >"$RUN_ROOT/download.json"
assert_json_ok "$RUN_ROOT/download.json" "storage.download"

cmp "$INPUT_FILE" "$OUTPUT_FILE"

python3 - "$RUN_ROOT" "$ADDRESS" "$INPUT_FILE" "$OUTPUT_FILE" <<'PY'
import json
import pathlib
import sys

run_root, address, input_file, output_file = sys.argv[1:5]
print(json.dumps({
    "ok": True,
    "run_root": run_root,
    "address": address,
    "input": input_file,
    "downloaded": output_file,
    "proofs": {
        "init": f"{run_root}/init.json",
        "start": f"{run_root}/start.json",
        "upload": f"{run_root}/upload.json",
        "storage_list_uploaded": f"{run_root}/storage-list-uploaded.json",
        "share": f"{run_root}/share.json",
        "download": f"{run_root}/download.json",
        "storage_log": f"{run_root}/storage.log",
    },
}, indent=2))
PY
