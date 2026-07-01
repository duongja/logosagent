# Compute Unit Report

Current status: hosted-testnet and localnet transaction evidence exists for the
required on-chain operations, but the current LEZ wallet/RPC output used for
this submission does not expose compute-unit (CU) values directly. CU is
therefore reported as `TBD` until Logos provides explorer metadata, sequencer
metadata, wallet logs, or an evaluator-approved benchmark-to-CU mapping.

The Logos team advised submitting the LP-0008 PR while they clarify the exact CU
expectation, and suggested the `fryorcraken/lez-signature-bench` approach as a
measurement model. During submission preparation, Logos redeployed LEZ for
v0.2 and later restored the hosted endpoint. This report includes the fresh
final `v0.2.0` hosted-testnet hashes where available and keeps CU as `TBD`
until a CU/cycle data source is available.

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
| `wallet.send` hosted v0.2 testnet proof | hosted LEZ testnet | authenticated transfer, public-to-public | TBD | `3f140331aee32dba313d0eb73e47b1aad7e6f1dd5dfc8721460c16ac8a011c86` | verified 2026-06-26 with LEZ `v0.2.0-rc5` / `27360cb` and `RISC0_DEV_MODE=0`; sender `10000 -> 9999`, recipient `20000 -> 20001`; CU not exposed by wallet/RPC output |
| `agent.task` payment hosted v0.2 testnet proof | hosted LEZ testnet | token transfer for declared A2A skill price | TBD | `2111c69569e0804e28ca4210e9850a7db4171d6d7f3787d10c0f426629e461b4` | verified 2026-06-26 with LEZ `v0.2.0-rc5` / `27360cb`; payer `9999 -> 9998`, recipient `20001 -> 20002`; CU not exposed by wallet/RPC output |
| `program.deploy` hosted v0.2 testnet proof | hosted LEZ testnet | `data_changer.bin` deployment tx | TBD | `1db8975f24b5f27a4c271ea17f7db33e9d654964af8ab980ee78d0e351537f03` | verified 2026-06-26 with bytecode SHA-256 `7040a6af83a92834f947c366cf12255bcdbaf943401a131bf03345635801785f`; transaction lookup returned the deployment |
| `program.call` hosted v0.2 testnet proof | hosted LEZ testnet | signed public call, instruction `LP0008-v020` | TBD | `e752295333411623035c660016e8b1fb8deffdb4b7fc5c87fa0007eb004a8f30` | verified 2026-06-26; `getAccount` for `Public/HMeNkN8qAD5Ek8qK4SVBrUHZ1AQbTgnKf4C5EyfYfMB2` returned data bytes for `LP0008-v020` and nonce `1` |
| `agent.task` discovery + payment local proof | local standalone sequencer | signed Agent Card discovery, task lifecycle, and LEZ payment | TBD | `81b55313e470325b17d58328dc03da9f03538d7c970a24b8d98ea23c83e0ed74` | verified 2026-06-20; two isolated Core daemons reached `TASK_STATE_COMPLETED`; CU not exposed by local wallet/RPC output |
| `wallet.send` local refresh proof | local standalone sequencer | public token transfer through `logos_execution_zone` wallet FFI | TBD | `22b2daffa8a526f17b4b370afe408edacbdfe48c2078af07c128673d5e402547` | verified 2026-06-22 after Basecamp owner-chat fixes; approval gate was tested first with zero limits |
| `agent.task` discovery + payment local refresh proof | local standalone sequencer | signed Agent Card discovery, task lifecycle, and LEZ payment | TBD | `cbe01582b0bd0fab691b73760b1919b94e9d2da3ae023e32d158b02404d29bd7` | verified 2026-06-22; client discovered signed card, paid price `1`, and both agents reached `TASK_STATE_COMPLETED` |
| `wallet.send` hosted final v0.2.0 testnet proof | hosted LEZ testnet | authenticated transfer, public-to-public | TBD | `7bdeea835624591f222da7ece3d6a58f3663d5e943ee28f57d0ab35c37824de1` | verified 2026-07-01 with LEZ `v0.2.0` / `a58fbce` and `RISC0_DEV_MODE=0`; sender `10000 -> 9999`, recipient `20000 -> 20001`; CU not exposed by wallet/RPC output |
| `agent.task` payment hosted final v0.2.0 testnet proof | hosted LEZ testnet | token transfer for declared A2A skill price | TBD | `3d2d8a20b07c2df742078fbefdc18c6eb2e483e3ef9468681686e67f4d213894` | verified 2026-07-01 with LEZ `v0.2.0` / `a58fbce`; payer `9999 -> 9998`, recipient `20001 -> 20002`; CU not exposed by wallet/RPC output |
| `program.deploy` hosted final v0.2.0 testnet proof | hosted LEZ testnet | `hello_world_with_authorization.bin` deployment tx | TBD | `e9c0d01039e9ccb1b4c3ab915b263a6b4a6c5b8244737bb063b33282093a7d02` | verified 2026-07-01 with bytecode SHA-256 `a72944403dee3c259f87aa5fda684376ce53afd15b5ed541dd28147788f6de6f`; transaction lookup returned the deployment |
| `program.call` hosted final v0.2.0 testnet proof | hosted LEZ testnet | signed public call via `auth-transfer init` wallet facade | TBD | `ee2c922038fa225bb13d9dba9b8a9f63d48ccf23b8c1c6bd4ef1cb534f261e9f` | verified 2026-07-01 with LEZ `v0.2.0` / `a58fbce`; `getAccount` for `Public/CpF3WDqzMuPFtjwzdoiYZZv2p8gzEPM8uQToEZ2VfPDd` returned authenticated-transfer owner and nonce `1`; CU not exposed by wallet/RPC output |
| `wallet.send` local balance-delta proof | local standalone sequencer | public token transfer through `logos_execution_zone` wallet FFI | TBD | `7a0ea38183efaa41883f702be23829f23665550f54e4531c45d183bf8a83094b` | verified 2026-06-24 with separated topup and transfer windows; sender `5095 -> 5094`, recipient `5 -> 6`, both nonces advanced by one |

## Hosted Testnet CU Status

Hosted-testnet tx evidence must use a wallet whose builtin program IDs and RPC
client match the endpoint. LEZ tag `v0.1.2` / commit `cf3639d8` matched the
hosted testnet on 2026-06-19 UTC, LEZ `v0.2.0-rc5` / commit `27360cb`
matched the restored hosted testnet on 2026-06-26 UTC, and final LEZ `v0.2.0`
/ commit `a58fbce` matched the current hosted testnet on 2026-07-01 UTC. The
June 25 `METHOD_NOT_FOUND` compatibility failure is retained in
`docs/testnet-v020-compatibility-evidence-20260625.md` as outage diagnosis.

Keep CU as `TBD` until one of these sources is available:

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
