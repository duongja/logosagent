# Compute Unit Report

This document must be completed from devnet/testnet measurements before final
submission.

| Operation | Network | Program/Method | CU | Tx Hash | Notes |
| --- | --- | --- | --- | --- | --- |
| localnet health smoke | local standalone sequencer | `wallet check-health` via `agent_lez query` and `agent_lez call` | N/A | N/A | verified 2026-06-10 with `risc0_dev_mode = false`; no transaction submitted |
| `wallet.send` local proof | local standalone sequencer | public token transfer through `logos_execution_zone` wallet FFI | TBD | `1df33d3663daf739c62dd6b49a232552605e44966884fc339c13a2d7c8d34cab` | verified 2026-06-17 after aligning the module to scaffold-pinned LEZ commit `35d8df0d031315219f94d1546ceb862b0e5b208f`; replace with CU-measured devnet/testnet tx before final submission |
| `agent.task` payment local proof | local standalone sequencer | token transfer for declared A2A task price | TBD | `9dba4d55356904b077fca7181322b3d8d1f0750727076821d032c1a3d20af40f` | verified 2026-06-17; refund tx `310753b711d1325aee21106f8bd39717ba8a3546de51d18ec79aa991942f2a10`; CU still needs devnet/testnet measurement |
| `wallet.send` private-owned | TBD | authenticated transfer | TBD | TBD | run with `RISC0_DEV_MODE=0` on devnet/testnet |
| `program.deploy` | TBD | deployment tx | TBD | TBD | from `agent_lez deploy` using `wallet deploy-program`; current local program smoke uses `sha256-fallback` |
| `program.call` public | TBD | selected demo program | TBD | TBD | include instruction params; current stable local proof uses the wallet health facade |
| `agent.task` payment | TBD | token transfer | TBD | TBD | pay declared skill price and report CU from the accepted tx |

## Hosted Testnet CU Status

Hosted-testnet CU/tx evidence is gated by wallet compatibility. On 2026-06-19
UTC, `./scripts/lez-testnet-compatibility-evidence.sh` reached
`https://testnet.lez.logos.co/`, read block `61095`, and ran wallet commands
with `RISC0_DEV_MODE=0`, but `wallet check-health` exited `101` because the
remote builtin program IDs differ from the local public LEZ wallet artifacts.

Do not fill hosted-testnet CU rows from this endpoint until
`summary.json.transaction_submission_allowed` is `true`; otherwise any tx hash
would be from an incompatible wallet build and not valid prize evidence.
