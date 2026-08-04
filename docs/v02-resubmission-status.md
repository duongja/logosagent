# Testnet v0.2 Resubmission Status

## Evidence classification

The June and July evidence documents predate the integrated resubmission
harness. Their hosted LEZ hashes show wallet/program activity on LEZ, but do not
prove that a running `logos_agent` module initiated those operations. Recorded
Storage, Delivery, A2A lifecycle, and Basecamp flows are local or use the
earlier module stack. They are historical development records only.

## Current implementation target

- Logos Core CLI `v0.2.0`.
- Delivery module `v0.1.3` (the package published for Testnet v0.2), preset `logos.test`.
- Storage module `v2.0.1`, network `logos.test`.
- Chat module `v0.2.1`.
- LEZ Core module `v0.2.0`, module name `lez_core`, pinned to the official
  module revision that embeds LEZ `v0.2.0` for the public v0.2 sequencer RPC.
- Correlated `logos.agent.evidence.v1` audit events.

Exact source revisions are recorded in `dependencies-v0.2.json`.

## Acceptance status

- Repository migration and evidence tooling: implemented.
- Automatic local module E2E workflow: configured; a public passing Actions run
  is required before resubmission.
- Public two-agent Testnet v0.2 proof: complete. The authoritative run is
  `run_62d7e4e3fbc2439594822ec3ac835c1a` under
  `evidence/current/testnet-v02/`.
- The paid task reached `TASK_STATE_COMPLETED`; LEZ transaction
  `ee5b41972e315f0bca0d2c7745048dfe6e875418ccef1b132160f35995d9d9ea`
  was initiated through `logos_agent`, changed the payer balance from `7369`
  to `7368`, and was returned by the public sequencer's `getTransaction` RPC.
- Signed Agent Card discovery and task/status traffic used Delivery
  `logos.test`. Storage upload/download used `logos.test` and produced matching
  plaintext SHA-256 values.
- Replacement narrated video: pending a continuous recording of the successful
  public run and evidence validator.

The public proof is committed and independently verifiable. Do not describe the
replacement video or public Actions run as complete until their links are added.

## LEZ compatibility resolution

The moving module catalog currently publishes LEZ Core `0.4.0`, which embeds a
newer RPC surface than the public v0.2 sequencer. The public endpoint returned
`MethodNotFound` for that combination. The successful run instead uses the
official LEZ Core `0.2.0` module revision
`92dd9e25bcc6be04f841671e8da7b94bd2449f39`, built as the production
`lgx-portable` variant. Exact artifact checksums are locked in
`dependencies-v0.2.json`.
