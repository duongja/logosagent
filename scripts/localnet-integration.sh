#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
RUN_ROOT="$ROOT/.local/localnet-integration"
PROJECT_NAME="scaffold-project"
PROJECT_DIR="$RUN_ROOT/$PROJECT_NAME"
SCAFFOLD_CACHE_ROOT="$RUN_ROOT/cache"
SCAFFOLD_CIRCUITS_BOOTSTRAP="$RUN_ROOT/circuits-bootstrap"
SCAFFOLD_REPO="${SCAFFOLD_REPO:-$WORKSPACE/scaffold}"
SCAFFOLD_BIN="${SCAFFOLD_BIN:-}"
KEEP_LOCALNET=0
RUN_SETUP=0
USE_PREBUILT=0
TIMEOUT_SEC="${TIMEOUT_SEC:-180}"
PORT="${PORT:-3040}"

usage() {
  cat <<'USAGE'
Usage: scripts/localnet-integration.sh [--setup] [--prebuilt] [--keep-localnet]

Runs a non-demo local LEZ sequencer smoke against agent_lez:
  1. Creates an isolated scaffold workspace under .local/localnet-integration.
  2. Uses a project-local scaffold cache and forces [localnet].risc0_dev_mode = false.
  3. Starts scaffold's standalone localnet.
  4. Runs agent_lez query/call through the live wallet/sequencer.

If scaffold setup fails after building the LEZ sequencer and wallet but before
seeding the wallet home, the harness prepares the wallet home itself. This keeps
the wallet/sequencer smoke independent from optional SPel build drift.

Options:
  --setup          Run `logos-scaffold setup` before starting localnet.
  --prebuilt       Pass --prebuilt to scaffold setup when available.
  --keep-localnet  Do not stop localnet on exit.

Environment:
  SCAFFOLD_BIN   Path to logos-scaffold binary.
  SCAFFOLD_REPO  Path to logos-co/scaffold checkout.
  PORT           Localnet port, default 3040.
  TIMEOUT_SEC    Localnet start timeout, default 180.
  CARGO_BUILD_JOBS
                 Cargo build parallelism for scaffold source builds, default min(nproc, 4).
  BINDGEN_EXTRA_CLANG_ARGS
                 Optional extra clang args for LEZ dependency bindgen builds.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --setup) RUN_SETUP=1 ;;
    --prebuilt) USE_PREBUILT=1 ;;
    --keep-localnet) KEEP_LOCALNET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SCAFFOLD_BIN" ]; then
  if command -v logos-scaffold >/dev/null 2>&1; then
    SCAFFOLD_BIN="$(command -v logos-scaffold)"
  elif [ -x "$SCAFFOLD_REPO/target/release/logos-scaffold" ]; then
    SCAFFOLD_BIN="$SCAFFOLD_REPO/target/release/logos-scaffold"
  elif [ -x "$SCAFFOLD_REPO/target/debug/logos-scaffold" ]; then
    SCAFFOLD_BIN="$SCAFFOLD_REPO/target/debug/logos-scaffold"
  fi
fi

if [ -z "$SCAFFOLD_BIN" ] || [ ! -x "$SCAFFOLD_BIN" ]; then
  cat >&2 <<EOF
logos-scaffold binary not found.

Build or install it first, for example:
  cd "$SCAFFOLD_REPO"
  cargo build --release --bin logos-scaffold

Or pass:
  SCAFFOLD_BIN=/path/to/logos-scaffold $0
EOF
  exit 1
fi
SCAFFOLD_BIN="$(cd "$(dirname "$SCAFFOLD_BIN")" && pwd)/$(basename "$SCAFFOLD_BIN")"

if [ ! -x "$ROOT/agent_lez/target/debug/agent_lez" ]; then
  (cd "$ROOT/agent_lez" && cargo build --locked)
fi
AGENT_LEZ="$ROOT/agent_lez/target/debug/agent_lez"

if [ -z "${BINDGEN_EXTRA_CLANG_ARGS:-}" ] && command -v gcc >/dev/null 2>&1; then
  GCC_INCLUDE="$(gcc -print-file-name=include 2>/dev/null || true)"
  if [ -n "$GCC_INCLUDE" ] && [ -d "$GCC_INCLUDE" ]; then
    export BINDGEN_EXTRA_CLANG_ARGS="-I$GCC_INCLUDE"
  fi
fi
if [ -z "${CARGO_BUILD_JOBS:-}" ]; then
  BUILD_JOBS="$(nproc 2>/dev/null || echo 1)"
  if [ "$BUILD_JOBS" -gt 4 ]; then
    BUILD_JOBS=4
  fi
  export CARGO_BUILD_JOBS="$BUILD_JOBS"
fi

rm -rf "$PROJECT_DIR"
mkdir -p "$RUN_ROOT"

if [ -z "${LOGOS_BLOCKCHAIN_CIRCUITS:-}" ]; then
  mkdir -p "$SCAFFOLD_CIRCUITS_BOOTSTRAP"
  export LOGOS_BLOCKCHAIN_CIRCUITS="$SCAFFOLD_CIRCUITS_BOOTSTRAP"
fi

(cd "$RUN_ROOT" && "$SCAFFOLD_BIN" new "$PROJECT_NAME" --cache-root "$SCAFFOLD_CACHE_ROOT")
cd "$PROJECT_DIR"

python3 - "$PORT" <<'PY'
import re
import sys
from pathlib import Path

port = sys.argv[1]
path = Path("scaffold.toml")
text = path.read_text()
text = re.sub(r"(?m)^risc0_dev_mode = (true|false)$", "risc0_dev_mode = false", text)
text = re.sub(r"(?m)^port = \d+$", f"port = {port}", text)
path.write_text(text)
PY

eval "$(
  python3 - <<'PY'
import shlex
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python <3.11 fallback for local machines.
    import tomli as tomllib

project_root = Path.cwd()
cfg = tomllib.loads(Path("scaffold.toml").read_text())
scaffold = cfg.get("scaffold", {})
wallet = cfg.get("wallet", {})
repos = cfg.get("repos", {})

cache_root = Path(scaffold.get("cache_root", ""))
if not cache_root:
    raise SystemExit("scaffold.toml did not record [scaffold].cache_root")
if not cache_root.is_absolute():
    cache_root = project_root / cache_root

wallet_home = Path(wallet.get("home_dir", ".scaffold/wallet"))
if not wallet_home.is_absolute():
    wallet_home = project_root / wallet_home

lez = repos.get("lez", {})
lez_path_text = lez.get("path", "")
if lez_path_text:
    lez_path = Path(lez_path_text)
    if not lez_path.is_absolute():
        lez_path = project_root / lez_path
else:
    pin = lez.get("pin", "")
    if not pin:
        raise SystemExit("scaffold.toml did not record [repos.lez].pin")
    lez_path = cache_root / "repos" / "lez" / pin

wallet_bin = lez_path / "target" / "release" / "wallet"
print(f"WALLET_HOME={shlex.quote(str(wallet_home))}")
print(f"WALLET_BIN_CANDIDATE={shlex.quote(str(wallet_bin))}")
print(f"LEZ_REPO_CANDIDATE={shlex.quote(str(lez_path))}")
PY
)"

prepare_wallet_home_fallback() {
  local wallet_config_src="$LEZ_REPO_CANDIDATE/wallet/configs/debug/wallet_config.json"
  local state_file="$PROJECT_DIR/.scaffold/state/wallet.state"

  if [ ! -x "$LEZ_REPO_CANDIDATE/target/release/sequencer_service" ] || [ ! -x "$WALLET_BIN_CANDIDATE" ]; then
    echo "fallback unavailable: missing built sequencer or wallet under $LEZ_REPO_CANDIDATE" >&2
    return 1
  fi
  if [ ! -f "$wallet_config_src" ]; then
    echo "fallback unavailable: missing wallet debug config at $wallet_config_src" >&2
    return 1
  fi

  mkdir -p "$WALLET_HOME" "$(dirname "$state_file")"
  if [ ! -f "$WALLET_HOME/wallet_config.json" ]; then
    cp "$wallet_config_src" "$WALLET_HOME/wallet_config.json"
  fi

  python3 - "$WALLET_HOME/wallet_config.json" "$state_file" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])
data = json.loads(config_path.read_text())

for item in data.get("initial_accounts", []):
    public = item.get("Public")
    if isinstance(public, dict) and public.get("account_id"):
        state_path.write_text(f"default_address=Public/{public['account_id']}\n")
        break
PY
}

if [ "$RUN_SETUP" -eq 1 ]; then
  set +e
  if [ "$USE_PREBUILT" -eq 1 ]; then
    "$SCAFFOLD_BIN" setup --prebuilt
    setup_status=$?
  else
    "$SCAFFOLD_BIN" setup
    setup_status=$?
  fi
  set -e

  if [ "$setup_status" -ne 0 ]; then
    echo "warning: scaffold setup exited with status $setup_status; checking wallet/sequencer fallback" >&2
    if prepare_wallet_home_fallback; then
      echo "warning: scaffold setup failed after LEZ binaries were built; continuing with wallet-home fallback for this smoke harness" >&2
    else
      exit "$setup_status"
    fi
  fi
fi

cleanup() {
  if [ "$KEEP_LOCALNET" -eq 0 ]; then
    "$SCAFFOLD_BIN" localnet stop >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

"$SCAFFOLD_BIN" localnet start --timeout-sec "$TIMEOUT_SEC"
"$SCAFFOLD_BIN" localnet status --json

WALLET_BIN="$WALLET_BIN_CANDIDATE"
if [ ! -x "$WALLET_BIN" ]; then
  WALLET_BIN="$(find "$LEZ_REPO_CANDIDATE" "$SCAFFOLD_CACHE_ROOT" -path '*/target/release/wallet' -type f -perm -111 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$WALLET_BIN" ] || [ ! -x "$WALLET_BIN" ]; then
  cat >&2 <<EOF
wallet binary not found.

Expected: $WALLET_BIN_CANDIDATE

Run with --setup after scaffold dependencies are available, or build the
project-local wallet through logos-scaffold setup first.
EOF
  exit 1
fi

printf '{"wallet_bin":"%s","wallet_home":"%s","target":"health"}' "$WALLET_BIN" "$WALLET_HOME" \
  | "$AGENT_LEZ" query

printf '{"wallet_bin":"%s","wallet_home":"%s","wallet_args":["check-health"],"amount":"0"}' "$WALLET_BIN" "$WALLET_HOME" \
  | "$AGENT_LEZ" call

cat <<EOF
Localnet integration smoke completed.
Project: $PROJECT_DIR
RISC0_DEV_MODE: 0
EOF
