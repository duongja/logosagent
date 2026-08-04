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
workspace. The generated LGX is 4,138,893 bytes with SHA-256
`01b93371a28d00b658d0177c0e11572e5996cd1d7ca2154f4d498f7037a72db3`.
Its manifest root is
`1c7b162f7b1bed7a65c45e9fe57e3586ac05367893c3a3a1df50b709d2e7e9a0`.

## Completed Public CI Verification

Public Actions run
[30932258747](https://github.com/duongja/logosagent/actions/runs/30932258747)
passed submission preflight, released-interface tests, and the full local
two-agent E2E. The E2E covered Storage, Delivery discovery and task traffic,
unsigned and paid A2A lifecycles, LEZ wallet transfer, and program
query/call/deploy. The run published the sanitized
[E2E evidence artifact](https://github.com/duongja/logosagent/actions/runs/30932258747/artifacts/8903988192)
and the
[v0.2 dependency/LGX artifact](https://github.com/duongja/logosagent/actions/runs/30932258747/artifacts/8903988755).

## Manual/External Items Still Open

1. Replacement public-testnet video
   - Record one continuous run showing the two agents, module versions,
     Delivery discovery/task events, Storage verification, LEZ transaction
     lookup, evidence validation, and the public CI result.

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
