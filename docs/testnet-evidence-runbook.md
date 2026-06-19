# Testnet Evidence Runbook

This is the remaining proof path for prize readiness. The local implementation
is already exercised by the smoke scripts; final submission needs the same
flows recorded against the target LEZ testnet/devnet environment with tx hashes
and CU/cycle evidence.

## Preconditions

- Use the LEZ wallet/config expected by the target testnet.
- Keep `RISC0_DEV_MODE=0` for any proof-generating run.
- Fund the agent account and any peer-agent payment accounts.
- Keep Basecamp setup/install separate from heavy Nix builds on low-memory
  machines.

## Package Evidence

```bash
./scripts/package-dev-lgx.sh
./scripts/package-live-modules-lgx.sh
./scripts/basecamp-owner-channel.sh --capture-only
./scripts/basecamp-profile-install-smoke.sh
./scripts/prepare-three-agent-deployment.sh --network testnet --delivery-preset logos.dev
./scripts/collect-prize-evidence.py --network localnet
```

For final testnet evidence, rerun the collector with `--network testnet` and
explicit run roots:

```bash
./scripts/collect-prize-evidence.py \
  --network testnet \
  --wallet-run .local/agent-wallet-smoke/<testnet-run> \
  --storage-run .local/agent-storage-smoke/<testnet-run> \
  --messaging-run .local/agent-messaging-smoke/<testnet-run> \
  --a2a-run .local/agent-a2a-paid-smoke/<testnet-run> \
  --program-run .local/agent-program-smoke/<testnet-run> \
  --out-dir .local/evidence/testnet
```

The collector writes `evidence.json` and `evidence.md`. It does not copy raw run
roots by default because those directories can contain wallet keys and runtime
state. Use `--copy-runs` only for a deliberately redacted archive review path.

## Required Live Proofs

Before recording live proofs, use
`.local/testnet-agents/latest/manifest.json` from
`scripts/prepare-three-agent-deployment.sh` as the deployment checklist for the
three required prize agents.

1. `wallet.send`
   - Agent has its own LEZ account.
   - Below-threshold transfer submits without owner approval.
   - Above-threshold transfer remains pending until owner approval.
   - Evidence: tx hash, wallet history, policy config, CU/cycles if exposed.

2. Storage
   - `storage.upload`, `storage.list`, `storage.share`, `storage.download`.
   - Evidence: content address, share recipient, downloaded file hash matching
     original.

3. Messaging and owner channel
   - Basecamp profile loads the module set.
   - Owner sends a JSON skill call over Chat and receives the agent response.
   - Evidence: Basecamp screen recording plus agent/Core logs.

4. Paid A2A
   - Two agents discover each other.
   - Client submits a paid task using the server Agent Card price.
   - Server reaches a valid A2A terminal state.
   - Cancellation/refund path is shown if using an input-required task.
   - Evidence: task id, Agent Cards, payment tx hash, refund tx hash if any.

5. Program operations
   - `program.query`.
   - `program.deploy` using the testnet-supported LEZ deploy path.
   - `program.call` using a stable wallet facade or program-specific runner.
   - Evidence: program id, tx hash where exposed, CU/cycles if exposed.

## CU/Cycle Reporting

The LEZ docs currently expose deterministic program cycle counts through
`cycle_bench` and transaction/block size evidence through `integration_bench`.
For final prize submission, fill `docs/cu-report.md` from the most authoritative
source available for the target network:

- Explorer or sequencer transaction metadata, if CU is exposed directly.
- Wallet/sequencer logs, if they print execution cycles or proof stats.
- LEZ benchmark docs for deterministic instruction cycles, clearly marked as
  benchmark-derived rather than testnet-explorer-derived.

Do not present local benchmark cycle counts as testnet CU unless the evaluator
accepts that mapping.
