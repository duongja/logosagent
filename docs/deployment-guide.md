# Deployment Guide

## Build Package

From a clean workspace, first prepare sibling Logos sources:

```bash
./scripts/bootstrap-workspace.sh
```

```bash
nix build --impure .#lgx -L
```

On this development machine, when the module has already been built and
installed under `.local/live-modules/logos_agent`, a lighter dev-package path is
available:

```bash
./scripts/package-dev-lgx.sh
```

That creates `result/logos-logos_agent-module-lib.lgx` and verifies it with the
Logos `lgx` tool. Use the Nix build above for a clean evaluator machine; use the
dev-package path to reproduce the current local package artifact without
rebuilding the full Logos dependency graph.

For Basecamp installation, package the complete locally tested runtime module
set:

```bash
./scripts/package-live-modules-lgx.sh
```

## Install

```bash
mkdir -p ./modules
lgpm --modules-dir ./modules install --file ./result/logos-logos_agent-module-lib.lgx
```

Install dependency modules too:

- `logos_execution_zone`
- `storage_module`
- `chat_module`
- `delivery_module`

For local scaffold-sequencer proofs, align `logos_execution_zone` with the LEZ
commit pinned by scaffold localnet before running wallet or paid A2A smokes:

```bash
./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 -- ./scripts/build-pinned-lez-runtime.sh
```

This is a localnet compatibility step. Testnet deployment should use the
`logos_execution_zone` module generation expected by that testnet.

## Run Headless

```bash
logoscore --config-dir .local/core-a -D -m ./modules
logoscore --config-dir .local/core-a load-module logos_agent
```

The owner-facing one-command path composes package install, optional daemon
start, module load, `init`, and `start`:

```bash
./cli/logos-agent-cli --config-dir .local/core-a provision \
  --output-dir .local/agent-a \
  --modules-dir ./modules \
  --lgx ./result/logos-logos_agent-module-lib.lgx \
  --start-daemon \
  --agent-name "Storage Agent" \
  --create-wallet \
  --create-agent-account
```

## Three-Agent Prize Deployment

LP-0008 requires evidence for three separately deployed agents: one Storage,
one Messaging, and one Blockchain agent. Generate those deployment profiles
with:

```bash
./scripts/prepare-three-agent-deployment.sh \
  --network testnet \
  --delivery-preset logos.dev
```

The script writes:

- `.local/testnet-agents/latest/storage-agent`
- `.local/testnet-agents/latest/messaging-agent`
- `.local/testnet-agents/latest/blockchain-agent`
- `.local/testnet-agents/latest/manifest.json`

Each agent directory contains `agent-config.json` plus a `deploy.sh` wrapper.
The wrapper installs the five verified runtime LGX packages, starts an isolated
`logoscore` profile, initializes the agent, starts it, and records `agent.card`,
`meta.skills`, and `meta.status` evidence. Run each generated `deploy.sh` with
`RISC0_DEV_MODE=0` for final testnet/devnet evidence.

## Configure

```bash
./cli/logos-agent-cli --config-dir .local/core-a make-config --output-dir .local/agent-a
./cli/logos-agent-cli --config-dir .local/core-a init @.local/agent-a/agent-config.json
./cli/logos-agent-cli --config-dir .local/core-a start
```

A2A Agent Cards and task envelopes are signed by the agent Ed25519 identity
created during `init`; no development HMAC flag is needed for normal local
runs.

## Interact

```bash
./cli/logos-agent-cli --config-dir .local/core-a invoke meta.status '{}'
./cli/logos-agent-cli --config-dir .local/core-a invoke agent.card '{}'
```

## Owner App Path

Basecamp is the reference owner app shell. After building the LGX:

```bash
./scripts/basecamp-owner-channel.sh --setup
```

The helper pins Basecamp to `tutorial-v3` / `release/0.1.2`
(`63b35e8a0e826789ba15a46766df9fedc6794bc8`) by default. Override with
`BASECAMP_PIN=<commit-or-tag>` only if Logos provides a newer required build.

For a light validation that only captures the module table:

```bash
./scripts/basecamp-owner-channel.sh --capture-only
```

Then launch the owner profile:

```bash
cd .local/basecamp-owner-channel
logos-scaffold basecamp launch alice
```

Owner chat messages are JSON skill calls or approval decisions; see
[owner-channel-basecamp.md](owner-channel-basecamp.md).
