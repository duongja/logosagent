# Owner Channel and Basecamp

The owner channel is a Logos Chat private conversation between the owner app
instance and the agent's `chat_module` identity. The agent also runs Delivery
for A2A discovery, group topics, and agent-to-agent task transport.

## Agent Config

`logos-agent-cli make-config` writes a `chat` section compatible with
`chat_module.initChat`:

```json
{
  "chat": {
    "name": "Storage Agent",
    "port": 60002,
    "clusterId": 2,
    "shardId": 1,
    "staticPeers": [],
    "create_intro_bundle": false,
    "owner_conversation_id": "",
    "owner_intro_bundle": ""
  }
}
```

For a real owner conversation, pass at least one Waku bootstrap ENR:

```bash
./cli/logos-agent-cli make-config \
  --output-dir .local/agent-a \
  --agent-name "Storage Agent" \
  --chat-static-peer "$BOOTSTRAP_ENR" \
  --create-intro-bundle
```

The chat schema follows the current `logos-chat-module` e2e config shape:
`name`, `port`, `clusterId`, `shardId`, and `staticPeers`.

## Message Format

The owner sends JSON in the chat message body. The runtime accepts both direct
JSON objects and the real `chat_module` push-event wrapper where message
content is hex-encoded.

Skill call:

```json
{"skill":"meta.status","params":{}}
```

Approval:

```json
{"approval_id":"appr_xxx","approved":true}
```

Above-threshold transactions stay pending until an approval message is received.

## Basecamp Module Packaging

Package the locally tested module payload first. This creates
`result/logos-logos_agent-module-lib.lgx` from `.local/live-modules/logos_agent`
and verifies it with `lgx verify`:

```bash
./scripts/package-dev-lgx.sh
```

Package the runtime modules needed by the owner-channel demo:

```bash
./scripts/package-live-modules-lgx.sh
```

The Basecamp package set includes:

- `chat_module`
- `delivery_module`
- `storage_module`
- `logos_execution_zone`
- `logos_agent`

## Basecamp Setup

The helper pins Scaffold's Basecamp checkout to the recommended
`tutorial-v3` / `release/0.1.2` commit
`63b35e8a0e826789ba15a46766df9fedc6794bc8` by default. Override with
`BASECAMP_PIN=<commit-or-tag>` only if Logos publishes a newer required build.

Validate module capture without running the heavier Basecamp install/setup
path:

```bash
./scripts/basecamp-owner-channel.sh --capture-only
```

Validate the package-manager installation layer without building or launching
the Basecamp GUI:

```bash
./scripts/basecamp-profile-install-smoke.sh
```

This installs the five LGX packages into scaffold-compatible `alice` and `bob`
Basecamp profile trees with the real `lgpm` CLI, then writes
`.local/basecamp-profile-install-smoke/latest/summary.json`.

For the official Basecamp AppImage, use portable LGXs:

```bash
./scripts/package-live-modules-lgx.sh \
  --out-root .local/artifacts/basecamp-lgx-portable \
  --variant linux-amd64
VARIANT=linux-amd64 \
  ./scripts/basecamp-profile-install-smoke.sh \
  --direct-profile \
  --run-root "$HOME/.local/share/Logos/LogosBasecamp" \
  --lgx-root .local/artifacts/basecamp-lgx-portable \
  --lgpm .local/tools/lgpm-portable/bin/lgpm
```

Prepare Basecamp owner app profiles when the machine has enough memory:

```bash
./scripts/basecamp-owner-channel.sh --setup
```

The script creates `.local/basecamp-owner-channel`, initializes a scaffold
project, captures the five verified LGX module packages, and installs them into
scaffold's `alice` and `bob` Basecamp profiles.

On low-memory laptops, `logos-scaffold basecamp setup` can be the expensive
step because it builds the Basecamp GUI through Nix. If the desktop session is
killed by memory pressure, keep the module capture and package-manager install
proofs, then run the GUI setup/launch step on a larger machine or after the
Basecamp binary is already cached.

Launch the owner profile:

```bash
cd .local/basecamp-owner-channel
logos-scaffold basecamp launch alice
```

Use the Chat UI in Basecamp to create or open the private conversation with the
agent. The final recorded prize demo should show this path end-to-end after the
testnet agents and LEZ funding are ready.
