# Three-Agent Headless Evidence - 2026-06-20 UTC

This is the sanitized evidence for the three required LP-0008 agent categories.
It was captured without launching the Basecamp GUI.

Command pattern:

```bash
LOGOSCORE=/home/agate/Projects/logos/logos-agent/.local/logoscore-bin/bin/logoscore \
LGPM=/nix/store/z24jsqngnzzzaiixxkbh5h46k0ihr8ah-logos-package-manager-cli-1.0.0/bin/lgpm \
RISC0_DEV_MODE=0 \
.local/testnet-agents/latest/<agent>/deploy.sh

./scripts/summarize-three-agent-deployment.py
```

## Result

All three agents installed the verified module LGXs, loaded `logos_agent`,
initialized, started, published an A2A Agent Card to the Delivery discovery
topic, and generated:

- `agent-card.json`
- `meta-skills.json`
- `meta-status.json`
- `deployment-summary.json`

| Category | Agent | LEZ account | Agent Card signed | Delivery started | Chat started |
| --- | --- | --- | --- | --- | --- |
| Storage | `storage-agent` | `Gj9BkjZ5DhaJSQvqNUWLdHFrgwrEpeiDUPTZFb9WswQm` | `true` | `true` | `true` |
| Messaging | `messaging-agent` | `DhxUctNjTky2au8GdYg5L2LfGFFdvro43zDpWtU9Cogs` | `true` | `true` | `true` |
| Blockchain | `blockchain-agent` | `87VVsVRvarJLEbJrPqXBC1QpWsyejcV12veViKhsjQiR` | `true` | `true` | `true` |

The compact local summary is:

```text
.local/testnet-agents/latest/three-agent-deployment-evidence.json
```

The generated evidence is intentionally not committed because it lives under
`.local`, but it is included in sanitized submission bundles.

## Scope Note

The three headless deployment captures prove module installation, initialization,
agent identity creation, wallet account creation, Agent Card signing, skill
listing, status reporting, and Delivery startup for each category agent.

On this laptop the `logoscore` daemon did not remain running after each capture;
`logoscore status` reported a stale daemon PID. The generated JSON evidence is
valid for the CLI deployment capture, but the final Basecamp owner-channel video
should be recorded on a larger or already-cached machine.
