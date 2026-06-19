# Hosted LEZ Testnet A2A Payment Evidence - 2026-06-19 UTC

This is the sanitized hosted-testnet evidence for the LEZ payment leg of a
paid A2A task. It complements the local Delivery/A2A lifecycle smoke tests by
showing the declared task price paid with a real hosted-testnet transaction.

Raw run directory:
`/home/agate/Projects/logos/logos-agent/.local/testnet-evidence/20260619T223523Z-lez-compat`

The raw run directory is intentionally not committed because it contains local
wallet state. The compact local summary is
`testnet-a2a-payment-summary.json` inside that run directory.

## Command

```bash
./scripts/lez-testnet-a2a-payment-evidence.sh
```

The script reuses the hosted-testnet compatibility run wallet home and runs:

```bash
NSSA_WALLET_HOME_DIR=<run>/wallet-home \
LOGOS_BLOCKCHAIN_CIRCUITS=$HOME/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.0-linux-x86_64 \
RISC0_DEV_MODE=0 \
/home/agate/Projects/logos/logos-execution-zone-v0.1.2-testnet/target/release/wallet \
  auth-transfer send \
  --from Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV \
  --to Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo \
  --amount 1
```

## Result

| Field | Value |
| --- | --- |
| Network | hosted LEZ testnet |
| Endpoint | `https://testnet.lez.logos.co/` |
| LEZ ref | `v0.1.2` |
| LEZ commit | `cf3639d` |
| `RISC0_DEV_MODE` | `0` |
| A2A task id | `task-testnet-paid-a2a-20260619T235140Z` |
| Skill id | `messaging.echo` |
| Declared price | `1 LEZ` |
| Payment recipient | `Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo` |
| Payment transaction hash | `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494` |
| Transaction lookup returned transaction | `true` |

## Balance Evidence

| Account | Before balance | Before nonce | After balance | After nonce |
| --- | ---: | ---: | ---: | ---: |
| payer/client | 3647 | 39 | 3646 | 40 |
| recipient/server | 4001 | 8 | 4002 | 9 |

The payer decreased by `1`, the recipient increased by `1`, and both nonces
advanced by one.

## Scope Note

This proves the hosted-testnet LEZ payment leg for a paid A2A task record. The
full live two-agent Delivery transport run remains separate prize evidence:
local A2A lifecycle and paid/refund flows are already proven, but the final
submission still needs a live Delivery/Basecamp or multi-node agent run that
combines discovery, task lifecycle, and this payment path in one recorded flow.
