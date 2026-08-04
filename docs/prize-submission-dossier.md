# LP-0008 Prize Submission Dossier

> **Current resubmission map:** the authoritative integrated public proof is
> `evidence/current/testnet-v02/`. Older hosted LEZ hashes retained below are
> standalone historical evidence, not agent-on-testnet proof.

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

The current integrated proof was captured on 2026-08-03 UTC with two isolated
agents, Delivery and Storage on `logos.test`, LEZ Core `0.2.0`, and
`logos_agent` `0.2.0`. It is independently validated from
`evidence/current/testnet-v02/summary.json`.

| Operation | Tx Hash | Status |
| --- | --- | --- |
| `agent.task` payment through `logos_agent` | `ee5b41972e315f0bca0d2c7745048dfe6e875418ccef1b132160f35995d9d9ea` | direct `getTransaction` result; payer `7369 -> 7368`; task `task_c766adf8fb544dafa9d4eed2fe3faeb2` reached `TASK_STATE_COMPLETED` |
| Storage upload/download | N/A | content address `zDvZRwzmAaw9AK9WMFPcWzhNKwHW4EdtuP62k5troeudkbCNRNvN`; matching plaintext SHA-256 `2e36f5d965e6b5eb6fae2fcfcb41976d274922ad0cbd872e83e1ea1df75d0f35` |
| Delivery discovery/task/status | N/A | signed server Agent Card discovered by the client; task and terminal status crossed public `logos.test` topics |

The July standalone LEZ `v0.2.0`, June `v0.2.0-rc5`, and pre-v0.2 hashes are
retained in separate evidence docs as historical context only.

## Narrated Demo Videos

| Video | Focus | Link |
| --- | --- | --- |
| Video 1 | Repository readiness, package/evidence bundle, hosted-testnet transaction evidence, and submission overview | https://www.youtube.com/watch?v=fYlokf7NIfI |
| Video 2 | Basecamp owner-to-agent Chat flow and owner-channel skill calls | https://www.youtube.com/watch?v=nS8928doTkE |
| Video 3 | Live skill proofs: Storage, wallet spending controls and transfer history, Messaging/Delivery, paid A2A, and program operations | https://www.youtube.com/watch?v=hxRQejaBhxo |

These videos demonstrate the earlier implementation and local end-to-end flows.
They predate the integrated two-agent public proof, so
`evidence/current/testnet-v02/` is the source of truth for current Testnet v0.2
agent activity and transaction identifiers.

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

- The current hosted-testnet evidence proves signed Agent Card discovery, a
  paid A2A task and terminal status over Delivery, Storage round-trip, and LEZ
  confirmation through two running `logos_agent` modules.
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

- Record and publish the replacement continuous public-testnet demo.
- Push the workflows and link the first public passing local E2E Actions run.
