# Hosted LEZ Testnet v0.2 Compatibility Evidence - 2026-06-25 UTC

This is the sanitized post-redeploy compatibility check for the LEZ
`v0.2.0-rc5` wallet against the advertised hosted testnet endpoint.

## Superseded By 2026-07-01 Final Run

This June 25 check captured the endpoint outage/proxy failure while Logos was
updating infrastructure. On 2026-06-26 Logos reported that the testnet was back
online, and a fresh `v0.2.0-rc5` run passed `wallet check-health`, matched
hosted/local program IDs, and produced hosted-testnet tx hashes for
`wallet.send`, `agent.task` payment, `program.deploy`, and `program.call`.
On 2026-07-01, final LEZ `v0.2.0` evidence superseded that rc5 run.

Use `docs/testnet-v020-final-evidence-20260701.md` as the current
hosted-testnet evidence. This file is retained as historical diagnosis for the
outage.

The Logos builders channel announced a LEZ redeploy on 2026-06-25 in
preparation for v0.2 Testnet. The announcement said state was wiped and
builders should recompile and redeploy programs against:

```text
https://github.com/logos-blockchain/logos-execution-zone/tree/v0.2.0-rc5
```

## Local v0.2 Setup

| Field | Value |
| --- | --- |
| LEZ ref | `v0.2.0-rc5` |
| LEZ commit | `27360cb7d6ccb2bfbcca7d171bab8a3938490264` |
| Wallet binary | `/home/agate/Projects/logos/logos-execution-zone-v0.2.0-rc5-testnet/target/release/wallet` |
| Wallet home env var | `LEE_WALLET_HOME_DIR` |
| Required Rust toolchain | `1.94.0` |
| Local build result | `cargo +1.94.0 build -p wallet --release -j1` succeeded |
| Circuits path | `$HOME/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.0-linux-x86_64` |
| `RISC0_DEV_MODE` | `0` for wallet checks |

The v0.2 wallet command surface still includes the hosted proof operations we
need:

- `wallet check-health`
- `wallet chain-info current-block-id`
- `wallet vault claim --account-id Public/... --amount ...`
- `wallet auth-transfer init --account-id Public/...`
- `wallet auth-transfer send --from Public/... --to Public/... --amount ...`
- `wallet deploy-program <binary>`

The important v0.2 change for a fresh wiped testnet is funding: the next live
run should use `vault claim` or the funding command confirmed by Logos instead
of relying on the pre-redeploy funded accounts from the June 19 evidence.

## Command Run

```bash
RUN_ROOT=.local/testnet-evidence/v020-rc5-check-$(date -u +%Y%m%dT%H%M%SZ) \
  ./scripts/lez-testnet-compatibility-evidence.sh \
  --lez-repo /home/agate/Projects/logos/logos-execution-zone-v0.2.0-rc5-testnet \
  --wallet /home/agate/Projects/logos/logos-execution-zone-v0.2.0-rc5-testnet/target/release/wallet
```

Raw run directory:

```text
.local/testnet-evidence/v020-rc5-check-20260625T182442Z
```

The raw run directory is intentionally not committed because it contains wallet
state. First-run recovery text was redacted by the evidence script.

## Result

| Check | Result |
| --- | --- |
| Endpoint | `https://testnet.lez.logos.co/` |
| Endpoint health OK | `false` |
| `wallet check-health` | fail, exit `101` |
| `chain-info current-block-id` | fail, exit `1` |
| `account list` | pass, exit `0` |
| Transaction submission allowed | `false` |

The endpoint returned JSON-RPC `METHOD_NOT_FOUND` for the wallet's expected
sequencer methods. Example `checkHealth` response:

```json
{"jsonrpc":"2.0","error":{"name":"REQUEST_VALIDATION_ERROR","cause":{"name":"METHOD_NOT_FOUND","info":{"method_name":"checkHealth"}},"code":-32601,"message":"Method not found","data":"checkHealth"},"id":1}
```

The v0.2 wallet then failed before transaction submission because the RPC error
shape contains a top-level `name` field not accepted by the wallet's JSON-RPC
error parser:

```text
Error fetching program ids: ParseError(Error("unknown field `name`, expected one of `code`, `message`, `data`", line: 1, column: 32))
```

## Endpoint Probe

The v0.2 source still declares the same sequencer RPC methods:

- `checkHealth`
- `getProgramIds`
- `getLastBlockId`
- `getTransaction`
- `getAccount`

Probing obvious endpoint variants did not find a working sequencer or indexer
JSON-RPC path:

- `https://testnet.lez.logos.co/` returned `METHOD_NOT_FOUND` for sequencer and
  indexer methods.
- `/rpc`, `/jsonrpc`, `/sequencer`, `/sequencer/rpc`, `/seq`, `/indexer`, and
  `/indexer/rpc` returned `404`.
- `sequencer.testnet.lez.logos.co`, `indexer.testnet.lez.logos.co`,
  `v2.testnet.lez.logos.co`, and similar guessed subdomains did not resolve.
- `https://explorer.testnet.lez.logos.co/` returned `502 Bad Gateway` during
  the check.

A pending `logos-docs` branch named `wallet-testnet-cli` still documents
`https://testnet.lez.logos.co` as the v0.2 sequencer address, so the current
blocker appears to be deployment/proxy availability or an unpublished endpoint
change, not an LP-0008 agent implementation issue.

The repeatable diagnostic command is:

```bash
./scripts/lez-v020-endpoint-diagnose.py \
  --url https://testnet.lez.logos.co/ \
  --all-paths
```

Expected success condition: at least `checkHealth`, `getProgramIds`, and
`getLastBlockId` return JSON-RPC `result` values at the wallet
`sequencer_addr`. Current failure condition: all sequencer/indexer methods at
the documented root return `METHOD_NOT_FOUND`.

## Submission Impact

This check proves that the local environment has adapted far enough to build
and run the v0.2 wallet. It does not produce post-redeploy hosted-testnet tx
hashes because the advertised endpoint is not currently exposing the wallet's
sequencer RPC methods.

Current status for LP-0008:

- June 19 hosted-testnet tx hashes remain historical pre-redeploy evidence.
- Current post-redeploy hosted-testnet evidence is blocked on the exact v0.2
  sequencer RPC endpoint/proxy behavior and funding path.
- Localnet/Basecamp/Storage/Messaging/A2A evidence is unaffected by the LEZ
  hosted-testnet state wipe.

## Rerun Once Endpoint Is Confirmed

After Logos confirms the v0.2 sequencer RPC URL, rerun:

```bash
TESTNET_URL=<confirmed-v0.2-sequencer-url> \
RUN_ROOT=.local/testnet-evidence/v020-rc5-live-$(date -u +%Y%m%dT%H%M%SZ) \
  ./scripts/lez-testnet-compatibility-evidence.sh \
  --lez-repo /home/agate/Projects/logos/logos-execution-zone-v0.2.0-rc5-testnet \
  --wallet /home/agate/Projects/logos/logos-execution-zone-v0.2.0-rc5-testnet/target/release/wallet
```

Proceed to funded transfers only when `summary.json` says:

```json
{"transaction_submission_allowed": true}
```

Then use the v0.2 wallet flow:

```bash
export LEE_WALLET_HOME_DIR=<run>/wallet-home
export LOGOS_BLOCKCHAIN_CIRCUITS=$HOME/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.0-linux-x86_64
export RISC0_DEV_MODE=0

wallet vault claim --account-id Public/<sender> --amount <amount>
wallet auth-transfer init --account-id Public/<sender>
wallet auth-transfer init --account-id Public/<recipient>
wallet auth-transfer send --from Public/<sender> --to Public/<recipient> --amount 1
```
