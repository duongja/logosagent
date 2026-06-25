# Compute Unit Report

Current status: hosted-testnet and localnet transaction evidence exists for the
required on-chain operations, but the current LEZ wallet/RPC output used for
this submission does not expose compute-unit (CU) values directly. CU is
therefore reported as `TBD` until Logos provides explorer metadata, sequencer
metadata, wallet logs, or an evaluator-approved benchmark-to-CU mapping.

The Logos team advised submitting the LP-0008 PR while they clarify the exact CU
expectation, and suggested the `fryorcraken/lez-signature-bench` approach as a
measurement model. This report therefore keeps verifiable tx hashes in the main
table and documents the benchmark method we will apply if reviewers ask for a
cycles/proving-cost supplement.

| Operation | Network | Program/Method | CU | Tx Hash | Notes |
| --- | --- | --- | --- | --- | --- |
| localnet health smoke | local standalone sequencer | `wallet check-health` via `agent_lez query` and `agent_lez call` | N/A | N/A | verified 2026-06-10 with `risc0_dev_mode = false`; no transaction submitted |
| `wallet.send` local proof | local standalone sequencer | public token transfer through `logos_execution_zone` wallet FFI | TBD | `1df33d3663daf739c62dd6b49a232552605e44966884fc339c13a2d7c8d34cab` | verified 2026-06-17 after aligning the module to scaffold-pinned LEZ commit `35d8df0d031315219f94d1546ceb862b0e5b208f`; replace with CU-measured devnet/testnet tx before final submission |
| `agent.task` payment local proof | local standalone sequencer | token transfer for declared A2A task price | TBD | `9dba4d55356904b077fca7181322b3d8d1f0750727076821d032c1a3d20af40f` | verified 2026-06-17; refund tx `310753b711d1325aee21106f8bd39717ba8a3546de51d18ec79aa991942f2a10`; CU still needs devnet/testnet measurement |
| `wallet.send` hosted testnet proof | hosted LEZ testnet | authenticated transfer, public-to-public | TBD | `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0` | verified 2026-06-19 with LEZ `v0.1.2` / `cf3639d8` and `RISC0_DEV_MODE=0`; sender `3648 -> 3647`, recipient `4000 -> 4001`; CU not exposed by wallet output |
| `wallet.send` private-owned | TBD | authenticated transfer | TBD | TBD | run with `RISC0_DEV_MODE=0` on devnet/testnet |
| `program.deploy` hosted testnet proof | hosted LEZ testnet | `hello_world_with_authorization` deployment tx | TBD | `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb` | verified 2026-06-19 with LEZ `v0.1.2` / `cf3639d8`; RPC/wallet output does not expose CU |
| `program.call` hosted testnet proof | hosted LEZ testnet | signed public call, instruction `Hola mundo!` | TBD | `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518` | verified 2026-06-19; `getAccount` returned data bytes for `Hola mundo!` and nonce `1`; CU not exposed by RPC/wallet output |
| `agent.task` payment hosted testnet proof | hosted LEZ testnet | token transfer for declared A2A skill price | TBD | `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494` | verified 2026-06-19 with LEZ `v0.1.2` / `cf3639d`; payer `3647 -> 3646`, recipient `4001 -> 4002`; CU not exposed by wallet/RPC output |
| `agent.task` discovery + payment local proof | local standalone sequencer | signed Agent Card discovery, task lifecycle, and LEZ payment | TBD | `81b55313e470325b17d58328dc03da9f03538d7c970a24b8d98ea23c83e0ed74` | verified 2026-06-20; two isolated Core daemons reached `TASK_STATE_COMPLETED`; CU not exposed by local wallet/RPC output |
| `wallet.send` local refresh proof | local standalone sequencer | public token transfer through `logos_execution_zone` wallet FFI | TBD | `22b2daffa8a526f17b4b370afe408edacbdfe48c2078af07c128673d5e402547` | verified 2026-06-22 after Basecamp owner-chat fixes; approval gate was tested first with zero limits |
| `agent.task` discovery + payment local refresh proof | local standalone sequencer | signed Agent Card discovery, task lifecycle, and LEZ payment | TBD | `cbe01582b0bd0fab691b73760b1919b94e9d2da3ae023e32d158b02404d29bd7` | verified 2026-06-22; client discovered signed card, paid price `1`, and both agents reached `TASK_STATE_COMPLETED` |
| `wallet.send` local balance-delta proof | local standalone sequencer | public token transfer through `logos_execution_zone` wallet FFI | TBD | `7a0ea38183efaa41883f702be23829f23665550f54e4531c45d183bf8a83094b` | verified 2026-06-24 with separated topup and transfer windows; sender `5095 -> 5094`, recipient `5 -> 6`, both nonces advanced by one |

## Hosted Testnet CU Status

Hosted-testnet tx evidence must use a wallet whose builtin program IDs match
the endpoint. The current public `main` wallet mismatches
`https://testnet.lez.logos.co/`; LEZ tag `v0.1.2` / commit `cf3639d8` matches
and passed `wallet check-health` on 2026-06-19 UTC.

The wallet output does not currently expose CU directly. Keep CU as `TBD` until
one of these sources is available:

- a Logos explorer transaction details page with CU/cycle fields;
- a sequencer metadata endpoint that returns CU/cycle fields for a transaction;
- wallet or sequencer logs that print execution cycles or proof stats;
- an evaluator-approved benchmark mapping from deterministic LEZ cycle counts
  to the requested prize CU field.

Do not infer or invent CU numbers from transaction success alone.

## Proposed Benchmark Method

The suggested reference is:

```text
https://github.com/fryorcraken/lez-signature-bench
```

That repository is a research benchmark for signature verification cost on
RISC Zero / LEZ, not a source of CU values for this agent. Its useful part for
LP-0008 is the measurement shape:

- run real proofs with `RISC0_DEV_MODE=0`;
- capture RISC Zero `ProveInfo.stats` fields such as `total_cycles`,
  `user_cycles`, `paging_cycles`, and `segments`;
- record wall-clock prove time and receipt size;
- for end-to-end cost, wrap a real private transaction submission against
  localnet and measure the full call that performs proving, serialization,
  sequencer round trip, and confirmation;
- record machine, LEZ version, RISC Zero version, and whether the result is
  local prove only or end-to-end transaction time.

For LP-0008, the benchmark target is not a signature algorithm matrix. The
target operations are the agent's on-chain actions:

- `wallet.send`;
- `agent.task` LEZ payment transfer;
- `agent.cancel` refund transfer when applicable;
- `program.deploy`;
- `program.call`.

The cleanest follow-up measurement is a small `agent_lez`/wallet-core benchmark
runner that executes the same transaction builders used by the agent, with
`RISC0_DEV_MODE=0`, and prints:

```text
operation | network | tx_hash | total_cycles | user_cycles | paging_cycles | segments | prove_seconds | receipt_bytes
```

Until that runner exists or the hosted testnet exposes CU/cycle metadata, the
submission should keep the current tx evidence and explicitly mark CU as
pending team clarification. This matches the team's guidance to apply now and
continue the CU discussion in the PR.
