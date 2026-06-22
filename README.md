# Logos Agent Module

This repository is the LP-0008 implementation workspace for a Logos Core module
that runs an autonomous agent with:

- a LEZ wallet identity and spending policy,
- Logos Storage upload/download/share skills,
- Logos Messaging owner chat and Delivery-backed group/A2A transport,
- an A2A-compatible Agent Card and task lifecycle binding,
- a CLI for deployment and module calls.

The project is intentionally split into adapters so Logos module APIs can evolve
without changing the public agent skill interface.

## Status

Current implementation:

- Core module scaffold: `logos_agent`
- Default LP-0008 skills registered behind `invoke(skill, paramsJson)`
- Durable JSON state under the module instance persistence path
- Wallet adapter using `logos_execution_zone`
- Storage adapter using `storage_module`
- Owner messaging adapter using `chat_module`
- A2A/group transport using `delivery_module`
- Spending thresholds with durable approval queue
- CLI: `cli/logos-agent-cli`
- Program helper: `agent_lez`
- Basecamp owner-channel setup helper: `scripts/basecamp-owner-channel.sh`
- Verified local package artifact: `result/logos-logos_agent-module-lib.lgx`

Known pre-submission gaps:

- `agent_lez` uses the real `wallet deploy-program`, query, and wallet-facade
  call bridge where available. A true generic arbitrary-program call should
  replace that bridge once LEZ exposes a stable CLI/API for it.
- Storage upload/download uses OpenSSL AES-256-GCM for local file encryption,
  and `storage.share` wraps file keys to recipient X25519 public keys.
- A2A Agent Cards and task envelopes use Ed25519 identity signatures with
  durable replay nonce tracking. Bind those keys directly to native Logos
  Messaging/LEZ identity material once the stable signing API is exposed.
- Chat groups are not exposed by `logos-chat-module`; group skills use Delivery
  topics and document that transport binding.

## Build

With Logos tooling and Nix installed:

```bash
nix build --impure .#unit-tests-fast -L
nix build --impure .#unit-tests -L
nix build --impure .#lgx -L
```

`unit-tests-fast` validates the local agent state, policy, amount encoding, and
skill registry without building the full Storage/Chat/Delivery/LEZ dependency
closure. `unit-tests` is the fuller Logos-module test path and is intentionally
heavier because it realizes the declared module dependencies from
`metadata.json`.

See [docs/environment-setup.md](docs/environment-setup.md) for the exact local
tooling setup and the remaining root-level install steps.

For a clean machine, clone this repo as `logos-agent` inside a workspace
directory and run:

```bash
./scripts/bootstrap-workspace.sh
```

That script clones the sibling Logos repos pinned for this implementation and
applies the temporary LEZ compatibility patches documented in `patches/`.

The Rust helper can be checked independently:

```bash
cd agent_lez
cargo fmt --check
cargo check
```

Probe Delivery preset/module behavior without rebuilding the agent:

```bash
./scripts/delivery-smoke.sh --preset logos.dev
./scripts/delivery-smoke.sh --preset logos.test --api-only
```

## CLI Quickstart

Create a local config:

```bash
./cli/logos-agent-cli make-config --output-dir .local/agent-a --agent-name "Storage Agent"
```

Install and load the packaged module:

```bash
./cli/logos-agent-cli deploy --modules-dir ./modules --lgx ./result/logos-logos_agent-module-lib.lgx --load
```

Initialize and start:

```bash
./cli/logos-agent-cli init @.local/agent-a/agent-config.json
./cli/logos-agent-cli start
```

Or provision a local headless instance in one command after building the LGX:

```bash
./cli/logos-agent-cli --config-dir .local/core-a provision \
  --output-dir .local/agent-a \
  --modules-dir ./modules \
  --lgx ./result/logos-logos_agent-module-lib.lgx \
  --start-daemon
```

Call a skill:

```bash
./cli/logos-agent-cli invoke meta.skills '{}'
./cli/logos-agent-cli invoke wallet.balance '{}'
```

Approve a pending spend:

```bash
./cli/logos-agent-cli approve appr_xxx --approved
```

## Public Module API

The module exposes a small JSON surface:

- `init(configJson) -> json`
- `start() -> json`
- `stop() -> json`
- `invoke(skillName, paramsJson) -> json`
- `approve(approvalId, decisionJson) -> json`
- `skills() -> json`
- `status() -> json`

All skill calls return:

```json
{"ok": true}
```

or:

```json
{"ok": false, "code": "namespace.reason", "error": "human readable message"}
```

See [docs/skill-interface.md](docs/skill-interface.md).

For the owner app path, see
[docs/owner-channel-basecamp.md](docs/owner-channel-basecamp.md). It documents
how Basecamp loads the module and how owner chat messages are formatted.
The Basecamp helper pins Scaffold's Basecamp checkout to `tutorial-v3` /
`release/0.1.2` (`63b35e8a0e826789ba15a46766df9fedc6794bc8`) by default.
On low-memory machines, use `./scripts/basecamp-profile-install-smoke.sh` to
prove the real `lgpm` profile install layer without building the Basecamp GUI.

For the required three-agent prize deployment profiles, run:

```bash
./scripts/prepare-three-agent-deployment.sh --network testnet --delivery-preset logos.dev
```

For prize packaging status, see
[docs/submission-readiness.md](docs/submission-readiness.md).
For final tx/CU/testnet evidence capture, see
[docs/testnet-evidence-runbook.md](docs/testnet-evidence-runbook.md).
For a concise committed review map, see
[docs/prize-submission-dossier.md](docs/prize-submission-dossier.md).

Create a sanitized local review bundle with:

```bash
./scripts/create-submission-bundle.py
```

The bundle intentionally excludes wallet state and raw runtime secrets. The
remaining manual/UI tasks are tracked in
[docs/manual-intervention-checklist.md](docs/manual-intervention-checklist.md).
