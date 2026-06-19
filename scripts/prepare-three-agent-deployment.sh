#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/cli/logos-agent-cli"
OUT_DIR="$ROOT/.local/testnet-agents/latest"
NETWORK="${NETWORK:-testnet}"
DELIVERY_PRESET="${DELIVERY_PRESET:-logos.dev}"
DELIVERY_MODE="${DELIVERY_MODE:-Core}"
DISCOVERY_TOPIC="${DISCOVERY_TOPIC:-/logos-agent/1/discovery/json}"
PER_TX_LIMIT="${PER_TX_LIMIT:-0}"
PERIOD_LIMIT="${PERIOD_LIMIT:-0}"
PERIOD_SECONDS="${PERIOD_SECONDS:-86400}"
OWNER_CONVERSATION_ID="${OWNER_CONVERSATION_ID:-}"
OWNER_INTRO_BUNDLE="${OWNER_INTRO_BUNDLE:-}"
CREATE_WALLET=1
CREATE_AGENT_ACCOUNT=1
PUBLISH_ON_START=1
BOOTSTRAP_PEERS=()

usage() {
  cat <<'USAGE'
Usage: scripts/prepare-three-agent-deployment.sh [options]

Generates the three LP-0008 prize deployment profiles:
  - Storage agent
  - Messaging agent
  - Blockchain agent

This script only writes configs, deploy helper scripts, and an evidence
manifest. It does not start logoscore, Basecamp, or a network service.

Options:
  --out-dir PATH              Output directory. Default: .local/testnet-agents/latest
  --network NAME              Evidence network label. Default: testnet
  --delivery-preset NAME      Delivery preset. Default: logos.dev
  --delivery-mode NAME        Delivery mode. Default: Core
  --discovery-topic TOPIC     A2A discovery topic.
  --per-tx-limit AMOUNT       Autonomous per-transaction limit. Default: 0
  --period-limit AMOUNT       Autonomous per-period limit. Default: 0
  --period-seconds SECONDS    Spending policy period. Default: 86400
  --owner-conversation-id ID  Existing owner chat conversation id.
  --owner-intro-bundle B64    Existing owner intro bundle.
  --chat-static-peer ENR      Add a Waku/bootstrap peer. May be repeated.
  --no-create-wallet          Do not ask the agent to create a wallet on init.
  --no-create-agent-account   Do not ask the agent to create an account on init.
  --no-publish-on-start       Do not publish the Agent Card on start.
  -h, --help                  Show this help.

Environment overrides:
  NETWORK, DELIVERY_PRESET, DELIVERY_MODE, DISCOVERY_TOPIC, PER_TX_LIMIT,
  PERIOD_LIMIT, PERIOD_SECONDS, OWNER_CONVERSATION_ID, OWNER_INTRO_BUNDLE.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="$(realpath -m "${2:-}")"; shift ;;
    --network) NETWORK="${2:-}"; shift ;;
    --delivery-preset) DELIVERY_PRESET="${2:-}"; shift ;;
    --delivery-mode) DELIVERY_MODE="${2:-}"; shift ;;
    --discovery-topic) DISCOVERY_TOPIC="${2:-}"; shift ;;
    --per-tx-limit) PER_TX_LIMIT="${2:-}"; shift ;;
    --period-limit) PERIOD_LIMIT="${2:-}"; shift ;;
    --period-seconds) PERIOD_SECONDS="${2:-}"; shift ;;
    --owner-conversation-id) OWNER_CONVERSATION_ID="${2:-}"; shift ;;
    --owner-intro-bundle) OWNER_INTRO_BUNDLE="${2:-}"; shift ;;
    --chat-static-peer) BOOTSTRAP_PEERS+=("${2:-}"); shift ;;
    --no-create-wallet) CREATE_WALLET=0 ;;
    --no-create-agent-account) CREATE_AGENT_ACCOUNT=0 ;;
    --no-publish-on-start) PUBLISH_ON_START=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$OUT_DIR" ] || [ -z "$NETWORK" ] || [ -z "$DELIVERY_PRESET" ]; then
  echo "out dir, network, and delivery preset must be non-empty" >&2
  exit 2
fi

case "$PERIOD_SECONDS" in
  ''|*[!0-9]*|0)
    echo "--period-seconds must be a positive integer" >&2
    exit 2
    ;;
esac

mkdir -p "$OUT_DIR"

peer_args=()
for peer in "${BOOTSTRAP_PEERS[@]}"; do
  peer_args+=(--chat-static-peer "$peer")
done

common_config_args=(
  --delivery-preset "$DELIVERY_PRESET"
  --delivery-mode "$DELIVERY_MODE"
  --discovery-topic "$DISCOVERY_TOPIC"
  --per-tx-limit "$PER_TX_LIMIT"
  --period-limit "$PERIOD_LIMIT"
  --period-seconds "$PERIOD_SECONDS"
  --owner-conversation-id "$OWNER_CONVERSATION_ID"
  --owner-intro-bundle "$OWNER_INTRO_BUNDLE"
)

if [ "$CREATE_WALLET" -eq 1 ]; then
  common_config_args+=(--create-wallet)
fi
if [ "$CREATE_AGENT_ACCOUNT" -eq 1 ]; then
  common_config_args+=(--create-agent-account)
fi
if [ "$PUBLISH_ON_START" -eq 1 ]; then
  common_config_args+=(--publish-on-start)
fi

write_deploy_script() {
  local agent_dir="$1"
  local category="$2"
  local script="$agent_dir/deploy.sh"
  cat >"$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ROOT="$ROOT"
AGENT_DIR="$agent_dir"
CATEGORY="$category"
MODULES_DIR="\${MODULES_DIR:-\$AGENT_DIR/modules}"
CORE_DIR="\${CORE_DIR:-\$AGENT_DIR/core}"
LOGOSCORE="\${LOGOSCORE:-logoscore}"
LGPM="\${LGPM:-lgpm}"
DAEMON_WAIT="\${DAEMON_WAIT:-2}"
export RISC0_DEV_MODE="\${RISC0_DEV_MODE:-0}"

mkdir -p "\$MODULES_DIR" "\$CORE_DIR"

for lgx in \\
  "\$ROOT/.local/artifacts/basecamp-lgx/delivery_module/delivery_module.lgx" \\
  "\$ROOT/.local/artifacts/basecamp-lgx/storage_module/storage_module.lgx" \\
  "\$ROOT/.local/artifacts/basecamp-lgx/chat_module/chat_module.lgx" \\
  "\$ROOT/.local/artifacts/basecamp-lgx/logos_execution_zone/logos_execution_zone.lgx" \\
  "\$ROOT/.local/artifacts/basecamp-lgx/logos_agent/logos_agent.lgx"
do
  if [ ! -f "\$lgx" ]; then
    echo "missing LGX package: \$lgx" >&2
    echo "Run: ./scripts/package-dev-lgx.sh && ./scripts/package-live-modules-lgx.sh" >&2
    exit 1
  fi
  "\$LGPM" --modules-dir "\$MODULES_DIR" install --file "\$lgx"
done

"\$LOGOSCORE" --config-dir "\$CORE_DIR" -D -m "\$MODULES_DIR" \\
  >"\$AGENT_DIR/logoscore.out" 2>"\$AGENT_DIR/logoscore.err" &
echo "\$!" >"\$AGENT_DIR/logoscore.pid"
sleep "\$DAEMON_WAIT"

"\$LOGOSCORE" --config-dir "\$CORE_DIR" load-module logos_agent
"\$ROOT/cli/logos-agent-cli" --logoscore "\$LOGOSCORE" --config-dir "\$CORE_DIR" init @"\$AGENT_DIR/agent-config.json"
"\$ROOT/cli/logos-agent-cli" --logoscore "\$LOGOSCORE" --config-dir "\$CORE_DIR" start
"\$ROOT/cli/logos-agent-cli" --logoscore "\$LOGOSCORE" --config-dir "\$CORE_DIR" invoke agent.card '{}' >"\$AGENT_DIR/agent-card.json"
"\$ROOT/cli/logos-agent-cli" --logoscore "\$LOGOSCORE" --config-dir "\$CORE_DIR" invoke meta.skills '{}' >"\$AGENT_DIR/meta-skills.json"
"\$ROOT/cli/logos-agent-cli" --logoscore "\$LOGOSCORE" --config-dir "\$CORE_DIR" invoke meta.status '{}' >"\$AGENT_DIR/meta-status.json"

python3 - "\$AGENT_DIR" "\$CATEGORY" <<'PY'
import json
import pathlib
import sys

agent_dir = pathlib.Path(sys.argv[1])
category = sys.argv[2]
summary = {
    "ok": True,
    "category": category,
    "agent_dir": str(agent_dir),
    "pid_file": str(agent_dir / "logoscore.pid"),
    "agent_card": str(agent_dir / "agent-card.json"),
    "meta_skills": str(agent_dir / "meta-skills.json"),
    "meta_status": str(agent_dir / "meta-status.json"),
}
(agent_dir / "deployment-summary.json").write_text(json.dumps(summary, indent=2) + "\\n")
print(json.dumps(summary, indent=2))
PY
EOF
  chmod +x "$script"
}

make_agent() {
  local dirname="$1"
  local category="$2"
  local agent_id="$3"
  local name="$4"
  local description="$5"
  local port="$6"
  local agent_dir="$OUT_DIR/$dirname"

  mkdir -p "$agent_dir"
  "$CLI" make-config \
    --output-dir "$agent_dir" \
    --agent-id "$agent_id" \
    --agent-name "$name" \
    --agent-description "$description" \
    --chat-port "$port" \
    "${common_config_args[@]}" \
    "${peer_args[@]}"

  printf '%s\n' "$category" >"$agent_dir/category.txt"
  write_deploy_script "$agent_dir" "$category"
}

make_agent \
  storage-agent \
  storage \
  storage-agent \
  "Storage Agent" \
  "LP-0008 storage-category agent for upload, list, share, and download proof." \
  60102

make_agent \
  messaging-agent \
  messaging \
  messaging-agent \
  "Messaging Agent" \
  "LP-0008 messaging-category agent for owner chat, group messaging, and A2A transport proof." \
  60103

make_agent \
  blockchain-agent \
  blockchain \
  blockchain-agent \
  "Blockchain Agent" \
  "LP-0008 blockchain-category agent for wallet transfer, program query, program call, and deploy proof." \
  60104

python3 - "$OUT_DIR" "$NETWORK" "$DELIVERY_PRESET" "$DELIVERY_MODE" "$DISCOVERY_TOPIC" "$PER_TX_LIMIT" "$PERIOD_LIMIT" "$PERIOD_SECONDS" "$PUBLISH_ON_START" <<'PY'
import json
import pathlib
import sys

out_dir = pathlib.Path(sys.argv[1])
network = sys.argv[2]
delivery_preset = sys.argv[3]
delivery_mode = sys.argv[4]
discovery_topic = sys.argv[5]
per_tx_limit = sys.argv[6]
period_limit = sys.argv[7]
period_seconds = int(sys.argv[8])
publish_on_start = sys.argv[9] == "1"

agents = []
for dirname in ("storage-agent", "messaging-agent", "blockchain-agent"):
    agent_dir = out_dir / dirname
    config_path = agent_dir / "agent-config.json"
    config = json.loads(config_path.read_text())
    agents.append({
        "category": (agent_dir / "category.txt").read_text().strip(),
        "agent_id": config["identity"]["agent_id"],
        "name": config["agent_card"]["name"],
        "description": config["agent_card"]["description"],
        "config": str(config_path),
        "deploy_script": str(agent_dir / "deploy.sh"),
        "expected_evidence": {
            "agent_card": str(agent_dir / "agent-card.json"),
            "meta_skills": str(agent_dir / "meta-skills.json"),
            "meta_status": str(agent_dir / "meta-status.json"),
            "deployment_summary": str(agent_dir / "deployment-summary.json"),
        },
    })

manifest = {
    "network": network,
    "delivery": {
        "preset": delivery_preset,
        "mode": delivery_mode,
        "discovery_topic": discovery_topic,
        "publish_on_start": publish_on_start,
    },
    "policy": {
        "per_transaction_limit": per_tx_limit,
        "period_limit": period_limit,
        "period_seconds": period_seconds,
    },
    "agents": agents,
    "package_prerequisites": [
        "scripts/package-dev-lgx.sh",
        "scripts/package-live-modules-lgx.sh",
    ],
    "evidence_next_steps": [
        "Run each deploy_script with RISC0_DEV_MODE=0.",
        "Fund each agent LEZ account on the target network.",
        "Record storage upload/list/share/download evidence for storage-agent.",
        "Record owner chat plus Delivery/A2A evidence for messaging-agent.",
        "Record wallet send, program query/call/deploy, tx hashes, and CU/cycles for blockchain-agent.",
        "Regenerate scripts/collect-prize-evidence.py with explicit run roots and --network matching this manifest.",
    ],
}

(out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

lines = [
    "# LP-0008 Three-Agent Deployment",
    "",
    f"- Network: `{network}`",
    f"- Delivery preset: `{delivery_preset}`",
    f"- Discovery topic: `{discovery_topic}`",
    "",
    "## Package First",
    "",
    "```bash",
    "./scripts/package-dev-lgx.sh",
    "./scripts/package-live-modules-lgx.sh",
    "```",
    "",
    "## Deploy Agents",
    "",
]
for agent in agents:
    lines.extend([
        f"### {agent['name']}",
        "",
        f"- Category: `{agent['category']}`",
        f"- Config: `{agent['config']}`",
        "",
        "```bash",
        f"RISC0_DEV_MODE=0 {agent['deploy_script']}",
        "```",
        "",
    ])

lines.extend([
    "## Evidence",
    "",
    "Keep terminal transcripts and generated JSON files for the final submission.",
    "Do not publish wallet configs, wallet storage files, Core token files, or private keys.",
    "",
])
(out_dir / "README.md").write_text("\n".join(lines))
PY

echo "Prepared LP-0008 three-agent deployment under: $OUT_DIR"
echo "Manifest: $OUT_DIR/manifest.json"
echo "Readme:   $OUT_DIR/README.md"
