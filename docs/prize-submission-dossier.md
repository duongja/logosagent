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
- Narrated demo videos: `docs/demo-video-links.md`.

## Default Skill Coverage

- Storage: upload, download, list, share.
- Messaging: send, join group, create group.
- Wallet: balance, send, history.
- Program: query, call, deploy.
- A2A: card, discover, task, subscribe, cancel.
- Meta: skills, status, configure.

Local smoke evidence exists for wallet, storage, messaging, A2A, program, and
Basecamp package-manager install. A 2026-06-22 refresh also proves the
Basecamp owner Chat path and all default localnet skill categories. Generate
the current sanitized evidence view:

```bash
./scripts/create-submission-bundle.py
```

## Hosted-Testnet Evidence

Current hosted-testnet evidence was refreshed on 2026-06-26 after Logos
reported that the v0.2 testnet endpoint was back online. The run used LEZ
`v0.2.0-rc5` / commit `27360cb7d6ccb2bfbcca7d171bab8a3938490264` with
`RISC0_DEV_MODE=0`. See
`docs/testnet-v020-live-evidence-20260626.md`.

| Operation | Tx Hash | Status |
| --- | --- | --- |
| `wallet.send` | `3f140331aee32dba313d0eb73e47b1aad7e6f1dd5dfc8721460c16ac8a011c86` | confirmed by transaction lookup and balance deltas: sender `10000 -> 9999`, recipient `20000 -> 20001` |
| `program.deploy` | `1db8975f24b5f27a4c271ea17f7db33e9d654964af8ab980ee78d0e351537f03` | `data_changer.bin` deployment confirmed by hosted-testnet RPC lookup |
| `program.call` | `e752295333411623035c660016e8b1fb8deffdb4b7fc5c87fa0007eb004a8f30` | confirmed by account data `LP0008-v020` and nonce `1` |
| `agent.task` payment leg | `2111c69569e0804e28ca4210e9850a7db4171d6d7f3787d10c0f426629e461b4` | confirmed by transaction lookup and balance deltas: payer `9999 -> 9998`, recipient `20001 -> 20002` |

The older June 19 hosted-testnet tx hashes are retained in separate evidence
docs as historical pre-v0.2-redeploy context only.

## Narrated Demo Videos

| Video | Focus | Link |
| --- | --- | --- |
| Video 1 | Repository readiness, package/evidence bundle, hosted-testnet transaction evidence, and submission overview | https://www.youtube.com/watch?v=fYlokf7NIfI |
| Video 2 | Basecamp owner-to-agent Chat flow and owner-channel skill calls | https://www.youtube.com/watch?v=nS8928doTkE |
| Video 3 | Live skill proofs: Storage, wallet spending controls and transfer history, Messaging/Delivery, paid A2A, and program operations | https://www.youtube.com/watch?v=hxRQejaBhxo |

## Local Proof Highlights

- Storage upload/list/share/download completed and downloaded bytes matched the
  original input.
- Messaging send/create-group/join completed over Delivery topics.
- A2A task lifecycle completed locally over Delivery, including a latest
  discovery + payment proof where the client discovered the server's signed
  Agent Card and paid its advertised price.
- Basecamp owner Chat accepted JSON skill calls and returned agent replies in
  the same private conversation; above-threshold `wallet.send` created pending
  owner approval `appr_29deccb3d30d7ab1842b43b8f42f1285`.
- Paid A2A task payment and cancel/refund completed locally with LEZ tx hashes.
- Basecamp profile install smoke installed Delivery, Storage, Chat, LEZ, and
  Agent LGXs into `alice` and `bob` profiles with the real `lgpm` CLI.
- Three headless category agents generated signed Agent Cards, `meta.skills`,
  `meta.status`, private LEZ accounts, and Delivery startup evidence.

## Known Scope Boundaries

- The hosted-testnet A2A evidence proves the LEZ payment leg for a priced A2A
  task. The full two-agent Delivery transport proof is localnet headless
  evidence and should be shown in the final narrated recording.
- The three-agent deployment evidence is headless CLI evidence. Basecamp
  owner-chat evidence is now captured separately with a headless agent and the
  Basecamp owner app.
- `program.call` uses the current supported signed public call path. The
  generic arbitrary-program CLI/API should replace the helper bridge when LEZ
  exposes a stable interface for it.
- CU values are documented in `docs/cu-report.md` as `TBD` because the previous
  wallet/RPC output did not expose CU fields. The Logos team advised applying
  anyway while they clarify CU expectations, and suggested the
  `fryorcraken/lez-signature-bench` style of real `RISC0_DEV_MODE=0`
  cycle/prove-time measurement as the follow-up method.

## Manual-Only Items Left

See `docs/manual-intervention-checklist.md`. In short:

- Official clean package build on stable hardware or CI.
