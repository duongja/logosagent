# Manual Intervention Checklist

The repository now contains the local module implementation, local smoke
evidence, hosted-testnet transaction evidence, packaging helpers, and narrated
demo videos.

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

1. CU values
   - Fill `docs/cu-report.md` if Logos exposes CU through explorer, sequencer metadata, or logs.
   - If CU is not exposed, get evaluator/Discord confirmation that `TBD` plus tx hashes and benchmark notes are acceptable.

2. Official clean package build
   - Run `nix build --impure .#lgx -L` on a stable machine or GitHub workflow.
   - Keep the generated `.lgx` checksum with the final evidence bundle.

## Bundle Command

Create a sanitized review bundle with:

```bash
./scripts/create-submission-bundle.py
```

The bundle is written under `.local/submission-bundle/<timestamp>` and avoids
copying wallet state or raw runtime secrets.
