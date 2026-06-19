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
- Local evidence bundle generation available:
  `./scripts/collect-prize-evidence.py --network localnet`.
  The output is intended to be rerun with explicit testnet run roots before
  final submission.
- Three-agent prize deployment profiles available:
  `./scripts/prepare-three-agent-deployment.sh --network testnet --delivery-preset logos.dev`.
  This creates `.local/testnet-agents/latest/manifest.json` plus Storage,
  Messaging, and Blockchain agent directories with `agent-config.json` and
  `deploy.sh` wrappers.
- Hosted LEZ testnet reachability checked on 2026-06-19 UTC:
  `./scripts/lez-testnet-compatibility-evidence.sh`.
  The endpoint `https://testnet.lez.logos.co/` returned healthy JSON-RPC
  responses, `chain-info current-block-id` returned block `61095`, and the
  wallet read/list commands succeeded with `RISC0_DEV_MODE=0`.

## Current Hosted Testnet Blocker

- Hosted-testnet transaction evidence is currently blocked by LEZ artifact
  mismatch, not by the agent module. The current public LEZ wallet built from
  `logos-execution-zone` commit `feb6cb7` fails `wallet check-health` against
  `https://testnet.lez.logos.co/` with:
  `Local ID for authenticated transfer program is different from remote`.
- The same compatibility run records that all five builtin program IDs differ:
  `authenticated_transfer`, `token`, `pinata`, `amm`, and
  `privacy_preserving_circuit`. Because wallet `check-health` fails, submitting
  hosted-testnet transfers from this binary would not be valid prize evidence.
- Targeted branch-artifact scan found no match for the hosted testnet
  `authenticated_transfer` ID among the fetched public branches checked:
  `origin/main`, `origin/fix/program-ids`,
  `origin/programs-elfs-deployments-circuits-fix`,
  `origin/Pravdyvy/programs-elfs-deployments`,
  `origin/Pravdyvy/hardcoded-initial-state`,
  `origin/fix/add-amm-to-rpc-endpoint`,
  `origin/fix/increase-wallet-polling-timeout`,
  `origin/fix/update-wallet-output-examples`,
  `origin/schouhy/finish-auth-transfer-ffi-functionality`,
  `origin/schouhy/fix-wallet`, `origin/schouhy/protocol-fixes`, and
  `origin/schouhy/standalone-sequencer-with-mock`.
- Required external input before real hosted-testnet tx hashes can be produced:
  the exact LEZ wallet/artifact commit for `https://testnet.lez.logos.co/`, a
  prebuilt matching wallet binary, or a testnet redeploy aligned to the public
  wallet artifacts.

## Evidence Still Required

- CU measurements in `docs/cu-report.md` for:
  `wallet.send`, `program.deploy`, `program.call`, and `agent.task` payment.
- Official clean-machine LGX package build. A current dev LGX exists at
  `result/logos-logos_agent-module-lib.lgx`, produced from the locally tested
  module payload. Before final submission, also rerun the official clean Nix
  package path (`nix build --impure .#lgx -L`) on a machine with enough memory or
  after cache warmup.
- Live Basecamp GUI setup/launch/owner-channel run against a separate Logos app
  profile. The module capture and package-manager install layers now work; the
  GUI build/launch and chat interaction still need recorded proof.
- A stable arbitrary LEZ `program.call(program_id, instruction, params)` proof.
  The current local proof uses the supported wallet CLI bridge with
  `wallet_args:["check-health"]`; the LEZ `auth-transfer init` facade hangs in
  this local environment.
- Three LEZ testnet agent deployments:
  Storage agent, Messaging agent, Blockchain agent.
- End-to-end testnet evidence for at least three illustrative use cases.
- Basecamp owner-channel live run against the deployed agent.
- Recorded narrated demo with terminal proof output showing `RISC0_DEV_MODE=0`.

## Pre-Submission Command Set

Run these from a clean checkout after `scripts/bootstrap-workspace.sh`:

```bash
./scripts/preflight-submission.sh
./scripts/preflight-submission.sh --full
SCAFFOLD_BIN=../scaffold/target/release/logos-scaffold ./scripts/preflight-submission.sh --localnet
```
