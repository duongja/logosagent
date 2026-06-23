# Final Demo Recording Guide

This guide is written as a practical narration script for the LP-0008 final
demo video. It explains what to show, what each command proves, and how to
describe the output in simple language.

The goal of the video is not only to show commands passing. The goal is to make
it clear that the project is a real Logos agent module with wallet, storage,
messaging, owner chat, and agent-to-agent coordination.

## Recording Rules

Do show:

- The repository and current commit.
- `RISC0_DEV_MODE=0` before proof-generating LEZ runs.
- Basecamp owner Chat sending JSON commands to the agent.
- Testnet transaction hashes already captured in the docs.
- Local proof scripts for Storage, Wallet, Messaging, A2A, and Program skills.
- The generated submission bundle and checksums.

Do not show:

- Private keys.
- Raw wallet storage files.
- Recovery phrases.
- Token files.
- Unredacted `.local` wallet internals.

If a terminal command prints a warning that a package is unsigned, explain that
these are locally built development LGX packages. The important check is that
they install into the expected Basecamp/Core module directories and contain the
expected Linux variant.

## Short Opening Script

Say:

> This is my LP-0008 Logos Agent Module submission. The project builds a Logos
> Core module called `logos_agent`. The agent has its own wallet identity, can
> use Logos Storage, can talk over Logos Chat and Delivery, and can coordinate
> with other agents using an A2A-compatible task flow. The owner controls the
> agent through Basecamp Chat, and spending limits protect the owner from
> unwanted token transfers.

Then say:

> I will show three kinds of evidence. First, repository and package readiness.
> Second, hosted LEZ testnet transaction evidence. Third, live local proof
> scripts for the parts that are best verified with local Logos Core modules,
> including Storage, Messaging, owner chat, and two-agent A2A.

## Terminal Setup

Run:

```bash
cd ~/Projects/logos/logos-agent
git pull origin main
git status --short --branch
git log --oneline -5
export RISC0_DEV_MODE=0
echo "RISC0_DEV_MODE=$RISC0_DEV_MODE"
```

Explain:

> I start from the submitted GitHub repository. `git status` should be clean, so
> the video matches the pushed code. `RISC0_DEV_MODE=0` is important because it
> means proof-generating LEZ runs are not using the RISC0 developer shortcut.

Expected meaning:

- `Already up to date` means your local copy matches GitHub.
- `## main...origin/main` with no changed files means the repo is clean.
- `RISC0_DEV_MODE=0` is the proof-mode safety check.

## Section 1: Preflight And Submission Bundle

Run:

```bash
./scripts/preflight-submission.sh
```

Explain:

> This is the repository preflight. It creates the three required agent
> configurations, checks important security defaults, validates CLI syntax,
> runs a deterministic LEZ helper check, and confirms that the module package
> exists.

How to explain the output:

- `Generating three LP-0008 agent configs` means the project can create the
  three prize-required agent roles:
  - Storage agent
  - Messaging agent
  - Blockchain agent
- `fail-closed spend policy` means the agent starts with safe spending limits.
  By default it does not spend freely.
- `AES-GCM storage` means uploaded files are encrypted before being stored.
- `Ed25519 A2A signing` means Agent Cards and task messages are signed so peer
  agents can verify who sent them.
- `agent_lez deterministic inspect smoke` means the LEZ helper can inspect a
  program binary and produce a deterministic program ID.
- `Package artifact` means the `logos_agent` LGX package exists.
- `Package is unsigned` warnings are expected for local development packages.
  They are not claiming production signing; they are proving packaging and
  install behavior.

Run:

```bash
./scripts/create-submission-bundle.py --out-dir .local/submission-bundle/final-recording
sed -n '1,220p' .local/submission-bundle/final-recording/SUBMISSION-INDEX.md
cat .local/submission-bundle/final-recording/artifact-checksums.json
```

Explain:

> This creates a sanitized submission bundle. It collects public docs,
> evidence summaries, and package checksums, but it avoids copying wallet state
> or local secrets.

How to explain the output:

- `ok: true` means the bundle step succeeded.
- `public_files` is the number of public docs and metadata copied into the
  bundle.
- `artifacts` is the number of package artifacts/checksums discovered.
- `Hosted-Testnet Tx Evidence` lists real LEZ testnet transaction hashes.
- `Local Evidence Summary` lists the local proof runs for Storage, Wallet,
  Messaging, A2A, Program, and Basecamp.
- `artifact-checksums.json` gives file size and SHA-256 hashes so reviewers can
  verify that the package files did not change.

## Section 2: Testnet Evidence Already Captured

Show:

```bash
sed -n '1,160p' docs/testnet-wallet-transfer-evidence-20260619.md
sed -n '1,180p' docs/testnet-program-evidence-20260619.md
sed -n '1,160p' docs/testnet-a2a-payment-evidence-20260619.md
```

Explain:

> These documents show the hosted LEZ testnet evidence. The hosted testnet is
> where we can prove real LEZ transactions with transaction hashes. Storage and
> Delivery are proven separately through local Logos Core/Basecamp runs because
> they are not exposed as the same hosted LEZ transaction network.

### Wallet Transfer Evidence

Important output:

- Network: hosted LEZ testnet.
- Endpoint: `https://testnet.lez.logos.co/`.
- `RISC0_DEV_MODE = 0`.
- Transaction hash:
  `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0`.
- Sender balance: `3648 -> 3647`.
- Recipient balance: `4000 -> 4001`.
- Both nonces advanced by one.

Say:

> This proves a real testnet token transfer. The sender balance went down by
> one, the recipient balance went up by one, and the transaction can be looked
> up again by hash. The nonce changes show that both accounts were updated by
> the chain.

### Program Deploy And Call Evidence

Important output:

- Deploy tx:
  `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb`.
- Program call tx:
  `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518`.
- Account data after call: `Hola mundo!`.

Say:

> This proves the agent's program skills are connected to real LEZ program
> operations. The program was deployed, then a signed call changed account
> state. The readable result `Hola mundo!` is the simple proof that the program
> call executed and modified state.

### A2A Payment Evidence

Important output:

- A2A task id: `task-testnet-paid-a2a-20260619T235140Z`.
- Skill id: `messaging.echo`.
- Declared price: `1 LEZ`.
- Payment tx:
  `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494`.
- Payer balance: `3647 -> 3646`.
- Recipient balance: `4001 -> 4002`.

Say:

> A2A itself is the agent-to-agent task protocol. This document proves the
> payment leg on hosted LEZ testnet: a client agent paid the advertised price
> for a task. The full task lifecycle is shown locally because the Delivery
> transport is module-based.

## Section 3: Basecamp Owner Chat

Show the doc first:

```bash
sed -n '1,180p' docs/basecamp-owner-chat-evidence-20260622.md
```

Then open Basecamp if you are recording the GUI portion. In Basecamp Chat,
paste one command at a time.

Commands:

```json
{"skill":"meta.status","params":{}}
```

Say:

> This asks the agent for its current status. It proves that the owner can send
> a skill call through Basecamp Chat and the agent can answer in the same
> conversation.

```json
{"skill":"agent.card","params":{}}
```

Say:

> This returns the agent's A2A Agent Card. The Agent Card is like the agent's
> public profile: it declares who the agent is, which skills it offers, and how
> other agents can contact it.

```json
{"skill":"wallet.balance","params":{}}
```

Say:

> This routes a wallet skill through the owner chat path. In this isolated GUI
> proof, a wallet error can be acceptable if the GUI agent is not funded. The
> important point is that the request reached the wallet skill and returned a
> controlled result instead of crashing.

```json
{"skill":"storage.list","params":{}}
```

Say:

> This asks the agent to list stored files. If the isolated owner-chat agent has
> no files, an empty list is still a valid result. It proves the Storage skill
> can be invoked from owner chat.

```json
{"skill":"messaging.send","params":{"recipient":"6ceca915db6fcc4c3869e08f480469cc14c0","message":"agent echo proof"}}
```

Say:

> This asks the agent to send a message back to the owner conversation. It is a
> simple echo proof that the Messaging skill can send through the Logos Chat
> path.

```json
{"skill":"wallet.send","params":{"recipient":"deadbeef","amount":"1"}}
```

Say:

> This is a safety test. The default spend policy is strict, so the agent should
> not immediately spend. Instead, it creates a pending owner approval. That is
> exactly what the prize asks for: below-threshold transactions can be
> autonomous, but above-threshold transactions require owner approval.

If you see an approval object:

```json
{
  "approval_id": "...",
  "skill": "wallet.send",
  "amount": "1",
  "status": "pending",
  "origin": "owner-chat"
}
```

Explain:

> The key field is `status: pending`. That means the agent refused to spend
> automatically and is waiting for the owner.

## Section 4: Storage Proof

Run as one-line commands. Do not split flags across lines.

```bash
export RUN=.local/video/storage-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-storage-smoke.sh --run-root "$RUN"
cat "$RUN/storage-list-uploaded.json"
cat "$RUN/share.json"
cmp "$RUN/input.txt" "$RUN/downloaded.txt" && echo "downloaded file matches original"
```

Explain:

> This is the personal file vault use case. The agent uploads a local file,
> encrypts it, records a content address, lists it, creates a share payload, and
> downloads it again. The final `cmp` proves the downloaded file is exactly the
> same as the original.

How to explain the main script output:

- `ok: true` means the storage smoke test passed.
- `address` is the content address for the stored encrypted file.
- `input` is the original file.
- `downloaded` is the file retrieved back from storage.
- `proofs.upload`, `proofs.share`, and `proofs.download` are JSON evidence
  files created by the script.

How to explain `storage-list-uploaded.json`:

- `files` is the agent's stored-file index.
- `address` is the retrievable content address.
- `label` is the human-readable name.
- `status: uploaded` means the agent completed the upload.
- `encryption.alg: aes-256-gcm` means the local file was encrypted before
  storage.
- `plain_sha256` is the hash of the original file.
- `cipher_sha256` is the hash of the encrypted file.

How to explain `share.json`:

- `type: logos.storage.share.v1` means this is a storage-share payload.
- `key_wrap` means the file key is wrapped for a recipient. The raw file key is
  not exposed directly.
- `recipient_public_key_hex` identifies the recipient encryption key.
- `sender_ephemeral_public_key_hex`, `wrap_nonce_hex`, `wrap_tag_hex`, and
  `wrapped_key_hex` are cryptographic fields needed for secure sharing.

Say:

> The share object is what one agent or user could send to another identity so
> they can decrypt the file. The file itself remains encrypted.

How to explain `cmp`:

> `cmp` compares the original and downloaded files byte by byte. If it prints
> `downloaded file matches original`, the upload and download round trip is
> proven.

## Section 5: Wallet Proof

Run:

```bash
export RUN=.local/video/wallet-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-wallet-smoke.sh --run-root "$RUN" --localnet-timeout 240
cat "$RUN/wallet-send-approval-required.json"
cat "$RUN/wallet-send.json"
cat "$RUN/wallet-history.json"
```

Explain:

> This proves the agent wallet flow on a local LEZ sequencer. First the script
> tests the safety gate by making a transfer that requires approval. Then it
> tests an allowed transfer and records the transaction in wallet history.

How to explain the main script output:

- `ok: true` means the wallet smoke test passed.
- `from` is the funded sender account.
- `to` is the recipient account.
- `amount` is the transfer amount.
- `topup.status: success` means the local faucet funded the sender for the
  local proof.
- `tx_hash` is the localnet transaction hash.
- `balance_before` and `balance_after` can look unchanged if the faucet/top-up
  and transfer happen in the same smoke flow. The stronger evidence is the
  transaction hash plus wallet history.

How to explain `wallet-send-approval-required.json`:

- `requires_approval: true` means the spend policy blocked automatic spending.
- `policy.allowed: false` means the agent did not execute the transaction.
- `approval.status: pending` means the owner must approve.
- `per_transaction_limit: 0` means the default policy is very strict.

Say:

> This is the spend-threshold requirement. The agent can propose a transfer,
> but when the amount is above policy it must wait for the owner.

How to explain `wallet-send.json`:

- `ok: true` means the allowed transfer path succeeded.
- `transaction.result.success: true` means the wallet call succeeded.
- `tx_hash` is the transaction proof.
- `spending_controlled: true` means the transfer went through the policy engine.

How to explain `wallet-history.json`:

- `transactions` is the durable local history.
- It should include the transfer with the same amount, recipient, and tx hash.

## Section 6: Messaging Proof

Run:

```bash
export RUN=.local/video/messaging-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-messaging-smoke.sh --run-root "$RUN" --message-timeout 90 --daemon-timeout 45
cat "$RUN/messaging-create-group.json"
cat "$RUN/messaging-join.json"
cat "$RUN/messaging-send.json"
tail -n 5 "$RUN/receiver-events.ndjson"
```

Explain:

> This proves the agent can use Logos Delivery as the transport for group-style
> messaging. The script starts an agent and a raw Delivery receiver. The agent
> creates a topic, joins it, sends a message, and the receiver records the
> delivered event.

How to explain `messaging-create-group.json`:

- `ok: true` means group/topic creation passed.
- `group_id` is the Delivery topic.
- `members` are the intended participants.
- `transport: delivery_topic` means the group is represented by a Delivery
  topic because Chat group APIs are not exposed yet.

How to explain `messaging-join.json`:

- `ok: true` means the agent joined/subscribed to the topic.
- The note explains why Delivery topics are used for group transport.

How to explain `messaging-send.json`:

- `ok: true` means the send request was accepted.
- `request_id` identifies the send operation.
- `topic` is where the message was sent.

How to explain `receiver-events.ndjson`:

- `event: messageReceived` is the proof that another receiver saw the message.
- `arg1` is the topic.
- `arg2` is the message payload.

Say:

> This is not just a local function call. A separate receiver observed a
> Delivery event, so the messaging transport path is working.

## Section 7: Paid A2A Proof

Run:

```bash
export RUN=.local/video/a2a-paid-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-a2a-paid-smoke.sh --run-root "$RUN" --localnet-timeout 240
cat "$RUN/a2a-summary.json"
cat "$RUN/a2a/client-discover-final.json"
cat "$RUN/a2a/client-task-submit.json"
```

Explain:

> This is the paid skill marketplace use case. Two agents start independently.
> The server agent publishes a signed Agent Card with its skills and price. The
> client discovers that card, pays the declared LEZ price, submits a task, and
> both agents reach a completed task state.

How to explain the main script output:

- `ok: true` means the paid A2A proof passed.
- `from` is the client/payer account.
- `to` is the server/payment recipient account.
- `payment_tx_hash` is the local LEZ payment transaction.
- `a2a.task_id` is the A2A task identifier.
- `paid: true` means payment was attached to the task.
- `canceled: false` means this run completed normally instead of testing
  cancellation.

How to explain `a2a-summary.json`:

- `client_address` and `server_address` are the two agents.
- `task_id` is the shared task record.
- `proofs.client_discover_final` points to the discovered Agent Card.
- `proofs.client_task_submit` points to the submitted task.
- `proofs.client_completed_status` and `proofs.server_completed_status` prove
  both sides reached completion.

How to explain `client-discover-final.json`:

- `agents` is the list of discovered agents.
- `signature_alg: ed25519` means the Agent Card is signed.
- `logos.payment.price: 1` means the server advertises a 1 LEZ price.
- `logos.payment.recipient` is the payment destination.
- `skills` lists what the server offers.
- `preferredTransport: logos-messaging` means A2A is bound to Logos Messaging
  / Delivery instead of plain HTTP.

Say:

> The Agent Card is how agents discover services. It is signed so the client
> can trust that the skill list and price belong to that agent.

How to explain `client-task-submit.json`:

- `task.state: TASK_STATE_SUBMITTED` means the task request was created and
  sent.
- `payment.ok: true` means the client paid before or during task acceptance.
- `payment.transfer.transaction.result.tx_hash` is the payment proof.
- `transport.ok: true` means the task envelope was sent over the task topic.

Say:

> This combines three prize requirements: A2A-compatible discovery, A2A task
> lifecycle, and LEZ payment for the task price.

## Section 8: Program Proof

Run:

```bash
export RUN=.local/video/program-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-program-smoke.sh --run-root "$RUN" --localnet-timeout 240 --daemon-timeout 45
cat "$RUN/program-query-health.json"
cat "$RUN/program-call-wallet-health.json"
cat "$RUN/program-deploy.json"
```

Explain:

> This proves the program skill category. The agent can query LEZ state or
> health, call through the supported wallet/helper bridge, and deploy a program
> binary.

How to explain the main script output:

- `ok: true` means the program proof passed.
- `program_binary` is the binary being deployed.
- `program_id` is the deterministic identifier for that binary.
- `program_id_source: sha256-fallback` means the program ID came from hashing
  the binary in the helper path.

How to explain `program-query-health.json`:

- `ok: true` means the query path succeeded.
- `mode: wallet-cli` means the agent helper used the LEZ wallet CLI.
- `stdout: All looks good!` means the wallet health check passed.

How to explain `program-call-wallet-health.json`:

- This is a supported call bridge into the wallet CLI.
- It proves the agent can invoke a LEZ call-like operation through the program
  adapter without crashing the module.

How to explain `program-deploy.json`:

- `ok: true` means deploy completed.
- `binary_path` is the compiled program binary.
- `program_id` is the resulting program identifier.

Say:

> Hosted testnet deploy and call transaction hashes are shown in the earlier
> docs. This local run proves the agent skill interface can drive the program
> adapter end to end.

## Section 9: Three Required Agent Deployments

Show:

```bash
sed -n '1,180p' docs/three-agent-headless-evidence-20260620.md
```

Explain:

> The prize asks for three separate agents on testnet: one per major default
> skill category. This evidence shows the Storage agent, Messaging agent, and
> Blockchain agent each got its own config, identity, LEZ account, signed Agent
> Card, and module startup evidence.

Important output:

- Storage agent LEZ account.
- Messaging agent LEZ account.
- Blockchain agent LEZ account.
- `Agent Card signed: true`.
- `Delivery started: true`.
- `Chat started: true`.

Say:

> These are separate agent identities, not just one process pretending to be
> three categories.

## Section 10: Clean LGX Build Status

Show the GitHub Actions page for the latest `clean-lgx` run.

Say if it passes:

> This is the clean official LGX build from GitHub Actions. It proves a clean
> machine can build the package from the public repository.

Say if it is still running:

> The clean LGX build is running on GitHub Actions. Earlier runs showed the
> hosted runner was the bottleneck, first due to memory and then due to runtime.
> The current workflow adds swap, heartbeat logs, and a longer timeout. The
> repository also contains local package checksums and Basecamp install proof.

Say if it fails by timeout:

> This is a CI resource limitation rather than a source compile failure. The
> project has already produced local LGX artifacts and install evidence. For
> final review, a larger runner or already-cached build host should be used to
> complete the official clean LGX proof.

## Section 11: CU / Compute Unit Note

Show:

```bash
sed -n '1,120p' docs/cu-report.md
```

Say:

> The prize asks for compute unit costs. The LEZ wallet and RPC output we used
> expose transaction hashes and account state, but they do not currently expose
> CU directly. We document this honestly as `TBD`, with transaction hashes and
> the plan to fill CU from an explorer, sequencer metadata, logs, or an
> evaluator-approved benchmark mapping.

Important:

> Do not claim exact CU numbers unless Logos exposes them or the evaluators
> confirm an accepted benchmark mapping.

## Section 12: Closing Summary

Say:

> In this demo, I showed that the module is more than a chatbot wrapper. It is
> a Logos Core module with a wallet identity, storage skills, messaging skills,
> program skills, owner chat through Basecamp, and A2A-compatible coordination.
> The owner can interact with the agent over Logos Chat, spending is guarded by
> approval policy, files are encrypted before storage, agents can discover each
> other through signed Agent Cards, and paid A2A tasks include LEZ payment
> evidence.

Then say:

> The remaining limitations are documented: generic arbitrary LEZ program calls
> depend on the stable wallet/API surface, CU reporting depends on where Logos
> exposes CU, and the clean LGX CI build may need a larger runner because the
> full dependency build is very heavy.

## Common Mistakes During Recording

Do not split long option names across lines. This fails:

```bash
./scripts/agent-wallet-smoke.sh --run-root "$RUN" --localnet-
timeout 240
```

Use this instead:

```bash
./scripts/agent-wallet-smoke.sh --run-root "$RUN" --localnet-timeout 240
```

The same applies to:

```bash
--message-timeout
--localnet-timeout
--daemon-timeout
```

If you accidentally run the wrong script, stop and explain briefly:

> I accidentally ran the messaging smoke while preparing for the A2A proof. I
> am now running the correct A2A paid smoke script.

Then continue. Small terminal mistakes are acceptable if the final proof output
is clear.

## Quick Checklist

Before ending the recording, confirm you showed:

- Clean repo state.
- `RISC0_DEV_MODE=0`.
- Testnet wallet transfer tx hash.
- Testnet program deploy and call tx hashes.
- Testnet A2A payment tx hash.
- Basecamp owner-to-agent Chat.
- Storage upload/list/share/download and file match.
- Wallet approval gate and transfer history.
- Messaging Delivery receiver event.
- Paid A2A Agent Card discovery, payment, and task submit.
- Program query/call/deploy.
- Submission bundle index and checksums.
- CU-report status.
- Clean LGX build status or current CI limitation.

