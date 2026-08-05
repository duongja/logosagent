# Testnet Chain Status - 2026-08-05 UTC

This note separates the successful 2026-08-03 capture from what the public LEZ
endpoint exposes now. It prevents a reviewer from being given a transaction
hash that no longer resolves.

## Live Checks

At `2026-08-05T20:11:28Z`, direct JSON-RPC calls to
`https://testnet.lez.logos.co/` returned:

- `getLastBlockId`: `59`.
- `getTransaction` for
  `ee5b41972e315f0bca0d2c7745048dfe6e875418ccef1b132160f35995d9d9ea`:
  `null`.
- The two genesis-funded public accounts: their original balances (`10000` and
  `20000`) and nonce `0`.

Those results indicate that the chain state used by the 2026-08-03 integrated
run was reset. The committed `transaction-confirmation.json` remains an exact
capture-time response, but the hash must not be described as currently
explorer-verifiable.

The current sequencer's `getProgramIds` response also differs from the program
IDs built by the published LEZ `v0.2.0` source at commit
`a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a`. The official wallet's
`check-health` compatibility gate therefore refuses transaction submission.
Bypassing that gate would not be credible evidence.

## Agent Availability

The persistent Railway agent is independently live at
`https://logos-agent-production.up.railway.app`. Its sanitized health response
reports:

- network `logos-testnet-v0.2`;
- Delivery preset `logos.test`, connected;
- Storage network `logos.test`, started;
- Delivery `0.1.3`, Storage `2.0.1`, Chat `0.2.1`, LEZ Core `0.2.0`, and
  Logos Agent `0.2.0`;
- a signed Agent Card with a stable Ed25519 identity across redeployment.

That endpoint proves current agent availability on Delivery and Storage. It
does not replace a confirmed paid A2A task. Its newly created LEZ account has a
zero balance.

## Required Replacement Run

Before resubmitting:

1. Obtain the LEZ wallet/module build that matches the current public
   `getProgramIds` response, or wait for the public endpoint to return to the
   published v0.2.0 program set.
2. Fund the hosted agent and a second isolated agent without committing wallet
   material.
3. Rerun `./demo.sh --testnet` so Delivery discovery, Storage round-trip, paid
   task completion, and the new transaction share one `run_id`.
4. Confirm the new hash through both the sequencer and explorer, replace
   `evidence/current/testnet-v02/`, and record the continuous replacement video.
