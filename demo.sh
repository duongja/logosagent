#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_LOCALNET=0
RUN_PACKAGE_DEV=0

usage() {
  cat <<'USAGE'
Usage: ./demo.sh [--localnet] [--package-dev]

Runs the LP-0008 review demo entrypoint.

Default mode is artifact-safe and suitable for a clean reviewer machine:
  - forces RISC0_DEV_MODE=0 unless already set
  - runs the submission preflight
  - creates a sanitized submission bundle
  - prints the narrated video links and heavier live-flow commands

Options:
  --localnet     Also run the local sequencer skill proofs:
                 storage, wallet, messaging, paid A2A, and program operations.
  --package-dev  Also regenerate/install the dev LGX set during preflight.

The hosted LEZ testnet tx hashes and recorded Basecamp owner-chat proof are
documented in the generated submission bundle.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --localnet) RUN_LOCALNET=1 ;;
    --package-dev) RUN_PACKAGE_DEV=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT"

export RISC0_DEV_MODE="${RISC0_DEV_MODE:-0}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE=".local/submission-bundle/demo-${STAMP}"

echo "== LP-0008 Logos Agent demo =="
echo "repo: $ROOT"
echo "RISC0_DEV_MODE=$RISC0_DEV_MODE"

echo
echo "== Submission preflight =="
PREFLIGHT_ARGS=()
if [ "$RUN_PACKAGE_DEV" -eq 1 ]; then
  PREFLIGHT_ARGS+=(--package-dev)
fi
./scripts/preflight-submission.sh "${PREFLIGHT_ARGS[@]}"

echo
echo "== Sanitized submission bundle =="
./scripts/create-submission-bundle.py --out-dir "$BUNDLE"

if [ "$RUN_LOCALNET" -eq 1 ]; then
  echo
  echo "== Local sequencer skill proofs =="
  ./scripts/agent-storage-smoke.sh --run-root ".local/demo-runs/${STAMP}-storage"
  ./scripts/agent-wallet-smoke.sh --run-root ".local/demo-runs/${STAMP}-wallet" --localnet-timeout 240
  ./scripts/agent-messaging-smoke.sh --run-root ".local/demo-runs/${STAMP}-messaging" --message-timeout 90 --daemon-timeout 45
  ./scripts/agent-a2a-paid-smoke.sh --run-root ".local/demo-runs/${STAMP}-a2a-paid" --localnet-timeout 240
  ./scripts/agent-program-smoke.sh --run-root ".local/demo-runs/${STAMP}-program" --localnet-timeout 240 --daemon-timeout 45
else
  cat <<EOF

== Optional live-flow commands ==
Run these on a powered/stable machine when you want to replay the terminal
proofs shown in the narrated demo:

  export RISC0_DEV_MODE=0
  ./scripts/agent-storage-smoke.sh --run-root .local/demo-runs/${STAMP}-storage
  ./scripts/agent-wallet-smoke.sh --run-root .local/demo-runs/${STAMP}-wallet --localnet-timeout 240
  ./scripts/agent-messaging-smoke.sh --run-root .local/demo-runs/${STAMP}-messaging --message-timeout 90 --daemon-timeout 45
  ./scripts/agent-a2a-paid-smoke.sh --run-root .local/demo-runs/${STAMP}-a2a-paid --localnet-timeout 240
  ./scripts/agent-program-smoke.sh --run-root .local/demo-runs/${STAMP}-program --localnet-timeout 240 --daemon-timeout 45

Or run all five through this entrypoint:

  ./demo.sh --localnet
EOF
fi

cat <<EOF

== Narrated demo videos ==
Video 1: repository readiness, package/evidence bundle, hosted-testnet tx evidence
  https://www.youtube.com/watch?v=fYlokf7NIfI
Video 2: Basecamp owner-to-agent Chat flow
  https://www.youtube.com/watch?v=nS8928doTkE
Video 3: live skill proofs: Storage, wallet, Messaging, paid A2A, programs
  https://www.youtube.com/watch?v=hxRQejaBhxo

Submission bundle:
  $BUNDLE
EOF
