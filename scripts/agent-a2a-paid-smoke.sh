#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/agent-a2a-paid-smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
SCAFFOLD_PROJECT="${SCAFFOLD_PROJECT:-$ROOT/.local/localnet-integration/scaffold-project}"
SCAFFOLD_BIN="${SCAFFOLD_BIN:-}"
LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-$WORKSPACE/logos-blockchain-circuits}"
LOCALNET_TIMEOUT_SEC="${LOCALNET_TIMEOUT_SEC:-180}"
KEEP_LOCALNET="${KEEP_LOCALNET:-0}"
FROM_ADDRESS=""
TO_ADDRESS=""
TASK_AMOUNT="${TASK_AMOUNT:-1}"
CANCEL_REFUND="${CANCEL_REFUND:-0}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-a2a-paid-smoke.sh [options]

Starts scaffold localnet, tops up the client public sender, then runs the A2A
smoke with a real LEZ payment receipt attached to the task.

Options:
  --run-root P            Directory for logs and isolated config.
  --scaffold-project P    Scaffold project containing .scaffold/wallet.
  --scaffold-bin P        logos-scaffold binary path.
  --circuits-dir P        logos-blockchain-circuits path for sequencer.
  --localnet-timeout SEC  Scaffold localnet readiness timeout. Default: 180.
  --amount N              LEZ units to pay. Default: 1.
  --cancel-refund         Cancel an input-required paid task and verify refund.
  --keep-localnet         Leave localnet running on exit.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --scaffold-project) SCAFFOLD_PROJECT="${2:-}"; shift ;;
    --scaffold-bin) SCAFFOLD_BIN="${2:-}"; shift ;;
    --circuits-dir) LOGOS_BLOCKCHAIN_CIRCUITS="${2:-}"; shift ;;
    --localnet-timeout) LOCALNET_TIMEOUT_SEC="${2:-}"; shift ;;
    --amount) TASK_AMOUNT="${2:-}"; shift ;;
    --cancel-refund) CANCEL_REFUND=1 ;;
    --keep-localnet) KEEP_LOCALNET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

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
SCAFFOLD_PROJECT="$(cd "$SCAFFOLD_PROJECT" && pwd)"
LOGOS_BLOCKCHAIN_CIRCUITS="$(cd "$LOGOS_BLOCKCHAIN_CIRCUITS" && pwd)"

mkdir -p "$RUN_ROOT"
RUN_ROOT="$(cd "$RUN_ROOT" && pwd)"
WALLET_DIR="$RUN_ROOT/client-wallet"
SERVER_WALLET_DIR="$RUN_ROOT/server-wallet"
mkdir -p "$WALLET_DIR" "$SERVER_WALLET_DIR"

LOCALNET_STARTED=0

cleanup() {
  if [ "$LOCALNET_STARTED" -eq 1 ] && [ "$KEEP_LOCALNET" -eq 0 ]; then
    (cd "$SCAFFOLD_PROJECT" && LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" "$SCAFFOLD_BIN" localnet stop >/dev/null 2>&1) || true
  fi
}

on_error() {
  local status=$?
  cat >&2 <<EOF
agent paid A2A smoke failed with exit status $status
run_root: $RUN_ROOT
EOF
}

trap cleanup EXIT
trap on_error ERR

normalize_public_address() {
  local address="$1"
  case "$address" in
    Public/*|Private/*) printf '%s\n' "$address" ;;
    *) printf 'Public/%s\n' "$address" ;;
  esac
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

topup_sender() {
  local funded_address
  funded_address="$(normalize_public_address "$FROM_ADDRESS")"
  "$ROOT/scripts/v02-local-faucet.sh" \
    --scaffold-project "$SCAFFOLD_PROJECT" \
    --address "$funded_address" \
    >"$RUN_ROOT/wallet-topup.json" 2>"$RUN_ROOT/wallet-topup.err"
  python3 - "$RUN_ROOT/wallet-topup.json" "$funded_address" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected_address = sys.argv[2]
if str(payload.get("status", "")).lower() != "success":
    raise SystemExit(f"wallet topup did not report success: {json.dumps(payload, indent=2)[:1600]}")
if payload.get("address") and payload.get("address") != expected_address:
    raise SystemExit(f"wallet topup funded {payload.get('address')}, expected {expected_address}")
PY
}

"$SCAFFOLD_BIN" localnet stop >/dev/null 2>&1 || true
(cd "$SCAFFOLD_PROJECT" && LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" "$SCAFFOLD_BIN" localnet start --timeout-sec "$LOCALNET_TIMEOUT_SEC" >"$RUN_ROOT/localnet-start.out" 2>"$RUN_ROOT/localnet-start.err")
LOCALNET_STARTED=1
wait_for_localnet

cp "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" "$WALLET_DIR/wallet_config.json"
cp "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" "$SERVER_WALLET_DIR/wallet_config.json"

"$ROOT/scripts/provision-v02-wallet.sh" \
  --wallet-dir "$WALLET_DIR" \
  --wallet-config "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" \
  --run-root "$RUN_ROOT/provision-client" \
  --agent-id paid-a2a-client-provision >"$RUN_ROOT/client-provision.json"
"$ROOT/scripts/provision-v02-wallet.sh" \
  --wallet-dir "$SERVER_WALLET_DIR" \
  --wallet-config "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" \
  --run-root "$RUN_ROOT/provision-server" \
  --agent-id paid-a2a-server-provision >"$RUN_ROOT/server-provision.json"

FROM_ADDRESS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["account"])' "$RUN_ROOT/client-provision.json")"
TO_ADDRESS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["account"])' "$RUN_ROOT/server-provision.json")"
topup_sender

A2A_ARGS=(
  --run-root "$RUN_ROOT/a2a"
  --task-timeout 120
  --daemon-timeout 45
  --amount "$TASK_AMOUNT"
  --payment-mode public
  --client-wallet-config "$WALLET_DIR/wallet_config.json"
  --client-wallet-storage "$WALLET_DIR/storage.json"
  --client-wallet-password wallet-smoke
  --client-wallet-account "$FROM_ADDRESS"
  --server-wallet-config "$SERVER_WALLET_DIR/wallet_config.json"
  --server-wallet-storage "$SERVER_WALLET_DIR/storage.json"
  --server-wallet-password wallet-smoke
)
if [ "$CANCEL_REFUND" -eq 1 ]; then
  A2A_ARGS+=(
    --cancel-after-submit
    --payment-recipient "$TO_ADDRESS"
    --server-lez-account "$TO_ADDRESS"
  )
else
  A2A_ARGS+=(
    --payment-recipient "$TO_ADDRESS"
    --server-lez-account "$TO_ADDRESS"
  )
fi

"$ROOT/scripts/agent-a2a-smoke.sh" "${A2A_ARGS[@]}" >"$RUN_ROOT/a2a-summary.json"

python3 - "$RUN_ROOT" "$FROM_ADDRESS" "$TO_ADDRESS" "$TASK_AMOUNT" <<'PY'
import json
import pathlib
import sys

run_root = pathlib.Path(sys.argv[1])
summary = json.loads((run_root / "a2a-summary.json").read_text())
client_submit = json.loads((run_root / "a2a" / "client-task-submit.json").read_text())
payment = client_submit.get("task", {}).get("payment", {})
tx_hash = payment.get("transfer", {}).get("transaction", {}).get("result", {}).get("tx_hash")
if not tx_hash:
    raise SystemExit(f"paid A2A summary missing payment tx hash: {json.dumps(client_submit, indent=2)[:1800]}")
refund_tx_hash = ""
server_canceled = run_root / "a2a" / "server-meta-status-canceled.json"
if server_canceled.exists():
    canceled = json.loads(server_canceled.read_text())
    task_id = summary.get("task_id")
    for task in canceled.get("active_tasks", []):
        if task.get("task_id") == task_id:
            refund_tx_hash = task.get("refund", {}).get("transfer", {}).get("transaction", {}).get("result", {}).get("tx_hash", "")
            break

print(json.dumps({
    "ok": True,
    "run_root": str(run_root),
    "from": sys.argv[2],
    "to": sys.argv[3],
    "amount": sys.argv[4],
    "payment_tx_hash": tx_hash,
    "refund_tx_hash": refund_tx_hash,
    "a2a": summary,
    "topup": json.loads((run_root / "wallet-topup.json").read_text()),
}, indent=2))
PY
