# Submission Readiness

This checklist maps LP-0008 success criteria to repo assets and remaining
evidence work. Do not mark a live-network item complete until it has a
reproducible command transcript, tx hashes where applicable, and demo footage.

## Ready In Repo

- MIT license: `LICENSE`.
- Logos Core module package/build: `metadata.json`, `CMakeLists.txt`,
  `src/logos_agent_plugin.cpp`.
- Full default skill surface: `docs/skill-interface.md` and
  `src/agent_runtime.cpp`.
- Owner channel and Basecamp path: `docs/owner-channel-basecamp.md` and
  `scripts/basecamp-owner-channel.sh`.
- A2A-compatible card/task transport binding:
  `docs/a2a-logos-messaging-binding.md`.
- Spending policy and security model: `docs/security-model.md`,
  `src/policy_engine.cpp`.
- Reproducible dependency bootstrap: `scripts/bootstrap-workspace.sh`.
- Single-command owner deployment wrapper:
  `logos-agent-cli provision`.
- Local static smoke: `scripts/demo-local.sh`.
- Local LEZ sequencer smoke harness with `risc0_dev_mode = false`:
  `scripts/localnet-integration.sh`.
- Local wallet transfer harness:
  `scripts/agent-wallet-smoke.sh`.
- Local Messaging/Delivery skill harness:
  `scripts/agent-messaging-smoke.sh`.
- Local Storage skill harness:
  `scripts/agent-storage-smoke.sh`.
- Local paid A2A harness:
  `scripts/agent-a2a-paid-smoke.sh`.
- Local program operation harness:
  `scripts/agent-program-smoke.sh`.
- Reproducible dev LGX artifact path:
  `scripts/package-dev-lgx.sh`.
- Reproducible Basecamp runtime LGX set:
  `scripts/package-live-modules-lgx.sh`.
- Basecamp package-manager profile install smoke:
  `scripts/basecamp-profile-install-smoke.sh`.
- Testnet/CU evidence runbook and collector:
  `docs/testnet-evidence-runbook.md` and
  `scripts/collect-prize-evidence.py`.
- Hosted LEZ testnet compatibility evidence script:
  `scripts/lez-testnet-compatibility-evidence.sh`.
- Three-agent deployment profile generator:
  `scripts/prepare-three-agent-deployment.sh`.
- Pinned scaffold-localnet LEZ runtime repair:
  `scripts/build-pinned-lez-runtime.sh` and
  `patches/logos-execution-zone-module-pinned-localnet-ffi.patch`.
- Verified localnet smoke on 2026-06-10:
  `SCAFFOLD_BIN=../scaffold/target/release/logos-scaffold ./scripts/localnet-integration.sh --setup --prebuilt`.
  The run started a managed sequencer, reported `"ready": true`, and completed
  `agent_lez` wallet health query/call checks.
- Verified local wallet agent flow on 2026-06-16:
  `SCAFFOLD_BIN=/home/agate/Projects/logos/scaffold/target/release/logos-scaffold ./scripts/stable-test-runner.sh --allow-battery --jobs 1 --nix-cores 1 -- ./scripts/agent-wallet-smoke.sh`.
  The run started localnet, funded the scaffold public sender, proved
  above-threshold approval gating, submitted `wallet.send`, and returned tx hash
  `7c9ce13e30b5804ef07784c691dd6861134e9055ef422c77e0e901d45a3e4ce0`.
- Verified pinned LEZ runtime repair on 2026-06-17:
  `./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 -- ./scripts/build-pinned-lez-runtime.sh`.
  The run rebuilt the scaffold-pinned `wallet-ffi`, patched a scratch
  `logos_execution_zone` wrapper, installed it under `.local/live-modules`, and
  `scripts/check-runtime-modules.sh` passed for Delivery, Storage, Chat, LEZ,
  and the agent module.
- Verified local wallet agent flow again on 2026-06-17 after pinned runtime
  alignment:
  `RUN_ROOT="$PWD/.local/agent-wallet-smoke/$(date -u +%Y%m%dT%H%M%SZ)-pinned-hex-recipient"; ./scripts/agent-wallet-smoke.sh --run-root "$RUN_ROOT"`.
  The run submitted a real localnet `wallet.send` and returned tx hash
  `1df33d3663daf739c62dd6b49a232552605e44966884fc339c13a2d7c8d34cab`.
- Verified local Messaging/Delivery skill flow on 2026-06-16:
  `./scripts/stable-test-runner.sh --allow-battery --jobs 1 --nix-cores 1 -- ./scripts/agent-messaging-smoke.sh --message-timeout 75 --daemon-timeout 45`.
  The run proved `messaging.create_group`, `messaging.join`, and
  `messaging.send` through Delivery, with a second Logos Core instance receiving
  the message on `/logos-agent/1/messaging-smoke-group/json`.
- Verified local Messaging/Delivery skill flow again on 2026-06-17:
  `RUN_ROOT="$PWD/.local/agent-messaging-smoke/$(date -u +%Y%m%dT%H%M%SZ)-current"; ./scripts/agent-messaging-smoke.sh --run-root "$RUN_ROOT"`.
  The agent `messaging.send` reached a raw Delivery receiver on
  `/logos-agent/1/messaging-smoke-group/json`.
- Verified local Storage skill flow on 2026-06-16:
  `./scripts/stable-test-runner.sh --allow-battery --jobs 1 --nix-cores 1 -- ./scripts/agent-storage-smoke.sh --daemon-timeout 45 --storage-ready-timeout 90 --upload-timeout 120`.
  The run proved `storage.upload`, `storage.list`, `storage.share`, and
  `storage.download` through `storage_module`, compared downloaded bytes with
  the original input, and returned content address
  `zDvZRwzm1RbP7YQGD1uEAak1qwJoV44CspdkTMw88jPtFThb8ydv`.
- Verified local Storage skill flow again on 2026-06-17:
  `RUN_ROOT="$PWD/.local/agent-storage-smoke/$(date -u +%Y%m%dT%H%M%SZ)-current"; ./scripts/agent-storage-smoke.sh --run-root "$RUN_ROOT"`.
  The run proved upload/list/share/download and byte-for-byte recovery, returning
  content address `zDvZRwzm7HD8TBpjhw8exCohBcDatRZt58S6uZYcVFD9dbdohcCA`.
- Verified local paid A2A flow on 2026-06-16:
  `SCAFFOLD_BIN=/home/agate/Projects/logos/scaffold/target/release/logos-scaffold ./scripts/stable-test-runner.sh --allow-battery --jobs 1 --nix-cores 1 -- ./scripts/agent-a2a-paid-smoke.sh --localnet-timeout 180 --amount 1`.
  The run started localnet, funded the client sender, submitted a paid
  `agent.task`, completed the A2A lifecycle, and attached payment tx hash
  `7c9ce13e30b5804ef07784c691dd6861134e9055ef422c77e0e901d45a3e4ce0` to the
  task receipt on both agents.
- Verified local paid A2A cancel/refund flow on 2026-06-17:
  `RUN_ROOT="$PWD/.local/agent-a2a-paid-smoke/$(date -u +%Y%m%dT%H%M%SZ)-pinned-hex-recipient"; ./scripts/agent-a2a-paid-smoke.sh --run-root "$RUN_ROOT"`.
  The run paid the declared task price, moved the server task to
  `TASK_STATE_INPUT_REQUIRED`, cancelled the task, and submitted a real localnet
  refund. Payment tx hash:
  `9dba4d55356904b077fca7181322b3d8d1f0750727076821d032c1a3d20af40f`;
  refund tx hash:
  `310753b711d1325aee21106f8bd39717ba8a3546de51d18ec79aa991942f2a10`.
- Verified local unpaid A2A lifecycle on 2026-06-17:
  `RUN_ROOT="$PWD/.local/agent-a2a-smoke/$(date -u +%Y%m%dT%H%M%SZ)-current"; ./scripts/agent-a2a-smoke.sh --run-root "$RUN_ROOT"`.
  Task `task-a2a-smoke-20260617T000633Z` progressed from submit to working to
  completed over Delivery.
- Verified local A2A discovery + payment flow on 2026-06-20:
  `RISC0_DEV_MODE=0 SCAFFOLD_BIN=/home/agate/Projects/logos/scaffold/target/release/logos-scaffold LOGOSCORE=/home/agate/Projects/logos/logos-agent/.local/logoscore-bin/bin/logoscore MODULES_DIR=/home/agate/Projects/logos/logos-agent/.local/live-modules ./scripts/agent-a2a-paid-smoke.sh --run-root .local/agent-a2a-paid-smoke/20260620T101217Z-discovery-paid-prize --localnet-timeout 180`.
  The client subscribed to `/logos-agent/1/a2a-smoke-discovery/json`,
  discovered the server's signed Agent Card with advertised price `1`, paid the
  task price, and both agents reached `TASK_STATE_COMPLETED`. Payment tx hash:
  `81b55313e470325b17d58328dc03da9f03538d7c970a24b8d98ea23c83e0ed74`.
  See `docs/localnet-a2a-discovery-payment-evidence-20260620.md`.
- Verified local program operation flow on 2026-06-16:
  `SCAFFOLD_BIN=/home/agate/Projects/logos/scaffold/target/release/logos-scaffold ./scripts/stable-test-runner.sh --allow-battery --jobs 1 --nix-cores 1 -- ./scripts/agent-program-smoke.sh --localnet-timeout 180 --daemon-timeout 45`.
  The run started localnet, loaded the module in Logos Core, proved
  `program.query`, `program.call`, and `program.deploy` through `agent_lez`, and
  returned program ID
  `e0dac2d532553d5c059523c920c36bfe47fbe39c45434ce0c66e08dcf856d75f`.
- Verified local program operation flow again on 2026-06-17:
  `RUN_ROOT="$PWD/.local/agent-program-smoke/$(date -u +%Y%m%dT%H%M%SZ)-current"; ./scripts/agent-program-smoke.sh --run-root "$RUN_ROOT"`.
  The run proved `program.query`, `program.call`, and `program.deploy`; deploy
  returned program ID
  `e0dac2d532553d5c059523c920c36bfe47fbe39c45434ce0c66e08dcf856d75f` from the
  current `sha256-fallback` path.
- Verified current dev LGX package artifact on 2026-06-19:
  `./scripts/package-dev-lgx.sh`.
  The script packaged the already tested `.local/live-modules/logos_agent`
  payload into `result/logos-logos_agent-module-lib.lgx`, verified it with
  `lgx verify`, and produced a valid unsigned `linux-amd64-dev` core-module
  package with dependencies on `logos_execution_zone`, `storage_module`,
  `chat_module`, and `delivery_module`.
- Verified current Basecamp module capture on 2026-06-19:
  `./scripts/package-live-modules-lgx.sh` and
  `./scripts/basecamp-owner-channel.sh --capture-only`.
  The run produced verified path-based LGXs for `delivery_module`,
  `storage_module`, `chat_module`, `logos_execution_zone`, and `logos_agent`,
  then captured all five into
  `.local/basecamp-owner-channel/scaffold.toml` with the correct module names.
- Verified current Basecamp package-manager profile install on 2026-06-19:
  `./scripts/basecamp-profile-install-smoke.sh`.
  The run installed `delivery_module`, `storage_module`, `chat_module`,
  `logos_execution_zone`, and `logos_agent` into scaffold-compatible `alice`
  and `bob` Basecamp profile trees using the real `lgpm` CLI. The generated
  `summary.json` confirmed all five modules were present and exposed the
  expected `linux-amd64-dev` manifest variant.
- Verified Basecamp `0.1.2` launch and agent inspector flow on 2026-06-22:
  Basecamp was launched from Scaffold workspace `/tmp/lb` against
  `logos-basecamp` commit
  `63b35e8a0e826789ba15a46766df9fedc6794bc8`. The five runtime modules loaded
  in the `alice` profile, `logos_agent` exposed its invokable API, `skills()`
  returned the LP-0008 skill surface, `init()` and async `start()` succeeded,
  delayed `status()` returned `started = true` / `starting = false`, and
  `agent.card` returned a signed Ed25519 A2A-compatible card. Delivery logs
  showed `DeliveryModuleImpl: Delivery start completed with success` and a
  connection transition to `Connected`. See
  `docs/basecamp-v012-agent-evidence-20260622.md` and
  `support/basecamp-v012-agent-proof-20260622/`.
- Verified Basecamp owner-to-agent Chat UI flow on 2026-06-22:
  the owner pasted the agent intro bundle into Basecamp Chat and sent JSON
  skill calls in a private conversation. The headless agent received
  `meta.status`, `agent.card`, `wallet.balance`, `storage.list`,
  `messaging.send`, and `wallet.send` through the real `chat_module` push-event
  wrapper, replied to the same conversation, and created pending approval
  `appr_29deccb3d30d7ab1842b43b8f42f1285` for the above-threshold
  `wallet.send`. See `docs/basecamp-owner-chat-evidence-20260622.md`.
- Verified full localnet prize evidence refresh on 2026-06-22:
  Storage upload/list/share/download passed with byte-for-byte recovery and
  content address `zDvZRwzmDgqgmHKmGhXFpXsWitckj81Tuzk3vKfABaPV4VHvrXxU`;
  wallet threshold/transfer passed with tx
  `22b2daffa8a526f17b4b370afe408edacbdfe48c2078af07c128673d5e402547`;
  Messaging create/join/send passed over Delivery; unpaid and paid A2A reached
  `TASK_STATE_COMPLETED`; paid A2A attached payment tx
  `cbe01582b0bd0fab691b73760b1919b94e9d2da3ae023e32d158b02404d29bd7`;
  program query/call/deploy passed with program ID
  `e0dac2d532553d5c059523c920c36bfe47fbe39c45434ce0c66e08dcf856d75f`.
  See `docs/localnet-prize-evidence-refresh-20260622.md`.
- Local evidence bundle generation available:
  `./scripts/collect-prize-evidence.py --network localnet`.
  The output is intended to be rerun with explicit testnet run roots before
  final submission.
- Sanitized submission bundle generation available:
  `./scripts/create-submission-bundle.py`.
  It writes public docs, local/testnet evidence summaries, artifact checksums,
  and a manual-only checklist under `.local/submission-bundle/<timestamp>`
  without copying wallet state.
- Three-agent prize deployment profiles available:
  `./scripts/prepare-three-agent-deployment.sh --network testnet --delivery-preset logos.dev`.
  This creates `.local/testnet-agents/latest/manifest.json` plus Storage,
  Messaging, and Blockchain agent directories with `agent-config.json` and
  `deploy.sh` wrappers.
- Headless three-agent deployment evidence captured on 2026-06-20 UTC:
  Storage, Messaging, and Blockchain agents installed the verified module LGXs,
  loaded `logos_agent`, initialized, started, generated signed Agent Cards,
  returned `meta.skills`, returned `meta.status`, created private LEZ accounts,
  and started Delivery. See `docs/three-agent-headless-evidence-20260620.md`.
- Hosted LEZ testnet reachability and wallet compatibility checked on
  2026-06-19 UTC:
  `./scripts/lez-testnet-compatibility-evidence.sh --lez-repo /home/agate/Projects/logos/logos-execution-zone-v0.1.2-testnet --wallet /home/agate/Projects/logos/logos-execution-zone-v0.1.2-testnet/target/release/wallet`.
  The endpoint `https://testnet.lez.logos.co/` returned healthy JSON-RPC
  responses, `chain-info current-block-id` returned block `61127`, and
  `wallet check-health` passed with `RISC0_DEV_MODE=0`.
- Verified hosted-testnet wallet transfer on 2026-06-19 UTC:
  `wallet auth-transfer send --from Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV --to Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo --amount 1`.
  The run used LEZ tag `v0.1.2` / commit `cf3639d8`, returned tx hash
  `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0`,
  and a follow-up `chain-info transaction` query returned the transaction.
  Balance evidence showed sender `3648 -> 3647` and recipient `4000 -> 4001`.
- Verified hosted-testnet program deploy/call on 2026-06-19 UTC:
  `hello_world_with_authorization.bin` was deployed on the hosted LEZ testnet
  with tx hash
  `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb`.
  A signed public `program.call` then executed against the deployed program
  with tx hash
  `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518`.
  `getAccount` for
  `Public/3XJoAbLkgSjyAnS7XngaiBdcaU54UzN67FH9Q8NGbbgT` returned account data
  bytes for `Hola mundo!` and nonce `1`. See
  `docs/testnet-program-evidence-20260619.md`.
- Verified hosted-testnet LEZ payment leg for a paid A2A task on
  2026-06-19 UTC:
  `scripts/lez-testnet-a2a-payment-evidence.sh` submitted the declared
  `messaging.echo` task price with tx hash
  `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494`.
  Balance evidence showed payer `3647 -> 3646` and recipient `4001 -> 4002`;
  transaction lookup returned the tx. See
  `docs/testnet-a2a-payment-evidence-20260619.md`.

## Hosted Testnet Wallet Version

- The current public LEZ `main` wallet built from commit `feb6cb7` does not
  match `https://testnet.lez.logos.co/`; its builtin program IDs differ from
  the hosted testnet IDs.
- A full public artifact scan found matching builtin program IDs on LEZ tag
  `v0.1.2` / commit `cf3639d8` (also tag `v0.2.0-rc3`). Use that wallet for
  hosted-testnet tx evidence unless Logos redeploys the testnet.

## Evidence Still Required

- CU measurements in `docs/cu-report.md` for:
  `wallet.send`, `program.deploy`, `program.call`, and `agent.task` payment.
  Hosted-testnet tx hashes now exist for all four rows, but CU is still not
  exposed by the wallet/RPC output.
- Official clean-machine LGX package build. A current dev LGX exists at
  `result/logos-logos_agent-module-lib.lgx`, produced from the locally tested
  module payload. Before final submission, also rerun the official clean Nix
  package path (`nix build --impure .#lgx -L`) on a machine with enough memory or
  after cache warmup.
- End-to-end recorded evidence for at least three illustrative use cases. The
  implementation flows are now proven, including Basecamp owner Chat, but the
  final prize submission still needs narrated video footage that shows the
  evidence commands, visible Basecamp Chat interaction, tx hashes, and
  `RISC0_DEV_MODE=0`.

## Pre-Submission Command Set

Run these from a clean checkout after `scripts/bootstrap-workspace.sh`:

```bash
./scripts/preflight-submission.sh
./scripts/preflight-submission.sh --full
SCAFFOLD_BIN=../scaffold/target/release/logos-scaffold ./scripts/preflight-submission.sh --localnet
./scripts/create-submission-bundle.py
```
