# Manual Intervention Checklist

The repository now contains the local module implementation, local smoke
evidence, hosted-testnet transaction evidence, packaging helpers, reviewer
demo entrypoint, Basecamp/module descriptor, and narrated demo videos.

## Recorded Demo Videos

- Video 1: repository readiness, package/evidence bundle, hosted-testnet
  transaction evidence, and submission overview.
  https://www.youtube.com/watch?v=fYlokf7NIfI
- Video 2: Basecamp owner-to-agent Chat flow and owner-channel skill calls.
  https://www.youtube.com/watch?v=nS8928doTkE
- Video 3: live skill proofs: Storage, wallet spending controls and transfer
  history, Messaging/Delivery, paid A2A, and program operations.
  https://www.youtube.com/watch?v=hxRQejaBhxo

## Completed Recording Coverage

- Basecamp owner-channel recording: Video 2.
- Two-agent Delivery/A2A proof: Video 3.
- Three illustrative use cases:
  - Personal file vault: Video 3.
  - Paid skill marketplace: Video 3.
  - Program operation: Video 3.
- Terminal proof output, hosted-testnet tx hashes, and `RISC0_DEV_MODE=0`:
  Videos 1 and 3.

## Manual/External Items Still Open

1. Official clean package build
   - Run `nix build --impure .#lgx -L` on a stable machine or GitHub workflow.
   - Keep the generated `.lgx` checksum with the final evidence bundle.

2. Post-redeploy LEZ v0.2 hosted-testnet refresh
   - Logos redeployed LEZ on 2026-06-25 and wiped state for v0.2.
   - The old June 19 tx hashes are now historical pre-redeploy evidence.
   - `logos-execution-zone` `v0.2.0-rc5` now builds locally with Rust
     `1.94.0`.
   - The advertised endpoint `https://testnet.lez.logos.co/` returned
     `METHOD_NOT_FOUND` for the v0.2 wallet's expected sequencer RPC methods.
   - Once Logos confirms the active v0.2 sequencer RPC URL/funding path, rerun
     wallet transfer, program deploy/call, and A2A payment evidence.

## CU Status

`docs/cu-report.md` documents CU as `TBD` because the current LEZ wallet/RPC
outputs do not expose CU fields. Replace `TBD` if Logos provides explorer
metadata, sequencer metadata, wallet/sequencer logs, or an evaluator-approved
benchmark mapping.

## Bundle Command

Create a sanitized review bundle with:

```bash
./scripts/create-submission-bundle.py
```

The bundle is written under `.local/submission-bundle/<timestamp>` and avoids
copying wallet state or raw runtime secrets.
