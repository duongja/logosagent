# Hosted LEZ Testnet v0.2 Live Evidence - 2026-06-26 UTC

This is the sanitized post-outage hosted-testnet evidence captured after Logos
reported that `https://testnet.lez.logos.co/` was back online.

Raw run directory:

```text
.local/testnet-evidence/v020-rc5-live-tx-20260626T101906Z
```

The raw directory is intentionally not committed because it contains local
wallet state. Compact summaries from that run are included in generated
submission bundles.

## Environment

| Field | Value |
| --- | --- |
| Network | hosted LEZ testnet |
| Endpoint | `https://testnet.lez.logos.co/` |
| LEZ ref | `v0.2.0-rc5` |
| LEZ commit | `27360cb7d6ccb2bfbcca7d171bab8a3938490264` |
| Wallet binary | `/home/agate/Projects/logos/logos-execution-zone-v0.2.0-rc5-testnet/target/release/wallet` |
| Wallet home env var | `LEE_WALLET_HOME_DIR` |
| `RISC0_DEV_MODE` | `0` |

The compatibility gate passed before transactions were submitted:

- `wallet check-health` exited `0`;
- `chain-info current-block-id` exited `0`;
- hosted and local builtin program IDs matched;
- compact RPC lookups returned transactions for all hashes listed below.

## `wallet.send`

| Field | Value |
| --- | --- |
| Transaction hash | `3f140331aee32dba313d0eb73e47b1aad7e6f1dd5dfc8721460c16ac8a011c86` |
| From | `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV` |
| To | `Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo` |
| Amount | `1` |
| Block observed | `3398` |
| Transaction lookup returned transaction | `true` |

Balance evidence:

| Account | Before balance | Before nonce | After balance | After nonce |
| --- | ---: | ---: | ---: | ---: |
| sender | 10000 | 0 | 9999 | 1 |
| recipient | 20000 | 0 | 20001 | 1 |

## A2A Payment Leg

| Field | Value |
| --- | --- |
| A2A task id | `task-testnet-paid-a2a-20260626T102405Z` |
| Skill id | `messaging.echo` |
| Declared price | `1 LEZ` |
| Payment transaction hash | `2111c69569e0804e28ca4210e9850a7db4171d6d7f3787d10c0f426629e461b4` |
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
| Program binary | `data_changer.bin` |
| Program binary size | `385232` bytes |
| Bytecode SHA-256 | `7040a6af83a92834f947c366cf12255bcdbaf943401a131bf03345635801785f` |
| Transaction hash | `1db8975f24b5f27a4c271ea17f7db33e9d654964af8ab980ee78d0e351537f03` |
| Block observed | `3405` |
| Transaction lookup returned transaction | `true` |

The current `v0.2.0-rc5` `wallet deploy-program` command exits successfully but
does not print the sequencer response. The hash above was derived from the LEZ
`ProgramDeploymentTransaction` Borsh bytes and then verified through
`getTransaction`.

## `program.call`

| Field | Value |
| --- | --- |
| Transaction hash | `e752295333411623035c660016e8b1fb8deffdb4b7fc5c87fa0007eb004a8f30` |
| Account | `Public/HMeNkN8qAD5Ek8qK4SVBrUHZ1AQbTgnKf4C5EyfYfMB2` |
| Instruction payload | `LP0008-v020` |
| Block observed | `3425` |
| Transaction lookup returned transaction | `true` |
| Account nonce after call | `1` |
| Account data after call | `LP0008-v020` |

Final `getAccount` returned:

```json
{"program_owner":[3209599172,2531383504,4045322245,4199256023,496270304,4119425003,2701716433,2849628902],"balance":0,"data":[76,80,48,48,48,56,45,118,48,50,48],"nonce":1}
```

The `data` bytes decode to `LP0008-v020`, proving the deployed program
executed and modified account state. Earlier unsigned `PublicNoSign` attempts
did not land; the successful evidence used a signed `AccountIdentity::Public`
call because the program claims a fresh public account through the authorization
path.

## Scope

This document supersedes the June 25 endpoint-blocked note for hosted v0.2
transaction evidence. CU values are still marked `TBD` in `docs/cu-report.md`
because the wallet/RPC responses used here do not expose CU fields.
