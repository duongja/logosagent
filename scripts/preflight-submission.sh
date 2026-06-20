#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_FULL=0
RUN_LOCALNET=0
RUN_PACKAGE_DEV=0

usage() {
  cat <<'USAGE'
Usage: scripts/preflight-submission.sh [--full] [--localnet] [--package-dev]

Runs submission-oriented checks.

Default checks are intentionally fast:
  - CLI syntax/help
  - shell script syntax
  - agent_lez formatting/check
  - required submission files
  - local deterministic demo smoke
  - Basecamp profile package-manager install smoke

Options:
  --full         Also run Nix fast/full tests and build the official LGX package.
  --localnet     Also run the standalone LEZ localnet integration harness.
  --package-dev  Also regenerate a dev LGX from .local/live-modules/logos_agent.

Environment for --localnet is forwarded to scripts/localnet-integration.sh,
including SCAFFOLD_BIN, SCAFFOLD_REPO, CARGO_BUILD_JOBS, and PORT.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --full) RUN_FULL=1 ;;
    --localnet) RUN_LOCALNET=1 ;;
    --package-dev) RUN_PACKAGE_DEV=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT"

require_file() {
  if [ ! -f "$1" ]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_file LICENSE
require_file README.md
require_file metadata.json
require_file docs/architecture.md
require_file docs/skill-interface.md
require_file docs/a2a-logos-messaging-binding.md
require_file docs/security-model.md
require_file docs/deployment-guide.md
require_file docs/owner-channel-basecamp.md
require_file docs/cu-report.md
require_file docs/testnet-evidence-runbook.md
require_file docs/submission-readiness.md
require_file docs/prize-submission-dossier.md
require_file docs/manual-intervention-checklist.md

python3 -m py_compile cli/logos-agent-cli scripts/collect-prize-evidence.py scripts/create-submission-bundle.py scripts/summarize-three-agent-deployment.py
./cli/logos-agent-cli --help >/dev/null

bash -n \
  scripts/bootstrap-workspace.sh \
  scripts/demo-local.sh \
  scripts/basecamp-owner-channel.sh \
  scripts/basecamp-profile-install-smoke.sh \
  scripts/build-pinned-lez-runtime.sh \
  scripts/check-runtime-modules.sh \
  scripts/agent-a2a-paid-smoke.sh \
  scripts/agent-a2a-smoke.sh \
  scripts/agent-core-smoke.sh \
  scripts/agent-messaging-smoke.sh \
  scripts/agent-program-smoke.sh \
  scripts/agent-storage-smoke.sh \
  scripts/agent-wallet-smoke.sh \
  scripts/delivery-smoke.sh \
  scripts/lez-testnet-a2a-payment-evidence.sh \
  scripts/lez-testnet-compatibility-evidence.sh \
  scripts/stable-test-runner.sh \
  scripts/localnet-integration.sh \
  scripts/package-live-modules-lgx.sh \
  scripts/package-dev-lgx.sh \
  scripts/prepare-three-agent-deployment.sh \
  scripts/repair-live-modules.sh \
  scripts/preflight-submission.sh

(cd agent_lez && cargo fmt --check && cargo check --locked)

./scripts/demo-local.sh
./scripts/prepare-three-agent-deployment.sh --out-dir .local/preflight-three-agents --network testnet --delivery-preset logos.dev >/dev/null
./scripts/basecamp-profile-install-smoke.sh --run-root .local/preflight-basecamp-profile-install >/dev/null
./scripts/create-submission-bundle.py --out-dir .local/preflight-submission-bundle >/dev/null

if [ "$RUN_PACKAGE_DEV" -eq 1 ]; then
  ./scripts/package-dev-lgx.sh
  ./scripts/package-live-modules-lgx.sh
  ./scripts/basecamp-profile-install-smoke.sh --run-root .local/preflight-basecamp-profile-install >/dev/null
fi

if [ "$RUN_FULL" -eq 1 ]; then
  nix build --impure .#unit-tests-fast -L
  nix build --impure .#unit-tests -L
  nix build --impure .#lgx -L
fi

if [ "$RUN_LOCALNET" -eq 1 ]; then
  ./scripts/localnet-integration.sh --setup --prebuilt
fi

echo "Submission preflight completed."
