# Localnet Prize Evidence Refresh - 2026-06-22

This document records the fresh LP-0008 evidence run completed on
2026-06-22 after the Basecamp owner-channel fixes. Raw `.local` run
directories are intentionally not committed because they can contain wallet
storage, runtime state, and local profile data.

## Summary

All default skill categories and the paid A2A flow were re-run successfully on
the local standalone sequencer / local Logos Core setup:

- Storage: `storage.upload`, `storage.list`, `storage.share`,
  `storage.download`, with downloaded bytes matching the original file.
- Wallet: spending-threshold approval gate, `wallet.balance`, `wallet.send`,
  and `wallet.history`.
- Messaging: `messaging.create_group`, `messaging.join`, and
  `messaging.send` over Delivery with a raw receiver proving delivery.
- A2A: signed Agent Card discovery, task submission, subscription/status, and
  terminal `TASK_STATE_COMPLETED` on both agents.
- Paid A2A: task payment attached to the A2A receipt with a real localnet LEZ
  payment transaction hash.
- Program operations: `program.query`, `program.call`, and `program.deploy`
  through the current supported wallet/helper bridge.

The current sanitized collector output was generated with:

```bash
python3 scripts/collect-prize-evidence.py \
  --network localnet \
  --out-dir .local/evidence/latest-prize-refresh
```

## Run Artifacts

| Area | Run Root | Result |
| --- | --- | --- |
| Storage | `.local/agent-storage-smoke/prize-20260622T151126Z` | `ok = true` |
| Wallet | `.local/agent-wallet-smoke/prize-20260622T151246Z` | `ok = true` |
| A2A lifecycle | `.local/agent-a2a-smoke/prize-20260622T151335Z` | `ok = true` |
| Paid A2A | `.local/agent-a2a-paid-smoke/prize-20260622T151443Z` | `ok = true` |
| Messaging | `.local/agent-messaging-smoke/prize-20260622T151706Z` | `ok = true` |
| Program | `.local/agent-program-smoke/prize-20260622T151751Z` | `ok = true` |

## Key Evidence Values

- Storage content address:
  `zDvZRwzmDgqgmHKmGhXFpXsWitckj81Tuzk3vKfABaPV4VHvrXxU`
- Wallet localnet transfer tx:
  `22b2daffa8a526f17b4b370afe408edacbdfe48c2078af07c128673d5e402547`
- Paid A2A localnet payment tx:
  `cbe01582b0bd0fab691b73760b1919b94e9d2da3ae023e32d158b02404d29bd7`
- Paid A2A task id:
  `task-a2a-smoke-20260622T151514Z`
- Paid A2A terminal states:
  `TASK_STATE_COMPLETED` on client and server.
- Program ID from `program.deploy`:
  `e0dac2d532553d5c059523c920c36bfe47fbe39c45434ce0c66e08dcf856d75f`

## Commands Run

```bash
./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 \
  --run-root .local/test-runs/20260622T151126Z-agent-storage-prize-evidence \
  -- ./scripts/agent-storage-smoke.sh \
  --run-root .local/agent-storage-smoke/prize-20260622T151126Z

./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 \
  --run-root .local/test-runs/20260622T151246Z-agent-wallet-prize-evidence \
  -- ./scripts/agent-wallet-smoke.sh \
  --run-root .local/agent-wallet-smoke/prize-20260622T151246Z \
  --localnet-timeout 240

./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 \
  --run-root .local/test-runs/20260622T151335Z-agent-a2a-prize-evidence \
  -- ./scripts/agent-a2a-smoke.sh \
  --run-root .local/agent-a2a-smoke/prize-20260622T151335Z \
  --task-timeout 120 \
  --daemon-timeout 45

./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 \
  --run-root .local/test-runs/20260622T151443Z-agent-a2a-paid-prize-evidence \
  -- ./scripts/agent-a2a-paid-smoke.sh \
  --run-root .local/agent-a2a-paid-smoke/prize-20260622T151443Z \
  --localnet-timeout 240

./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 \
  --run-root .local/test-runs/20260622T151706Z-agent-messaging-prize-evidence \
  -- ./scripts/agent-messaging-smoke.sh \
  --run-root .local/agent-messaging-smoke/prize-20260622T151706Z \
  --message-timeout 90 \
  --daemon-timeout 45

./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 \
  --run-root .local/test-runs/20260622T151751Z-agent-program-prize-evidence \
  -- ./scripts/agent-program-smoke.sh \
  --run-root .local/agent-program-smoke/prize-20260622T151751Z \
  --localnet-timeout 240 \
  --daemon-timeout 45
```

## Hosted-Testnet Relationship

The localnet refresh complements the hosted-testnet evidence captured on
2026-06-19:

- Hosted `wallet.send` tx:
  `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0`
- Hosted `program.deploy` tx:
  `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb`
- Hosted `program.call` tx:
  `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518`
- Hosted paid A2A payment leg tx:
  `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494`

The hosted testnet does not currently expose Storage or Delivery as a hosted
testnet network in the same way LEZ does, so those modules are proven through
local Logos Core/Basecamp/Delivery evidence.

