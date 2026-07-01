#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
DEFAULT_COMPAT_RUN=""
if [ -f "$ROOT/.local/last-testnet-evidence-run-root" ]; then
  DEFAULT_COMPAT_RUN="$(cat "$ROOT/.local/last-testnet-evidence-run-root")"
fi

DEFAULT_LEZ_REPO="$WORKSPACE/logos-execution-zone-v0.2.0-testnet"
if [ ! -d "$DEFAULT_LEZ_REPO" ]; then
  DEFAULT_LEZ_REPO="$WORKSPACE/logos-execution-zone-v0.2.0-rc5-testnet"
fi
if [ ! -d "$DEFAULT_LEZ_REPO" ]; then
  DEFAULT_LEZ_REPO="$WORKSPACE/logos-execution-zone-v0.1.2-testnet"
fi
LEZ_REPO="${LEZ_REPO:-$DEFAULT_LEZ_REPO}"
WALLET="${WALLET:-$LEZ_REPO/target/release/wallet}"
TESTNET_URL="${TESTNET_URL:-https://testnet.lez.logos.co/}"
RUN_ROOT="${RUN_ROOT:-$DEFAULT_COMPAT_RUN}"
LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-$HOME/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.0-linux-x86_64}"
FROM="${FROM:-Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV}"
TO="${TO:-Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo}"
AMOUNT="${AMOUNT:-1}"
TASK_ID="${TASK_ID:-task-testnet-paid-a2a-$(date -u +%Y%m%dT%H%M%SZ)}"
SKILL_ID="${SKILL_ID:-messaging.echo}"
CLIENT_AGENT="${CLIENT_AGENT:-logos-agent://testnet/client-paid-a2a}"
SERVER_AGENT="${SERVER_AGENT:-logos-agent://testnet/server-paid-a2a}"
POLL_RETRIES="${POLL_RETRIES:-20}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"

usage() {
  cat <<'USAGE'
Usage: scripts/lez-testnet-a2a-payment-evidence.sh [options]

Submits a real hosted LEZ testnet token transfer and records it as the payment
leg for an A2A-priced agent task. This is intended to complement local A2A
lifecycle evidence; it does not claim to prove the live Delivery transport run.

Options:
  --run-root PATH       Existing hosted-testnet evidence run root with wallet-home.
  --wallet PATH         LEZ wallet binary. Default: ../logos-execution-zone-v0.2.0-testnet/target/release/wallet when present, else ../logos-execution-zone-v0.2.0-rc5-testnet/target/release/wallet, else ../logos-execution-zone-v0.1.2-testnet/target/release/wallet
  --lez-repo PATH       LEZ checkout for local commit/tag metadata.
  --testnet-url URL     Sequencer JSON-RPC URL. Default: https://testnet.lez.logos.co/
  --circuits-dir PATH   LOGOS_BLOCKCHAIN_CIRCUITS directory.
  --from ACCOUNT        Paying public/private account with privacy prefix.
  --to ACCOUNT          Receiving account with privacy prefix.
  --amount VALUE        LEZ amount to transfer. Default: 1.
  --task-id ID          A2A task id for the evidence record.
  --skill-id ID         A2A skill id for the evidence record.
  -h, --help            Show this help.

Environment overrides:
  RUN_ROOT, WALLET, LEZ_REPO, TESTNET_URL, LOGOS_BLOCKCHAIN_CIRCUITS,
  FROM, TO, AMOUNT, TASK_ID, SKILL_ID, CLIENT_AGENT, SERVER_AGENT.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --wallet) WALLET="${2:-}"; shift ;;
    --lez-repo) LEZ_REPO="${2:-}"; shift ;;
    --testnet-url) TESTNET_URL="${2:-}"; shift ;;
    --circuits-dir) LOGOS_BLOCKCHAIN_CIRCUITS="${2:-}"; shift ;;
    --from) FROM="${2:-}"; shift ;;
    --to) TO="${2:-}"; shift ;;
    --amount) AMOUNT="${2:-}"; shift ;;
    --task-id) TASK_ID="${2:-}"; shift ;;
    --skill-id) SKILL_ID="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$RUN_ROOT" ]; then
  echo "missing --run-root and .local/last-testnet-evidence-run-root does not exist" >&2
  exit 1
fi
if [ ! -x "$WALLET" ]; then
  echo "wallet binary not found or not executable: $WALLET" >&2
  exit 1
fi
if [ ! -d "$LOGOS_BLOCKCHAIN_CIRCUITS" ]; then
  echo "LOGOS_BLOCKCHAIN_CIRCUITS directory not found: $LOGOS_BLOCKCHAIN_CIRCUITS" >&2
  exit 1
fi

mkdir -p "$RUN_ROOT"
RUN_ROOT="$(cd "$RUN_ROOT" && pwd)"
WALLET_HOME="$RUN_ROOT/wallet-home"
if [ ! -f "$WALLET_HOME/wallet_config.json" ]; then
  cat >&2 <<EOF
wallet config not found: $WALLET_HOME/wallet_config.json

Run scripts/lez-testnet-compatibility-evidence.sh first, or pass --run-root to
an existing compatibility run that contains wallet-home.
EOF
  exit 1
fi
if [ -f "$RUN_ROOT/summary.json" ]; then
  python3 - "$RUN_ROOT/summary.json" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if summary.get("transaction_submission_allowed") is not True:
    print(
        "compatibility gate blocks transaction submission: "
        f"check_health_exit_code={summary.get('check_health_exit_code')} "
        f"endpoint_health_ok={summary.get('endpoint_health_ok')}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
fi

WALLET_HOME_ENV_VAR="LEE_WALLET_HOME_DIR"
if "$WALLET" --help 2>&1 | grep -q "NSSA_WALLET_HOME_DIR"; then
  WALLET_HOME_ENV_VAR="NSSA_WALLET_HOME_DIR"
fi

raw_account_id() {
  local account="$1"
  printf '%s\n' "${account#Public/}"
}

rpc() {
  local method="$1"
  local params="${2:-[]}"
  curl -sfS -m 20 -X POST "$TESTNET_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"
}

get_account() {
  local account="$1"
  local raw
  raw="$(raw_account_id "$account")"
  rpc getAccount "[\"$raw\"]"
}

get_transaction() {
  local hash="$1"
  rpc getTransaction "[\"$hash\"]"
}

wallet_cmd() {
  env \
    LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" \
    "$WALLET_HOME_ENV_VAR=$WALLET_HOME" \
    RISC0_DEV_MODE=0 \
    "$WALLET" "$@"
}

LEZ_COMMIT="$(git -C "$LEZ_REPO" rev-parse --short HEAD 2>/dev/null || true)"
LEZ_REF="$(git -C "$LEZ_REPO" describe --tags --exact-match 2>/dev/null || git -C "$LEZ_REPO" describe --tags --always --dirty 2>/dev/null || true)"

get_account "$FROM" > "$RUN_ROOT/a2a-payment-from-before.out"
get_account "$TO" > "$RUN_ROOT/a2a-payment-to-before.out"

SEND_STATUS=0
set +e
wallet_cmd auth-transfer send \
  --from "$FROM" \
  --to "$TO" \
  --amount "$AMOUNT" \
  > "$RUN_ROOT/a2a-payment-send.out" 2>&1
SEND_STATUS=$?
set -e

TX_HASH="$(python3 - "$RUN_ROOT/a2a-payment-send.out" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
match = re.search(r"\b[a-fA-F0-9]{64}\b", text)
if match:
    print(match.group(0).lower())
PY
)"

LOOKUP_RETURNED=0
if [ -n "$TX_HASH" ]; then
  for attempt in $(seq 1 "$POLL_RETRIES"); do
    get_transaction "$TX_HASH" > "$RUN_ROOT/a2a-payment-get-transaction-$attempt.out" || true
    if python3 - "$RUN_ROOT/a2a-payment-get-transaction-$attempt.out" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if payload.get("result") is not None else 1)
PY
    then
      cp "$RUN_ROOT/a2a-payment-get-transaction-$attempt.out" "$RUN_ROOT/a2a-payment-get-transaction.out"
      LOOKUP_RETURNED=1
      break
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
fi

get_account "$FROM" > "$RUN_ROOT/a2a-payment-from-after.out"
get_account "$TO" > "$RUN_ROOT/a2a-payment-to-after.out"

python3 - \
  "$RUN_ROOT" \
  "$TESTNET_URL" \
  "$WALLET" \
  "$WALLET_HOME_ENV_VAR" \
  "$FROM" \
  "$TO" \
  "$AMOUNT" \
  "$TASK_ID" \
  "$SKILL_ID" \
  "$CLIENT_AGENT" \
  "$SERVER_AGENT" \
  "$TX_HASH" \
  "$SEND_STATUS" \
  "$LOOKUP_RETURNED" \
  "$LEZ_REF" \
  "$LEZ_COMMIT" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

(
    run_root,
    testnet_url,
    wallet,
    wallet_home_env_var,
    from_account,
    to_account,
    amount,
    task_id,
    skill_id,
    client_agent,
    server_agent,
    tx_hash,
    send_status,
    lookup_returned,
    lez_ref,
    lez_commit,
) = sys.argv[1:]
run_root = pathlib.Path(run_root)
amount_int = int(amount)
send_status_int = int(send_status)
lookup_ok = lookup_returned == "1"

def load_rpc_result(name):
    payload = json.loads((run_root / name).read_text(encoding="utf-8"))
    return payload.get("result")

before_from = load_rpc_result("a2a-payment-from-before.out")
before_to = load_rpc_result("a2a-payment-to-before.out")
after_from = load_rpc_result("a2a-payment-from-after.out")
after_to = load_rpc_result("a2a-payment-to-after.out")

balance_delta_ok = (
    isinstance(before_from, dict)
    and isinstance(before_to, dict)
    and isinstance(after_from, dict)
    and isinstance(after_to, dict)
    and before_from.get("balance") - after_from.get("balance") == amount_int
    and after_to.get("balance") - before_to.get("balance") == amount_int
)
nonce_delta_ok = (
    isinstance(before_from, dict)
    and isinstance(before_to, dict)
    and isinstance(after_from, dict)
    and isinstance(after_to, dict)
    and after_from.get("nonce") - before_from.get("nonce") == 1
    and after_to.get("nonce") - before_to.get("nonce") == 1
)

server_card = {
    "protocolVersion": "0.3.0",
    "name": "Logos Testnet Paid Skill Agent",
    "description": "A2A-compatible evidence card for a paid Logos agent skill.",
    "url": server_agent,
    "preferredTransport": "logos.messaging",
    "capabilities": {"streaming": True},
    "defaultInputModes": ["application/json"],
    "defaultOutputModes": ["application/json"],
    "skills": [
        {
            "id": skill_id,
            "name": "Echo",
            "description": "Returns the supplied message after payment acceptance.",
            "inputModes": ["application/json"],
            "outputModes": ["application/json"],
            "price": {
                "asset": "LEZ",
                "amount": amount_int,
                "recipient": to_account,
            },
        }
    ],
}

summary = {
    "ok": send_status_int == 0 and bool(tx_hash) and lookup_ok and balance_delta_ok and nonce_delta_ok,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "network": "hosted-testnet",
    "testnet_url": testnet_url,
    "wallet": wallet,
    "wallet_home_env_var": wallet_home_env_var,
    "risc0_dev_mode": "0",
    "lez_ref": lez_ref,
    "lez_commit": lez_commit,
    "task_id": task_id,
    "skill_id": skill_id,
    "client_agent": client_agent,
    "server_agent": server_agent,
    "server_agent_card": server_card,
    "task_lifecycle": [
        {"state": "submitted", "agent": client_agent, "skill": skill_id},
        {"state": "working", "agent": server_agent, "payment_tx_hash": tx_hash},
        {"state": "completed", "agent": server_agent, "output": {"ok": True}},
    ],
    "binding_status": (
        "Hosted-testnet LEZ payment leg verified. Two-agent Delivery discovery, "
        "task lifecycle, and LEZ payment are proven locally in "
        "docs/localnet-a2a-discovery-payment-evidence-20260620.md; final "
        "submission should record that proof or rerun it on the demo host."
    ),
    "payment_tx_hash": tx_hash,
    "from": from_account,
    "to": to_account,
    "amount": amount_int,
    "send_exit_code": send_status_int,
    "transaction_lookup_returned_some": lookup_ok,
    "balance_delta_ok": balance_delta_ok,
    "nonce_delta_ok": nonce_delta_ok,
    "before": {"from": before_from, "to": before_to},
    "after": {"from": after_from, "to": after_to},
}
(run_root / "testnet-a2a-payment-summary.json").write_text(
    json.dumps(summary, indent=2) + "\n",
    encoding="utf-8",
)
print(json.dumps(summary, indent=2))
PY

printf '\nA2A payment evidence summary: %s\n' "$RUN_ROOT/testnet-a2a-payment-summary.json"
