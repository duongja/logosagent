#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/ci-e2e/$(date -u +%Y%m%dT%H%M%SZ)}"
export RISC0_DEV_MODE=0

# Create the artifact root before localnet setup so early failures are retained
# by the workflow's always-run evidence upload.
mkdir -p "$RUN_ROOT"
exec > >(tee "$RUN_ROOT/e2e.log") 2>&1

if [ -z "${LOGOSCORE:-}" ]; then
  if [ -s "$ROOT/.local/tools-v02/logoscore.path" ]; then
    LOGOSCORE="$(<"$ROOT/.local/tools-v02/logoscore.path")"
  elif command -v logoscore >/dev/null 2>&1; then
    LOGOSCORE="$(command -v logoscore)"
  else
    echo "logoscore v0.2 was not prepared; run scripts/prepare-v02-runtime.sh" >&2
    exit 1
  fi
fi
if [ ! -x "$LOGOSCORE" ]; then
  echo "prepared logoscore is not executable: $LOGOSCORE" >&2
  exit 1
fi
export LOGOSCORE

SCAFFOLD_REPO="${SCAFFOLD_REPO:-$ROOT/../scaffold}"
SCAFFOLD_PROJECT="${SCAFFOLD_PROJECT:-$ROOT/.local/localnet-integration/scaffold-project}"
if [ ! -x "$SCAFFOLD_REPO/target/release/logos-scaffold" ]; then
  if [ ! -f "$SCAFFOLD_REPO/Cargo.toml" ]; then
    echo "pinned scaffold checkout is missing: $SCAFFOLD_REPO" >&2
    exit 1
  fi
  (cd "$SCAFFOLD_REPO" && cargo build --release --locked --bin logos-scaffold)
fi
export SCAFFOLD_BIN="${SCAFFOLD_BIN:-$SCAFFOLD_REPO/target/release/logos-scaffold}"
export SCAFFOLD_PROJECT

if [ ! -f "$SCAFFOLD_PROJECT/.scaffold/wallet/wallet_config.json" ] \
  || [ ! -f "$SCAFFOLD_PROJECT/scaffold.toml" ] \
  || ! grep -Fq 'pin = "a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a"' "$SCAFFOLD_PROJECT/scaffold.toml"; then
  TIMEOUT_SEC=240 "$ROOT/scripts/localnet-integration.sh" --setup --prebuilt
fi

PROGRAM_BINARY="${PROGRAM_BINARY:-$("$ROOT/scripts/prepare-v02-program-fixture.sh")}"
export PROGRAM_BINARY

"$ROOT/scripts/check-runtime-modules.sh"
"$ROOT/scripts/agent-storage-smoke.sh" --run-root "$RUN_ROOT/storage"
"$ROOT/scripts/agent-messaging-smoke.sh" --run-root "$RUN_ROOT/messaging" --preset logos.dev --message-timeout 90 --daemon-timeout 45
"$ROOT/scripts/agent-a2a-smoke.sh" --run-root "$RUN_ROOT/a2a" --preset logos.dev
"$ROOT/scripts/agent-wallet-smoke.sh" --run-root "$RUN_ROOT/wallet" --localnet-timeout 240
"$ROOT/scripts/agent-a2a-paid-smoke.sh" --run-root "$RUN_ROOT/a2a-paid" --localnet-timeout 240
"$ROOT/scripts/agent-program-smoke.sh" \
  --run-root "$RUN_ROOT/program" --localnet-timeout 240 --daemon-timeout 45

echo "local two-agent E2E completed: $RUN_ROOT"
