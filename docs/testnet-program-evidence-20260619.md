# Hosted LEZ Testnet Program Evidence - 2026-06-19 UTC

This is the sanitized hosted-testnet evidence for `program.deploy` and a signed
`program.call` captured with the LEZ wallet/runtime artifacts matching the live
testnet.

Raw run directory:
`/home/agate/Projects/logos/logos-agent/.local/testnet-evidence/20260619T223523Z-lez-compat`

The raw run directory is intentionally not committed because it contains local
wallet state. The compact local summary is
`testnet-program-evidence-summary.json` inside that run directory.

## Environment

| Field | Value |
| --- | --- |
| Network | hosted LEZ testnet |
| Endpoint | `https://testnet.lez.logos.co/` |
| LEZ ref | `v0.1.2` |
| LEZ commit | `cf3639d8` |
| `RISC0_DEV_MODE` | `0` |
| Program binary | `hello_world_with_authorization.bin` |
| Program binary size | `386684` bytes |

## `program.deploy`

| Field | Value |
| --- | --- |
| Transaction hash | `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb` |
| Expected hash matched RPC hash | `true` |
| Transaction lookup returned transaction | `true` |

The deployment was submitted as a LEZ `ProgramDeploymentTransaction` over the
hosted testnet JSON-RPC endpoint. The transaction hash was computed locally from
the Borsh transaction bytes and matched the hash returned by the sequencer.

## `program.call`

| Field | Value |
| --- | --- |
| Transaction hash | `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518` |
| Expected hash matched RPC hash | `true` |
| Transaction lookup returned transaction | `true` |
| Program ID | `[747196075, 550424275, 870364738, 1720266279, 3351204663, 3506403667, 1516167069, 1324391327]` |
| Account | `Public/3XJoAbLkgSjyAnS7XngaiBdcaU54UzN67FH9Q8NGbbgT` |
| Instruction | `Hola mundo!` |
| Account data after call | `Hola mundo!` |
| Account nonce after call | `1` |

The call used a signed public transaction against `hello_world_with_authorization`.
The account state returned by `getAccount` after inclusion was:

```json
{"program_owner":[747196075,550424275,870364738,1720266279,3351204663,3506403667,1516167069,1324391327],"balance":0,"data":[72,111,108,97,32,109,117,110,100,111,33],"nonce":1}
```

The `data` bytes decode to `Hola mundo!`, proving the deployed program executed
and modified the account state.

## Note On Unsigned Call Attempt

An unsigned `hello_world` call was accepted by the RPC mempool but did not land
in a block. Current LEZ validation requires authorization for claiming a new
public account, so the successful proof uses the authorization-aware example and
a wallet-owned signer.
