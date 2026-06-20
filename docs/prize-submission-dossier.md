# LP-0008 Prize Submission Dossier

This file is the public, committed review map for the current submission state.
It avoids raw `.local` runtime state, wallet storage, and other local secrets.

## Built Components

- Logos Core module: `logos_agent`.
- CLI: `cli/logos-agent-cli`.
- Skill interface: `docs/skill-interface.md`.
- Owner/Basecamp path: `docs/owner-channel-basecamp.md`.
- A2A over Logos Messaging binding: `docs/a2a-logos-messaging-binding.md`.
- Security model: `docs/security-model.md`.
- Deployment guide: `docs/deployment-guide.md`.
- Evidence bundle generator: `scripts/create-submission-bundle.py`.

## Default Skill Coverage

- Storage: upload, download, list, share.
- Messaging: send, join group, create group.
- Wallet: balance, send, history.
- Program: query, call, deploy.
- A2A: card, discover, task, subscribe, cancel.
- Meta: skills, status, configure.

Local smoke evidence exists for wallet, storage, messaging, A2A, program, and
Basecamp package-manager install. Generate the current sanitized evidence view:

```bash
./scripts/create-submission-bundle.py
```

## Hosted-Testnet Evidence

| Operation | Tx Hash | Status |
| --- | --- | --- |
| `wallet.send` | `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0` | confirmed by transaction lookup and balance deltas |
| `program.deploy` | `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb` | confirmed by hosted-testnet RPC lookup |
| `program.call` | `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518` | confirmed by account data `Hola mundo!` |
| `agent.task` payment leg | `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494` | confirmed by transaction lookup and balance deltas |

The hosted-testnet wallet/runtime used LEZ tag `v0.1.2` / commit `cf3639d8`
because the current public LEZ `main` wallet did not match the deployed
testnet program IDs.

## Local Proof Highlights

- Storage upload/list/share/download completed and downloaded bytes matched the
  original input.
- Messaging send/create-group/join completed over Delivery topics.
- A2A task lifecycle completed locally over Delivery, including a latest
  discovery + payment proof where the client discovered the server's signed
  Agent Card and paid its advertised price.
- Paid A2A task payment and cancel/refund completed locally with LEZ tx hashes.
- Basecamp profile install smoke installed Delivery, Storage, Chat, LEZ, and
  Agent LGXs into `alice` and `bob` profiles with the real `lgpm` CLI.
- Three headless category agents generated signed Agent Cards, `meta.skills`,
  `meta.status`, private LEZ accounts, and Delivery startup evidence.

## Known Scope Boundaries

- The hosted-testnet A2A evidence proves the LEZ payment leg for a priced A2A
  task. The full two-agent Delivery transport proof is currently localnet
  headless evidence; final submission should record that run or rerun it on the
  final demo host.
- The three-agent deployment evidence is headless CLI evidence. On this laptop
  the post-capture `logoscore` daemons did not remain running, so Basecamp GUI
  owner-channel recording should be done on a larger or already-cached machine.
- `program.call` uses the current supported signed public call path. The
  generic arbitrary-program CLI/API should replace the helper bridge when LEZ
  exposes a stable interface for it.
- CU values are not exposed by the current wallet/RPC output. Keep them as
  `TBD` unless Logos provides explorer/sequencer metadata, logs, or an
  evaluator-approved benchmark mapping.

## Manual-Only Items Left

See `docs/manual-intervention-checklist.md`. In short:

- Basecamp GUI owner-channel recording.
- Recording of the already-proven headless two-agent Delivery/A2A flow.
- Three narrated illustrative use cases.
- Final narrated submission video.
- CU confirmation or accepted `TBD` policy from Logos.
- Official clean package build on stable hardware or CI.
