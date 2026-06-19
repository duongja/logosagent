# Hosted LEZ Testnet Wallet Transfer Evidence - 2026-06-19 UTC

This is the sanitized hosted-testnet transaction evidence captured with the LEZ
wallet matching the live testnet program artifacts.

Commands:

```bash
./scripts/lez-testnet-compatibility-evidence.sh \
  --lez-repo /home/agate/Projects/logos/logos-execution-zone-v0.1.2-testnet \
  --wallet /home/agate/Projects/logos/logos-execution-zone-v0.1.2-testnet/target/release/wallet

NSSA_WALLET_HOME_DIR=<run>/wallet-home \
LOGOS_BLOCKCHAIN_CIRCUITS=$HOME/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.0-linux-x86_64 \
RISC0_DEV_MODE=0 \
/home/agate/Projects/logos/logos-execution-zone-v0.1.2-testnet/target/release/wallet \
  auth-transfer send \
  --from Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV \
  --to Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo \
  --amount 1
```

Raw run directory:
`/home/agate/Projects/logos/logos-agent/.local/testnet-evidence/20260619T223523Z-lez-compat`

The raw run directory is intentionally not committed because it contains local
wallet state.

## Result

| Field | Value |
| --- | --- |
| Network | hosted LEZ testnet |
| Endpoint | `https://testnet.lez.logos.co/` |
| LEZ ref | `v0.1.2` |
| LEZ commit | `cf3639d8` |
| `RISC0_DEV_MODE` | `0` |
| Transaction hash | `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0` |
| From | `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV` |
| To | `Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo` |
| Amount | `1` |
| Transaction lookup returned transaction | `True` |

## Balance Evidence

| Account | Before balance | Before nonce | After balance | After nonce |
| --- | ---: | ---: | ---: | ---: |
| sender | 3648 | 38 | 3647 | 39 |
| recipient | 4000 | 7 | 4001 | 8 |

The sender decreased by `1`, the recipient increased by `1`, and both
nonces advanced by one. The transaction was retrieved again through
`wallet chain-info transaction --hash c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0`.
