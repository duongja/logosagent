# Hosted LEZ Testnet Compatibility Evidence - 2026-06-19 UTC

This is the sanitized hosted-testnet evidence captured before attempting
LP-0008 transaction/CU proofs.

Command:

```bash
./scripts/lez-testnet-compatibility-evidence.sh
./scripts/collect-prize-evidence.py --network testnet --out-dir .local/evidence/testnet
```

Raw run directory:
`.local/testnet-evidence/20260619T220346Z-lez-compat`

The raw run directory is intentionally not committed because it contains local
wallet state. The script redacts first-run wallet recovery text in
`check-health.out`.

## Result

| Check | Result |
| --- | --- |
| Endpoint | `https://testnet.lez.logos.co/` |
| JSON-RPC health | pass |
| `RISC0_DEV_MODE` | `0` |
| Wallet binary | `/home/agate/Projects/logos/logos-execution-zone/target/release/wallet` |
| LEZ commit | `feb6cb7` |
| `chain-info current-block-id` | `61095` |
| `account list` | pass |
| `wallet check-health` | fail, exit `101` |
| Transaction submission allowed | `false` |

The blocking wallet error is:

```text
Local ID for authenticated transfer program is different from remote
```

## Program ID Comparison

| Program | Hosted testnet ID | Local wallet ID | Match |
| --- | --- | --- | --- |
| `authenticated_transfer` | `[2299031209, 167565122, 3685861295, 2354389330, 2893215591, 1305489537, 3699818737, 2072750855]` | `[2172491596, 648287714, 3443481193, 1757114575, 2729968860, 2157376487, 835305942, 2223466012]` | no |
| `token` | `[2110201453, 1203268930, 3112084450, 2022553444, 396343408, 925204476, 1174463936, 1350666941]` | `[664952939, 3456132434, 1055856027, 1705590473, 2570385571, 3826567200, 4042147081, 3504740204]` | no |
| `pinata` | `[1798617790, 283257585, 2803511387, 764546991, 378103597, 1797965152, 4201122291, 3484074699]` | `[1210315115, 207568704, 3856089589, 3136569296, 524509414, 5944160, 3269601508, 3339412106]` | no |
| `amm` | `[458607522, 580067104, 3553453937, 470289546, 3558635307, 3646867965, 846272080, 3198149554]` | `[447541961, 895284501, 4022919768, 40236128, 3348905528, 3677176887, 958465322, 2868275295]` | no |
| `privacy_preserving_circuit` | `[2714931404, 2035572852, 221042473, 4270660760, 1882871986, 1904620030, 2269507084, 4114147883]` | `[3071279662, 250125373, 4204929257, 4055091220, 3962245221, 2089771828, 3551343405, 3203431156]` | no |

## Conclusion

Hosted-testnet transaction evidence is blocked by LEZ artifact mismatch, not by
the LP-0008 agent module. Do not submit hosted-testnet `wallet.send`,
`agent.task` payment, `program.deploy`, or `program.call` proofs from this
wallet until `wallet check-health` passes.

Required external input:

- exact LEZ wallet/artifact commit for `https://testnet.lez.logos.co/`; or
- matching prebuilt wallet binary; or
- a testnet redeploy aligned to the public wallet artifacts.
