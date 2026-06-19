#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/cli/logos-agent-cli"
WORK="$ROOT/.local/demo"
LGX="$ROOT/result/logos-logos_agent-module-lib.lgx"

rm -rf "$WORK"
mkdir -p "$WORK"

echo "== Generating three LP-0008 agent configs =="
"$CLI" make-config --output-dir "$WORK/agent-storage" --agent-id storage-agent --agent-name "Storage Agent" --per-tx-limit 0 --period-limit 0
"$CLI" make-config --output-dir "$WORK/agent-messaging" --agent-id messaging-agent --agent-name "Messaging Agent" --per-tx-limit 0 --period-limit 0
"$CLI" make-config --output-dir "$WORK/agent-blockchain" --agent-id blockchain-agent --agent-name "Blockchain Agent" --per-tx-limit 0 --period-limit 0

echo
echo "== Validating generated config security posture =="
python3 - "$WORK" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in sorted(root.glob("agent-*/agent-config.json")):
    cfg = json.loads(path.read_text())
    policy = cfg["policy"]
    security = cfg["security"]
    assert policy["per_transaction_limit"] == "0", path
    assert policy["period_limit"] == "0", path
    assert security["allow_dev_file_cipher"] is False, path
    assert security["allow_dev_a2a_secret"] is False, path
    print(f"{path}: fail-closed spend policy, AES-GCM storage, Ed25519 A2A signing")
PY

echo
echo "== CLI syntax check =="
python3 -m py_compile "$CLI"
"$CLI" --help >/dev/null

echo
echo "== agent_lez deterministic inspect smoke =="
printf 'demo program bytes' > "$WORK/demo-program.bin"
(
  cd "$ROOT/agent_lez"
  cargo run --quiet -- inspect <<JSON
{"binary_path":"$WORK/demo-program.bin","spel_bin":"/bin/false"}
JSON
)

echo
echo "== Package artifact =="
if [ -f "$LGX" ]; then
  ls -lh "$LGX"
else
  echo "LGX not found at $LGX"
  echo "Build it with: nix build --impure .#lgx -L"
fi

cat <<EOF
Created demo workspace under:
  $WORK/agent-storage/agent-config.json
  $WORK/agent-messaging/agent-config.json
  $WORK/agent-blockchain/agent-config.json

For live Logos Core execution, build/install the LGX and run three isolated logoscore daemons:
  nix build --impure .#lgx -L
  lgpm --modules-dir ./modules install --file ./result/logos-logos_agent-module-lib.lgx

Then initialize each daemon with its config and run:
  ./cli/logos-agent-cli --config-dir .local/core-storage init @$WORK/agent-storage/agent-config.json
  ./cli/logos-agent-cli --config-dir .local/core-storage start
  ./cli/logos-agent-cli --config-dir .local/core-storage invoke agent.card '{}'
  ./cli/logos-agent-cli --config-dir .local/core-storage invoke meta.skills '{}'
EOF
