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

Current hosted-testnet evidence was refreshed on 2026-07-01 after Logos
announced the final LEZ `v0.2.0` tag. The run used LEZ commit
`a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a` with `RISC0_DEV_MODE=0`.
See `docs/testnet-v020-final-evidence-20260701.md`.

| Operation | Tx Hash | Status |
| --- | --- | --- |
| `wallet.send` | `7bdeea835624591f222da7ece3d6a58f3663d5e943ee28f57d0ab35c37824de1` | confirmed by transaction lookup and balance deltas: sender `10000 -> 9999`, recipient `20000 -> 20001` |
| `agent.task` payment leg | `3d2d8a20b07c2df742078fbefdc18c6eb2e483e3ef9468681686e67f4d213894` | confirmed by transaction lookup and balance deltas: payer `9999 -> 9998`, recipient `20001 -> 20002` |
| `program.deploy` | `e9c0d01039e9ccb1b4c3ab915b263a6b4a6c5b8244737bb063b33282093a7d02` | `hello_world_with_authorization.bin` deployment confirmed by hosted-testnet RPC lookup |
| `program.call` | `ee2c922038fa225bb13d9dba9b8a9f63d48ccf23b8c1c6bd4ef1cb534f261e9f` | stable wallet-facade call to `authenticated_transfer` confirmed by transaction lookup and account nonce `1` |

The June 26 `v0.2.0-rc5` hashes and June 19 pre-v0.2 hashes are retained in
separate evidence docs as historical context only.

## Narrated Demo Videos

| Video | Focus | Link |
| --- | --- | --- |
| Video 1 | Repository readiness, package/evidence bundle, hosted-testnet transaction evidence, and submission overview | https://www.youtube.com/watch?v=fYlokf7NIfI |
| Video 2 | Basecamp owner-to-agent Chat flow and owner-channel skill calls | https://www.youtube.com/watch?v=nS8928doTkE |
| Video 3 | Live skill proofs: Storage, wallet spending controls and transfer history, Messaging/Delivery, paid A2A, and program operations | https://www.youtube.com/watch?v=hxRQejaBhxo |

These videos demonstrate the implementation and end-to-end flows. They were
recorded before the final hosted-testnet evidence refresh, so
`docs/testnet-v020-final-evidence-20260701.md` is the source of truth for the
current LEZ `v0.2.0` tx hashes.

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
- Final hosted `program.call` evidence uses the stable wallet facade for the
  builtin `authenticated_transfer` program. A heavier arbitrary-program example
  runner can still be rerun on a larger host if reviewers require that exact
  custom-program path.
- CU values are documented in `docs/cu-report.md` as `TBD` because the previous
  wallet/RPC output did not expose CU fields. The Logos team advised applying
  anyway while they clarify CU expectations, and suggested the
  `fryorcraken/lez-signature-bench` style of real `RISC0_DEV_MODE=0`
  cycle/prove-time measurement as the follow-up method.

## Manual-Only Items Left

See `docs/manual-intervention-checklist.md`. In short:

- Official clean package build on stable hardware or CI.
