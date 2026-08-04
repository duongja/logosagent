#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=local
EVIDENCE_DIR="$ROOT/evidence/current/testnet-v02"
TESTNET_CONFIG="${LOGOS_AGENT_TESTNET_CONFIG:-}"
OUT_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  ./demo.sh
  ./demo.sh --verify-testnet-evidence [DIR]
  ./demo.sh --testnet --config FILE [--out-dir DIR]

Default mode prepares checksum-recorded v0.2 module packages and executes the
real local Storage, Delivery, wallet, A2A, and program smoke suite.

--verify-testnet-evidence validates committed sanitized evidence without network
access. --testnet runs the authorized two-agent logos.test harness; it never
falls back to localnet or a standalone wallet command.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify-testnet-evidence)
      MODE=verify
      if [ "${2:-}" != "" ] && [[ "${2:-}" != --* ]]; then EVIDENCE_DIR="$2"; shift; fi
      ;;
    --testnet) MODE=testnet ;;
    --config) TESTNET_CONFIG="${2:-}"; shift ;;
    --out-dir) OUT_DIR="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT"
case "$MODE" in
  verify)
    exec ./cli/logos-agent-cli verify-evidence "$EVIDENCE_DIR"
    ;;
  testnet)
    if [ -z "$TESTNET_CONFIG" ]; then
      echo "--testnet requires --config or LOGOS_AGENT_TESTNET_CONFIG" >&2
      exit 2
    fi
    if [ -z "$OUT_DIR" ]; then OUT_DIR=".local/testnet-v02-e2e/$(date -u +%Y%m%dT%H%M%SZ)"; fi
    exec ./cli/logos-agent-cli testnet-e2e --config "$TESTNET_CONFIG" --out-dir "$OUT_DIR"
    ;;
  local)
    ./scripts/preflight-submission.sh
    ./scripts/bootstrap-workspace.sh
    MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules-v02}" ./scripts/prepare-v02-runtime.sh
    MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules-v02}" ./scripts/ci-local-e2e.sh
    echo "demo completed with real local module execution"
    ;;
esac
