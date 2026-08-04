# Manual Intervention Checklist

The repository now contains the local module implementation, local smoke
evidence, hosted-testnet transaction evidence, packaging helpers, reviewer
demo entrypoint, Basecamp/module descriptor, and narrated demo videos.

The three existing videos cover the earlier implementation. They are retained
for historical context and do not replace the continuous Testnet v0.2 recording
listed under the open items below.

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

## Completed Package Verification

The official v0.2 portable package build completed from the bootstrapped pinned
workspace. The generated LGX is 4,139,661 bytes with SHA-256
`5e1de2c30d40c47804c4713bd753d4ca0334ef6df7a51c11ae8a5e82d5b3c78d`.
Its manifest root is
`d9619ba8611fefd91a3777294285508573bbe53b5ae7480f46d11d2fd26ec15b`.

## Manual/External Items Still Open

1. Replacement public-testnet video
   - Record one continuous run showing the two agents, module versions,
     Delivery discovery/task events, Storage verification, LEZ transaction
     lookup, evidence validation, and the public CI result.

2. Public Actions URL
   - Push the repository changes and link the first passing automatic local E2E
     run. The self-hosted public-testnet workflow remains scheduled/manual.

3. CU values
   - Keep CU as `TBD` unless Logos provides explorer metadata, sequencer
     metadata, wallet/sequencer proof stats, or an evaluator-approved benchmark
     mapping.

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
