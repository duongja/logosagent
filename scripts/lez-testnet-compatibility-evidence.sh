#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
DEFAULT_LEZ_REPO="$WORKSPACE/logos-execution-zone-v0.2.0-testnet"
if [ ! -d "$DEFAULT_LEZ_REPO" ]; then
  DEFAULT_LEZ_REPO="$WORKSPACE/logos-execution-zone-v0.2.0-rc5-testnet"
fi
if [ ! -d "$DEFAULT_LEZ_REPO" ]; then
  DEFAULT_LEZ_REPO="$WORKSPACE/logos-execution-zone"
fi
LEZ_REPO="${LEZ_REPO:-$DEFAULT_LEZ_REPO}"
WALLET="${WALLET:-$LEZ_REPO/target/release/wallet}"
TESTNET_URL="${TESTNET_URL:-https://testnet.lez.logos.co/}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/testnet-evidence/$(date -u +%Y%m%dT%H%M%SZ)-lez-compat}"
LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-$HOME/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.0-linux-x86_64}"
POLL_TIMEOUT="${POLL_TIMEOUT:-30s}"
POLL_MAX_RETRIES="${POLL_MAX_RETRIES:-20}"
TX_POLL_MAX_BLOCKS="${TX_POLL_MAX_BLOCKS:-30}"
BLOCK_POLL_MAX_AMOUNT="${BLOCK_POLL_MAX_AMOUNT:-100}"

usage() {
  cat <<'USAGE'
Usage: scripts/lez-testnet-compatibility-evidence.sh [options]

Collects hosted LEZ testnet compatibility evidence without submitting a
transaction. It verifies JSON-RPC reachability, records remote builtin program
IDs when the endpoint exposes them, runs wallet check-health, and captures
read-only chain/account evidence.

Options:
  --run-root PATH       Output directory. Default: .local/testnet-evidence/<utc>-lez-compat
  --wallet PATH         LEZ wallet binary. Default: ../logos-execution-zone-v0.2.0-testnet/target/release/wallet when present, else ../logos-execution-zone-v0.2.0-rc5-testnet/target/release/wallet, else ../logos-execution-zone/target/release/wallet
  --lez-repo PATH       LEZ checkout for local commit/id metadata. Default: ../logos-execution-zone-v0.2.0-testnet when present, else ../logos-execution-zone-v0.2.0-rc5-testnet, else ../logos-execution-zone
  --testnet-url URL     Sequencer JSON-RPC URL. Default: https://testnet.lez.logos.co/
  --circuits-dir PATH   LOGOS_BLOCKCHAIN_CIRCUITS directory.
  -h, --help            Show this help.

Environment overrides:
  RUN_ROOT, WALLET, LEZ_REPO, TESTNET_URL, LOGOS_BLOCKCHAIN_CIRCUITS.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-root) RUN_ROOT="${2:-}"; shift ;;
    --wallet) WALLET="${2:-}"; shift ;;
    --lez-repo) LEZ_REPO="${2:-}"; shift ;;
    --testnet-url) TESTNET_URL="${2:-}"; shift ;;
    --circuits-dir) LOGOS_BLOCKCHAIN_CIRCUITS="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ ! -x "$WALLET" ]; then
  cat >&2 <<EOF
wallet binary not found or not executable: $WALLET

Build a compatible wallet first, for example:
  cd "$LEZ_REPO"
  CARGO_BUILD_JOBS=1 cargo build -p wallet --release
EOF
  exit 1
fi
if [ ! -d "$LOGOS_BLOCKCHAIN_CIRCUITS" ]; then
  echo "LOGOS_BLOCKCHAIN_CIRCUITS directory not found: $LOGOS_BLOCKCHAIN_CIRCUITS" >&2
  exit 1
fi

mkdir -p "$RUN_ROOT/wallet-home"
RUN_ROOT="$(cd "$RUN_ROOT" && pwd)"
WALLET_HOME="$RUN_ROOT/wallet-home"
printf '%s\n' "$RUN_ROOT" > "$ROOT/.local/last-testnet-evidence-run-root"

WALLET_HOME_ENV_VAR="LEE_WALLET_HOME_DIR"
if "$WALLET" --help 2>&1 | grep -q "NSSA_WALLET_HOME_DIR"; then
  WALLET_HOME_ENV_VAR="NSSA_WALLET_HOME_DIR"
fi

cat > "$WALLET_HOME/wallet_config.json" <<JSON
{
  "sequencer_addr": "$TESTNET_URL",
  "seq_poll_timeout": "$POLL_TIMEOUT",
  "seq_tx_poll_max_blocks": $TX_POLL_MAX_BLOCKS,
  "seq_poll_max_retries": $POLL_MAX_RETRIES,
  "seq_block_poll_max_amount": $BLOCK_POLL_MAX_AMOUNT
}
JSON

redact_recovery_text() {
  sed -E 's/[[:lower:]]+( [[:lower:]]+){11,23}/[REDACTED SEED PHRASE]/g'
}

rpc() {
  local method="$1"
  curl -sfS -m 20 -X POST "$TESTNET_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}"
}

wallet_cmd() {
  env \
    LOGOS_BLOCKCHAIN_CIRCUITS="$LOGOS_BLOCKCHAIN_CIRCUITS" \
    "$WALLET_HOME_ENV_VAR=$WALLET_HOME" \
    RISC0_DEV_MODE=0 \
    "$WALLET" "$@"
}

CHECK_HEALTH_STATUS=0
CURRENT_BLOCK_STATUS=0
ACCOUNT_LIST_STATUS=0

rpc checkHealth > "$RUN_ROOT/endpoint-health.json" 2>"$RUN_ROOT/endpoint-health.err" || true
rpc getProgramIds > "$RUN_ROOT/remote-program-ids.json" 2>"$RUN_ROOT/remote-program-ids.err" || true

python3 - "$RUN_ROOT/remote-program-ids.json" > "$RUN_ROOT/remote-program-ids.txt" <<'PY' || true
import json
import sys
path = sys.argv[1]
payload = json.load(open(path, encoding="utf-8"))
for name, value in sorted((payload.get("result") or {}).items()):
    print(f"{name} {value}")
PY

LOCAL_IDS_FILE="$RUN_ROOT/local-program-ids.txt"
python3 - "$LEZ_REPO" > "$LOCAL_IDS_FILE" <<'PY' || true
import glob
import pathlib
import re
import sys

repo = pathlib.Path(sys.argv[1])
files = sorted(
    glob.glob(str(repo / "target/release/build/lee-*/out/program_methods/mod.rs"))
    + glob.glob(str(repo / "target/release/build/nssa-*/out/program_methods/mod.rs")),
    key=lambda p: pathlib.Path(p).stat().st_mtime,
    reverse=True,
)
if not files:
    raise SystemExit(0)
text = pathlib.Path(files[0]).read_text(encoding="utf-8")
for const in [
    "AMM_ID",
    "AUTHENTICATED_TRANSFER_ID",
    "PINATA_ID",
    "PRIVACY_PRESERVING_CIRCUIT_ID",
    "TOKEN_ID",
]:
    match = re.search(rf"pub const {const}: \[u32; 8\] = (\[[^\n;]+\]);", text)
    if match:
        print(f"{const.lower().removesuffix('_id')} {match.group(1)}")
PY

check_tmp="$(mktemp)"
set +e
printf '\n' | wallet_cmd check-health > "$check_tmp" 2>&1
CHECK_HEALTH_STATUS=$?
set -e
redact_recovery_text < "$check_tmp" > "$RUN_ROOT/check-health.out"
rm -f "$check_tmp"

set +e
wallet_cmd chain-info current-block-id > "$RUN_ROOT/current-block-id.out" 2>&1
CURRENT_BLOCK_STATUS=$?
set -e

BLOCK_ID="$(awk '/Last block id is/{print $NF}' "$RUN_ROOT/current-block-id.out" 2>/dev/null || true)"
if [ -n "$BLOCK_ID" ]; then
  wallet_cmd chain-info block --id "$BLOCK_ID" > "$RUN_ROOT/block-$BLOCK_ID.out" 2>&1 || true
fi

set +e
wallet_cmd account list > "$RUN_ROOT/account-list.out" 2>&1
ACCOUNT_LIST_STATUS=$?
set -e

{
  git -C "$LEZ_REPO" rev-parse HEAD 2>/dev/null || true
  git -C "$LEZ_REPO" status --short 2>/dev/null || true
} > "$RUN_ROOT/lez-repo-status.out"

python3 - "$RUN_ROOT" "$TESTNET_URL" "$WALLET" "$WALLET_HOME" "$WALLET_HOME_ENV_VAR" "$CHECK_HEALTH_STATUS" "$CURRENT_BLOCK_STATUS" "$ACCOUNT_LIST_STATUS" <<'PY'
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

run_root = pathlib.Path(sys.argv[1])
testnet_url, wallet, wallet_home = sys.argv[2], sys.argv[3], sys.argv[4]
wallet_home_env_var = sys.argv[5]
check_health_status = int(sys.argv[6])
current_block_status = int(sys.argv[7])
account_list_status = int(sys.argv[8])

def load_json(name):
    try:
        return json.loads((run_root / name).read_text(encoding="utf-8"))
    except Exception:
        return None

def read(name):
    path = run_root / name
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""

def ids_from_text(name):
    result = {}
    for line in read(name).splitlines():
        if not line.strip():
            continue
        key, _, value = line.partition(" ")
        result[key] = value.strip()
    return result

remote_ids = ids_from_text("remote-program-ids.txt")
local_ids = ids_from_text("local-program-ids.txt")
key_map = {
    "amm": "amm",
    "authenticated_transfer": "authenticated_transfer",
    "pinata": "pinata",
    "privacy_preserving_circuit": "privacy_preserving_circuit",
    "token": "token",
}
program_id_matches = {}
for remote_key, local_key in key_map.items():
    if remote_key in remote_ids and local_key in local_ids:
        program_id_matches[remote_key] = remote_ids[remote_key] == local_ids[local_key]

block_id = ""
match = re.search(r"Last block id is\s+(\d+)", read("current-block-id.out"))
if match:
    block_id = match.group(1)

endpoint_health = load_json("endpoint-health.json")
summary = {
    "ok": check_health_status == 0,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "testnet_url": testnet_url,
    "wallet": wallet,
    "wallet_home": wallet_home,
    "wallet_home_env_var": wallet_home_env_var,
    "endpoint_health_ok": (
        isinstance(endpoint_health, dict)
        and "error" not in endpoint_health
        and endpoint_health.get("result") is None
    ),
    "endpoint_health_error": (
        endpoint_health.get("error") if isinstance(endpoint_health, dict) else None
    ),
    "check_health_exit_code": check_health_status,
    "current_block_exit_code": current_block_status,
    "account_list_exit_code": account_list_status,
    "current_block_id": block_id,
    "remote_program_ids": remote_ids,
    "local_program_ids": local_ids,
    "program_id_matches": program_id_matches,
    "transaction_submission_allowed": check_health_status == 0,
    "notes": [
        "RISC0_DEV_MODE=0 was set for wallet commands.",
        "wallet check-health must pass before hosted-testnet transaction hashes are valid evidence.",
        "First-run wallet recovery text is redacted and not retained by this script.",
    ],
}
(run_root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))
PY

printf '\nEvidence run: %s\n' "$RUN_ROOT"
