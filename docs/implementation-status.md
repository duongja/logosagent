# Implementation Status

This repo is now a concrete LP-0008 implementation scaffold, not just a plan.

## Implemented

- Logos Core module metadata/build scaffold.
- JSON public API: `init`, `start`, `stop`, `invoke`, `approve`, `skills`,
  `status`.
- Runtime skill registry with every LP-0008 default skill name.
- Durable state for config, files, transactions, approvals, tasks, messages, and
  discovered Agent Cards.
- Spending policy with fail-closed defaults and durable owner approvals.
- LEZ wallet adapter for account open/create, private account creation, balance,
  token send, and local history.
- Storage adapter for encrypt-upload, download-decrypt, list, and wrapped share
  payloads.
- Storage encryption now uses OpenSSL AES-256-GCM with ciphertext hash and tag
  verification.
- Storage shares wrap file encryption keys to recipient X25519 public keys with
  HKDF-SHA256 and AES-256-GCM; raw file keys are redacted from public file/share
  responses.
- Messaging adapter for owner chat and Delivery-backed groups.
- A2A adapter for Agent Card, discovery, task submit, subscribe, and cancel.
- A2A Agent Cards and envelopes use Ed25519 identity signatures, with durable
  replay nonce tracking.
- CLI for deploy/init/start/status/invoke/approve/config generation.
- Single-command CLI provisioning wrapper for config generation, module install,
  daemon start, module load, `init`, and `start`.
- Owner-channel config generation for `chat_module`, including static peer,
  cluster/shard, intro-bundle, and owner conversation fields.
- Owner chat messages are normalized from direct JSON and real `chat_module`
  push-event wrappers before skill/approval dispatch.
- Basecamp owner-app setup helper installs the agent LGX into scaffold's
  `alice`/`bob` profiles. It now packages and captures the full local runtime
  set (`Delivery`, `Storage`, `Chat`, `LEZ`, and `Agent`) for path-based
  Basecamp installation.
- Rust `agent_lez` helper. It bridges to real `wallet deploy-program` and wallet
  query/call commands when the LEZ CLI is installed.
- Unit tests for policy, amount encoding, state persistence, registry basics, and
  the required default skill contract.
- Documentation for architecture, skills, A2A binding, security, deployment, and
  CU reporting.
- Nix fast tests, full Logos-stack unit tests, and `.lgx` package build verified
  locally on 2026-06-09:
  - `nix build --impure .#unit-tests-fast -L`
  - `nix build --impure .#unit-tests -L`
  - `nix build --impure .#lgx -L`
- Packaged module artifact was previously verified through the official Nix LGX
  build on 2026-06-09. A fresh official `nix build --impure .#lgx -L --max-jobs 1 --cores 2`
  was started on 2026-06-17 and stopped for memory safety after Nix grew past
  6 GB RSS while realizing the full Logos/Rust dependency graph. On 2026-06-19,
  `scripts/package-dev-lgx.sh` regenerated a current dev LGX from the already
  tested `.local/live-modules/logos_agent` payload, verified it with `lgx
  verify`, and pointed `result/` at the artifact. Re-run the official package
  build on a higher-memory machine, or after more Nix cache warmup, before final
  submission.
- Basecamp module capture verified locally on 2026-06-19:
  - `./scripts/package-live-modules-lgx.sh`
  - `./scripts/basecamp-owner-channel.sh --capture-only`
  - Scaffold captured verified LGXs for `delivery_module`, `storage_module`,
    `chat_module`, `logos_execution_zone`, and `logos_agent` into
    `.local/basecamp-owner-channel/scaffold.toml`.
- Basecamp package-manager profile install verified locally on 2026-06-19:
  - `./scripts/basecamp-profile-install-smoke.sh`
  - The real `lgpm` CLI installed `delivery_module`, `storage_module`,
    `chat_module`, `logos_execution_zone`, and `logos_agent` into
    scaffold-compatible `alice` and `bob` Basecamp profile trees.
  - `summary.json` confirmed all modules were present, dependency references
    were satisfied, and the expected `linux-amd64-dev` manifest variant was
    exposed for each module.
- Workspace bootstrap script and CI workflow for reproducible dependency setup.
- Opt-in localnet integration harness using `logos-scaffold` standalone
  sequencer with `RISC0_DEV_MODE=0`.
- Pinned scaffold-localnet LEZ runtime repair script:
  `scripts/build-pinned-lez-runtime.sh`. It rebuilds the scaffold-pinned
  `wallet-ffi`, patches a scratch `logos_execution_zone` wrapper for the older
  FFI ABI, installs the result under `.local/live-modules`, and preserves a
  backup.
- MIT license and submission-readiness checklist.
- Localnet harness verified locally on 2026-06-10:
  - `SCAFFOLD_BIN=../scaffold/target/release/logos-scaffold ./scripts/localnet-integration.sh --setup --prebuilt`
  - scaffold started managed sequencer on `127.0.0.1:3040` with
    `risc0_dev_mode = false`
  - `agent_lez query` and `agent_lez call` both completed `wallet check-health`
    successfully.
- Wallet agent smoke verified locally on 2026-06-16:
  - `scripts/agent-wallet-smoke.sh` now starts scaffold localnet, tops up the
    configured public sender, proves the approval gate, submits `wallet.send`,
    records `wallet.history`, and shuts localnet down.
  - Latest proof returned tx hash
    `7c9ce13e30b5804ef07784c691dd6861134e9055ef422c77e0e901d45a3e4ce0`.
- Pinned LEZ runtime repair verified locally on 2026-06-17:
  - `./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 -- ./scripts/build-pinned-lez-runtime.sh`
  - The script rebuilt and installed `logos_execution_zone` against scaffold's
    LEZ commit `35d8df0d031315219f94d1546ceb862b0e5b208f`.
  - `scripts/check-runtime-modules.sh` passed for Delivery, Storage, Chat, LEZ,
    and `logos_agent`.
- Wallet agent smoke verified again locally on 2026-06-17 after pinned runtime
  alignment:
  - `scripts/agent-wallet-smoke.sh` submitted a real localnet transfer and
    returned tx hash
    `1df33d3663daf739c62dd6b49a232552605e44966884fc339c13a2d7c8d34cab`.
- Messaging skill smoke verified locally on 2026-06-16:
  - `scripts/agent-messaging-smoke.sh` proves `messaging.create_group`,
    `messaging.join`, and `messaging.send` through Delivery.
  - A second Logos Core instance received the message on
    `/logos-agent/1/messaging-smoke-group/json`.
- Messaging skill smoke verified again locally on 2026-06-17:
  - Agent `messaging.send` reached a raw Delivery receiver on
    `/logos-agent/1/messaging-smoke-group/json`.
- Storage skill smoke verified locally on 2026-06-16:
  - `scripts/agent-storage-smoke.sh` starts `storage_module`, proves
    `storage.upload`, `storage.list`, `storage.share`, and `storage.download`,
    then compares downloaded bytes with the original input.
  - Latest proof returned content address
    `zDvZRwzm1RbP7YQGD1uEAak1qwJoV44CspdkTMw88jPtFThb8ydv`; the share payload
    contains a wrapped key and does not expose raw `key_hex`.
- Storage skill smoke verified again locally on 2026-06-17:
  - Upload/list/share/download completed through `storage_module`, downloaded
    bytes matched the original input, and the run returned content address
    `zDvZRwzm7HD8TBpjhw8exCohBcDatRZt58S6uZYcVFD9dbdohcCA`.
- Paid A2A smoke verified locally on 2026-06-16:
  - `scripts/agent-a2a-paid-smoke.sh` starts localnet, funds the client sender,
    submits a paid `agent.task`, and verifies the LEZ payment receipt on both
    client and server task state.
  - Latest proof returned payment tx hash
    `7c9ce13e30b5804ef07784c691dd6861134e9055ef422c77e0e901d45a3e4ce0`.
- Paid A2A cancel/refund smoke verified locally on 2026-06-17:
  - `scripts/agent-a2a-paid-smoke.sh` paid the declared task price, observed the
    server task enter `TASK_STATE_INPUT_REQUIRED`, cancelled it, and submitted a
    real localnet refund.
  - Payment tx hash:
    `9dba4d55356904b077fca7181322b3d8d1f0750727076821d032c1a3d20af40f`.
  - Refund tx hash:
    `310753b711d1325aee21106f8bd39717ba8a3546de51d18ec79aa991942f2a10`.
- Unpaid A2A lifecycle verified locally on 2026-06-17:
  - Task `task-a2a-smoke-20260617T000633Z` progressed from submit to working to
    completed over Delivery.
- Program operation smoke verified locally on 2026-06-16:
  - `scripts/agent-program-smoke.sh` starts scaffold localnet, loads the agent
    into Logos Core, and proves `program.query`, `program.call`, and
    `program.deploy` through the `agent_lez` helper.
  - Latest proof deployed
    `/home/agate/Projects/logos/logos-execution-zone/artifacts/test_program_methods/noop.bin`
    and returned program ID
    `e0dac2d532553d5c059523c920c36bfe47fbe39c45434ce0c66e08dcf856d75f`.
  - The `agent_lez` helper now enforces `timeout_ms` on child wallet/runner
    processes so a hanging LEZ wallet subcommand returns a bounded JSON failure.
- Program operation smoke verified again locally on 2026-06-17:
  - `program.query`, `program.call`, and `program.deploy` completed.
  - The current `program.deploy` proof uses the documented `sha256-fallback`
    program ID path until the LEZ deploy API is stable in this environment.
- Hosted LEZ testnet program evidence captured on 2026-06-19:
  - Deployed `hello_world_with_authorization.bin` with tx hash
    `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb`.
  - Submitted a signed public `program.call` with tx hash
    `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518`.
  - `getAccount` returned data bytes for `Hola mundo!`, proving the deployed
    program executed on hosted testnet.
- Hosted LEZ testnet A2A payment evidence captured on 2026-06-19:
  - Submitted the declared `messaging.echo` paid-task price with tx hash
    `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494`.
  - Balance evidence showed payer `3647 -> 3646` and recipient
    `4001 -> 4002`; transaction lookup returned the tx.
  - This proves the hosted-testnet LEZ payment leg. The full live
    Delivery/A2A transport run remains required for final prize submission.

## Needs Next

- Bind A2A Ed25519 keys to native Logos Messaging/LEZ identity material once the
  stable signing API is exposed.
- Replace the `agent_lez` wallet-facade bridge with a true generic
  `program.call(program_id, instruction, params)` path once LEZ exposes a stable
  arbitrary-program CLI/API.
- Promote the live localnet harness into required CI once runtime cost and SPel
  pin drift are acceptable.
- Run the Basecamp owner-channel path live with the Chat UI after the agent
  testnet deployments are ready; module capture and package-manager profile
  install are now proven.
- Run and record three testnet agents: Storage, Messaging, Blockchain.
- Record a live two-agent Delivery/A2A run that combines discovery, task
  lifecycle, and the hosted-testnet payment path.
- Fill `docs/cu-report.md` from devnet/testnet measurements with
  `RISC0_DEV_MODE=0`.
- Rebuild and attach the official clean-machine LGX package artifact before
  final submission; the current local dev LGX is available at `result/`.
