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
- Basecamp `0.1.2` launch and agent inspector flow verified locally on
  2026-06-22:
  - Scaffold launched Basecamp profile `alice` from `/tmp/lb` using
    `logos-basecamp` commit
    `63b35e8a0e826789ba15a46766df9fedc6794bc8`.
  - The five runtime modules loaded: `storage_module`, `chat_module`,
    `delivery_module`, `logos_execution_zone`, and `logos_agent`.
  - `logos_agent` exposed `init`, `start`, `stop`, `invoke`, `approve`,
    `skills`, and `status`.
  - `skills()`, `init()`, async `start()`, delayed `status()`, and
    `agent.card` succeeded through the Basecamp QML inspector.
  - Delivery started and connected to `logos.dev`.
  - Evidence: `docs/basecamp-v012-agent-evidence-20260622.md` and
    `support/basecamp-v012-agent-proof-20260622/`.
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
- A2A discovery + paid lifecycle verified locally on 2026-06-20:
  - `scripts/agent-a2a-paid-smoke.sh` now subscribes the client to discovery,
    publishes the server's signed Agent Card on start, waits for the discovered
    card, then submits the paid task.
  - Latest proof used two isolated Logos Core daemons plus scaffold localnet.
    Both agents reached `TASK_STATE_COMPLETED`.
  - Payment tx hash:
    `81b55313e470325b17d58328dc03da9f03538d7c970a24b8d98ea23c83e0ed74`.
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
  - This proves the hosted-testnet LEZ payment leg. The full two-agent
    Delivery transport proof is captured locally in
    `docs/localnet-a2a-discovery-payment-evidence-20260620.md` and should be
    included in the final recording or rerun on the demo host.
- Hosted LEZ v0.2 testnet evidence refreshed on 2026-06-26 after the
  `v0.2.0-rc5` redeploy/outage:
  - `wallet.send` tx:
    `3f140331aee32dba313d0eb73e47b1aad7e6f1dd5dfc8721460c16ac8a011c86`.
  - `agent.task` payment tx:
    `2111c69569e0804e28ca4210e9850a7db4171d6d7f3787d10c0f426629e461b4`.
  - `program.deploy` tx:
    `1db8975f24b5f27a4c271ea17f7db33e9d654964af8ab980ee78d0e351537f03`.
  - `program.call` tx:
    `e752295333411623035c660016e8b1fb8deffdb4b7fc5c87fa0007eb004a8f30`.
  - `getAccount` returned data bytes for `LP0008-v020`; see
    `docs/testnet-v020-live-evidence-20260626.md`.
- Hosted LEZ final v0.2.0 testnet evidence refreshed on 2026-07-01:
  - `wallet.send` tx:
    `7bdeea835624591f222da7ece3d6a58f3663d5e943ee28f57d0ab35c37824de1`.
  - `agent.task` payment tx:
    `3d2d8a20b07c2df742078fbefdc18c6eb2e483e3ef9468681686e67f4d213894`.
  - `program.deploy` tx:
    `e9c0d01039e9ccb1b4c3ab915b263a6b4a6c5b8244737bb063b33282093a7d02`.
  - `program.call` tx:
    `ee2c922038fa225bb13d9dba9b8a9f63d48ccf23b8c1c6bd4ef1cb534f261e9f`.
  - `getAccount` for the called account returned the authenticated-transfer
    program owner and nonce `1`; see
    `docs/testnet-v020-final-evidence-20260701.md`.
- Three headless category-agent deployments captured on 2026-06-20:
  - Storage, Messaging, and Blockchain agents installed the verified LGX module
    set, loaded `logos_agent`, initialized, started, generated signed Agent
    Cards, returned `meta.skills`, returned `meta.status`, created private LEZ
    accounts, and started Delivery.
  - Evidence lives under `.local/testnet-agents/latest` and is summarized by
    `scripts/summarize-three-agent-deployment.py`.
  - The post-capture daemons did not remain running on this laptop, so the live
    Basecamp owner-channel recording should be done on a larger or cached host.

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
- Record the already-proven headless two-agent Delivery/A2A discovery +
  payment proof, or rerun it on the final demo host.
- Fill `docs/cu-report.md` from devnet/testnet measurements with
  `RISC0_DEV_MODE=0`.
- Rebuild and attach the official clean-machine LGX package artifact before
  final submission; the current local dev LGX is available at `result/`.
