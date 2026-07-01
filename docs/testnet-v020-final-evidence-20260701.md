# Hosted LEZ Testnet v0.2.0 Final Evidence - 2026-07-01 UTC

This is the sanitized hosted-testnet evidence refreshed after Logos announced
that the final `v0.2.0` tag should be used for compatible wallets and programs.

Raw run directory:

```text
.local/testnet-evidence/v020-final-live-20260701T092833Z
```

The raw directory is intentionally not committed because it contains local
wallet state. The compact summaries from that run are included in generated
submission bundles.

## Environment

| Field | Value |
| --- | --- |
| Network | hosted LEZ testnet |
| Endpoint | `https://testnet.lez.logos.co/` |
| LEZ ref | `v0.2.0` |
| LEZ commit | `a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a` |
| Wallet binary | `/home/agate/Projects/logos/logos-execution-zone-v0.2.0-testnet/target/release/wallet` |
| Wallet home env var | `LEE_WALLET_HOME_DIR` |
| `RISC0_DEV_MODE` | `0` |

The compatibility gate passed before transactions were submitted:

- `wallet check-health` exited `0`;
- `chain-info current-block-id` exited `0`;
- hosted RPC returned current chain data;
- transaction lookups returned the current hosted-testnet transactions listed
  below.

## `wallet.send`

| Field | Value |
| --- | --- |
| Transaction hash | `7bdeea835624591f222da7ece3d6a58f3663d5e943ee28f57d0ab35c37824de1` |
| From | `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV` |
| To | `Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo` |
| Amount | `1` |
| Transaction lookup returned transaction | `true` |

Balance evidence:

| Account | Before balance | Before nonce | After balance | After nonce |
| --- | ---: | ---: | ---: | ---: |
| sender | 10000 | 0 | 9999 | 1 |
| recipient | 20000 | 0 | 20001 | 1 |

## A2A Payment Leg

| Field | Value |
| --- | --- |
| A2A task id | `task-testnet-paid-a2a-20260701T093238Z` |
| Skill id | `messaging.echo` |
| Declared price | `1 LEZ` |
| Payment transaction hash | `3d2d8a20b07c2df742078fbefdc18c6eb2e483e3ef9468681686e67f4d213894` |
| Payer | `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV` |
| Recipient | `Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo` |
| Transaction lookup returned transaction | `true` |

Balance evidence:

| Account | Before balance | Before nonce | After balance | After nonce |
| --- | ---: | ---: | ---: | ---: |
| payer/client | 9999 | 1 | 9998 | 2 |
| recipient/server | 20001 | 1 | 20002 | 2 |

This hosted-testnet proof covers the LEZ payment leg for a priced A2A task.
The full two-agent Delivery discovery and A2A task lifecycle proof is captured
locally in `docs/localnet-a2a-discovery-payment-evidence-20260620.md` and in
the narrated demo videos.

## `program.deploy`

| Field | Value |
| --- | --- |
| Program binary | `hello_world_with_authorization.bin` |
| Program binary size | `386736` bytes |
| Bytecode SHA-256 | `a72944403dee3c259f87aa5fda684376ce53afd15b5ed541dd28147788f6de6f` |
| Program ID / image ID | `a1bce575b806c83e4e6760f65027c2ae216dcffd8d4fcad94aeed51c729e320b` |
| Transaction hash | `e9c0d01039e9ccb1b4c3ab915b263a6b4a6c5b8244737bb063b33282093a7d02` |
| Transaction lookup returned transaction | `true` |

The current `v0.2.0` `wallet deploy-program` command exits successfully but
does not print the sequencer response. The hash above was derived from the LEZ
`ProgramDeploymentTransaction` Borsh bytes and then verified through
`getTransaction`.

## `program.call`

Final hosted `v0.2.0` `program.call` evidence uses the stable wallet facade
for the builtin `authenticated_transfer` program. The command was:

```bash
wallet auth-transfer init --account-id Public/CpF3WDqzMuPFtjwzdoiYZZv2p8gzEPM8uQToEZ2VfPDd
```

This is a real public program transaction with signer authorization, a hosted
testnet transaction hash, RPC transaction lookup, and account nonce advancing
to `1`. It avoids the heavier arbitrary-program example runner while still
proving the agent's `program.call` path can submit a LEZ program instruction.

| Field | Value |
| --- | --- |
| Transaction hash | `ee2c922038fa225bb13d9dba9b8a9f63d48ccf23b8c1c6bd4ef1cb534f261e9f` |
| Program | `authenticated_transfer` |
| Program ID | `[3170810844, 2526647253, 999807262, 1205602179, 3401962591, 3484055895, 2106546407, 1900691388]` |
| Account | `Public/CpF3WDqzMuPFtjwzdoiYZZv2p8gzEPM8uQToEZ2VfPDd` |
| Instruction | `auth-transfer init` |
| Instruction data | `[1]` |
| Transaction lookup returned transaction | `true` |
| Account nonce after call | `1` |

Final `getAccount` returned the account owned by `authenticated_transfer` with
nonce `1`:

```json
{"program_owner":[3170810844,2526647253,999807262,1205602179,3401962591,3484055895,2106546407,1900691388],"balance":0,"data":[],"nonce":1}
```

The custom `hello_world_with_authorization` arbitrary-program runner remains a
heavier demo path. On this laptop it entered the RISC0 C++ prover support build
and was stopped to avoid repeated laptop crashes. The stable wallet-facade call
above is the final hosted `program.call` proof; the arbitrary-program runner
can be rerun later on a larger or already-cached build host if evaluators
specifically request that exact custom-program example.

## Scope

This document supersedes the June 26 `v0.2.0-rc5` page as the current hosted
LEZ evidence target. CU values are still marked `TBD` in `docs/cu-report.md`
because the wallet/RPC responses used here do not expose CU fields.
