# Final Demo Recording Guide

This is the compact recording script for the LP-0008 submission. It is split
into three videos. Each video section contains the commands to run, what to say,
and how to explain the important output in simple terms.

Do not show private keys, wallet storage files, recovery phrases, token files,
or raw `.local` wallet internals. If a command prints `Package is unsigned`,
explain that these are locally built development LGX packages; the proof is
that they package, install, and load in the expected module locations.

If you make a small terminal mistake, do not restart the whole recording. Say
what happened, rerun the correct command, and continue.

## Video 1: Repository, Package, Testnet Evidence

### Goal

Say:

> In this first video I am showing repository readiness, package evidence,
> hosted LEZ testnet transaction evidence, three-agent deployment evidence, and
> the current clean LGX build status.

### 1. Start From The Submitted Repo

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

- `git pull origin main` shows the local copy is up to date with GitHub.
- `git status --short --branch` should show a clean `main` branch. That means
  the recording matches the submitted code.
- `git log --oneline -5` shows the latest commits, including the demo guide and
  CI workflow commits.
- `RISC0_DEV_MODE=0` matters because LEZ proof-generating runs should not use
  the RISC0 developer shortcut.

### 2. Run Submission Preflight

Run:

```bash
./scripts/preflight-submission.sh
```

Explain:

> This is the repository preflight. It checks that the project can generate the
> required agent configs, validates important security defaults, checks CLI
> syntax, verifies a deterministic LEZ helper path, and confirms the agent LGX
> package exists.

Explain the important output:

- `Generating three LP-0008 agent configs`: the repo can create the required
  Storage, Messaging, and Blockchain category agents.
- `fail-closed spend policy`: the agent starts safely. It does not spend tokens
  freely by default.
- `AES-GCM storage`: files are encrypted before being stored.
- `Ed25519 A2A signing`: Agent Cards and task messages can be signed and
  verified.
- `agent_lez deterministic inspect smoke`: the helper can inspect a program
  binary and produce a deterministic program ID.
- `Package artifact`: the `logos_agent` LGX package exists.
- `Package is unsigned`: expected for local development packages.

### 3. Package And Install Basecamp Modules

Run:

```bash
./scripts/package-live-modules-lgx.sh
./scripts/basecamp-profile-install-smoke.sh
```

Explain:

> This packages the live module set and installs it into Basecamp-style profile
> module directories. This proves the package-manager/profile-install layer
> before we show the GUI owner chat in Video 2.

Explain the important output:

- `Created package`: an LGX package was created for a module.
- `Added variant 'linux-amd64-dev'`: the package contains the Linux build
  variant.
- `installed_modules`: the profile contains the expected modules.
- `missing: []`: no required module is missing.
- `dependency_errors: []`: package dependencies resolved.

### 4. Create The Submission Bundle

Run:

```bash
./scripts/create-submission-bundle.py --out-dir .local/submission-bundle/final-recording
sed -n '1,220p' .local/submission-bundle/final-recording/SUBMISSION-INDEX.md
cat .local/submission-bundle/final-recording/artifact-checksums.json
```

Explain:

> This creates a sanitized review bundle. It includes public docs, evidence
> summaries, package checksums, and transaction references. It intentionally
> avoids copying wallet secrets or raw runtime state.

Explain the important output:

- `ok: true`: the bundle step succeeded.
- `public_files`: number of public docs and metadata files copied.
- `Hosted-Testnet Tx Evidence`: the real LEZ testnet transaction hashes.
- `Local Evidence Summary`: local proof runs for Storage, Wallet, Messaging,
  A2A, Program, and Basecamp.
- `artifact-checksums.json`: file sizes and SHA-256 hashes for reproducibility.

### 5. Show Hosted LEZ Testnet Evidence

Run:

```bash
sed -n '1,160p' docs/testnet-wallet-transfer-evidence-20260619.md
sed -n '1,180p' docs/testnet-program-evidence-20260619.md
sed -n '1,160p' docs/testnet-a2a-payment-evidence-20260619.md
```

Explain:

> These documents prove the hosted LEZ testnet parts. LEZ wallet transfers,
> program deployment, program calls, and the A2A payment leg all have real
> hosted-testnet transaction hashes. Storage and Delivery are proven separately
> in local Logos Core/Basecamp because they are module-level systems, not the
> same hosted LEZ transaction endpoint.

Call out these values:

- `wallet.send` hosted testnet tx:
  `c2c0ef4f32afe5ebc971161f542917157859789b8c1e3e2e78a583a61b9b3da0`
- `program.deploy` hosted testnet tx:
  `c766019cf9e0161e174cea15fd5fe6232a94213b61a66f7ad3eb620e489bdcfb`
- `program.call` hosted testnet tx:
  `4feba206274c89b7cc6372e48f297d754b03d1746df75a8cdc5ff11f2653f518`
- Paid A2A payment-leg hosted testnet tx:
  `cd6bc3d08782f8ba5d2e3b4dc89cdf93288268092c6347930dded76deb156494`

Explain wallet evidence:

> For the wallet transfer, the sender balance went down by 1, the recipient
> balance went up by 1, and the transaction can be looked up again by hash.
> That proves a real hosted testnet transfer.

Explain program evidence:

> The program evidence shows a deploy transaction and a signed call transaction.
> The called account data becomes `Hola mundo!`, which is the simple readable
> proof that the deployed program executed and changed account state.

Explain A2A payment evidence:

> The A2A payment document proves the payment leg of a paid agent task. The
> task advertised a 1 LEZ price, the payer balance went down by 1, and the
> recipient balance went up by 1.

### 6. Show Three-Agent Deployment Evidence

Run:

```bash
sed -n '1,180p' docs/three-agent-headless-evidence-20260620.md
```

Explain:

> LP-0008 asks for three separate agents, one per default skill category. This
> evidence shows a Storage agent, Messaging agent, and Blockchain agent. Each
> has its own config, LEZ account, signed Agent Card, Delivery startup, and
> Chat startup.

Explain the important output:

- Three different agent rows means three separate agent identities.
- `Agent Card signed: true` means each agent can publish verifiable A2A
  metadata.
- `Delivery started: true` means the A2A/group transport started.
- `Chat started: true` means the owner-chat path started.

### 7. Show CU Status

Run:

```bash
sed -n '1,120p' docs/cu-report.md
```

Explain:

> The prize asks for compute unit costs. The LEZ wallet and RPC output we used
> expose transaction hashes and account state, but they do not expose CU
> directly. The report keeps CU as `TBD` until Logos exposes it through an
> explorer, sequencer metadata, logs, or an evaluator-approved benchmark
> mapping.

Important:

> Do not claim exact CU numbers unless Logos exposes them or the evaluators
> confirm an accepted benchmark mapping.

### 8. Show Clean LGX Build Status

Open:

```text
https://github.com/duongja/logosagent/actions
```

Click the latest `clean-lgx` run.

If it is still running, say:

> The official clean LGX build is running on GitHub Actions. The full Nix build
> is heavy, so the workflow includes swap, heartbeat logs, and a longer
> timeout. Local package artifacts and Basecamp install evidence are already
> captured.

If it passes, say:

> This proves a clean GitHub runner can build the official LGX package from the
> public repository.

If it fails by timeout or runner resource limit, say:

> This is a CI resource limitation, not a source compile error. The repository
> includes reproducible steps, package checksums, and local install evidence.
> A larger runner or already-cached build host should complete this clean LGX
> proof.

### Video 1 Closing

Say:

> This first video covered the public repo state, package evidence, hosted LEZ
> testnet transactions, three required agent deployments, CU reporting status,
> and clean LGX build status.

## Video 2: Basecamp Owner-To-Agent Chat

### Goal

Say:

> In this second video I am showing the owner-facing requirement. The owner can
> control the agent from Basecamp Chat without a custom HTTP server or exposed
> API.

### 1. Prepare And Show Owner-Channel Evidence

Run:

```bash
cd ~/Projects/logos/logos-agent
git status --short --branch
./scripts/package-live-modules-lgx.sh
./scripts/basecamp-owner-channel.sh --capture-only
./scripts/basecamp-profile-install-smoke.sh
sed -n '1,180p' docs/basecamp-owner-chat-evidence-20260622.md
```

Explain:

> These commands package the module set, capture the Basecamp owner-channel
> module configuration, install the modules into Basecamp-style profiles, and
> show the documented owner Chat evidence.

Explain the important output:

- `captured modules`: the owner-channel helper found the module LGXs.
- `Basecamp owner-channel module set captured`: the Basecamp module set is
  ready.
- `installed_modules`: the profile has Delivery, Storage, Chat, LEZ, and the
  Agent module.
- The evidence doc lists the JSON skill calls already proven through Basecamp
  Chat.

### 2. Open Basecamp And Send Owner Commands

In Basecamp Chat, paste each JSON command one at a time.

#### Status

Send:

```json
{"skill":"meta.status","params":{}}
```

Say:

> This asks the agent for its current status. A response proves that the owner
> can send a skill call through Basecamp Chat and receive a reply from the
> agent in the same conversation.

Explain likely output:

- `ok: true` means the skill call succeeded.
- `balance`, `storage`, `active_tasks`, or similar status fields describe what
  the agent currently knows.
- The exact values can differ between runs; the important proof is that the
  agent replied through Chat.

#### Agent Card

Send:

```json
{"skill":"agent.card","params":{}}
```

Say:

> This returns the agent's A2A Agent Card. The Agent Card is like the agent's
> public service profile. It declares identity, skills, schemas, transport
> information, and payment details for other agents.

Explain likely output:

- `skills`: what the agent can do.
- `logos.agent_address`: the Logos agent address.
- `signature` and `signature_alg`: proof the card is signed.
- `preferredTransport`: the transport binding, here Logos Messaging/Delivery.

#### Wallet Balance

Send:

```json
{"skill":"wallet.balance","params":{}}
```

Say:

> This routes a wallet skill through the owner Chat path. If this isolated GUI
> agent is not funded, a controlled wallet error can be acceptable. The point
> is that the owner Chat request reached the wallet skill and returned a
> controlled result instead of crashing the module.

#### Storage List

Send:

```json
{"skill":"storage.list","params":{}}
```

Say:

> This asks the agent to list stored files. If this owner-chat agent has no
> files yet, an empty list is still valid. It proves Storage skills are
> invokable through owner Chat.

Explain likely output:

- `ok: true` means the skill ran.
- `files: []` simply means this isolated agent has no stored files yet.

#### Messaging Echo

Send:

```json
{"skill":"messaging.send","params":{"recipient":"6ceca915db6fcc4c3869e08f480469cc14c0","message":"agent echo proof"}}
```

Say:

> This asks the agent to send a message back to the owner conversation. It is a
> simple echo proof that the Messaging skill can send through the Logos Chat
> path.

Explain likely output:

- `ok: true` means the send was accepted.
- If you see the echo in the same conversation, that proves the owner app
  received the agent's reply.

#### Spending Approval

Send:

```json
{"skill":"wallet.send","params":{"recipient":"deadbeef","amount":"1"}}
```

Say:

> This is the spending safety test. The default policy is strict, so the agent
> should not spend immediately. It should create a pending approval and wait
> for the owner.

Explain likely output:

- `approval_id`: the durable approval request ID.
- `skill: wallet.send`: the blocked skill.
- `amount: 1`: the proposed spend.
- `status: pending`: the agent did not spend automatically.
- `origin: owner-chat`: the request came from Basecamp Chat.

Say:

> The key field is `status: pending`. That means the agent refused to spend on
> its own and is waiting for owner approval.

### Video 2 Closing

Say:

> This second video proves the owner channel. The owner sends JSON skill calls
> in Basecamp Chat, the agent receives them through the Logos Chat module,
> replies in the same conversation, and above-threshold spending stays pending
> for owner approval.

## Video 3: Live Skill Proofs

### Goal

Say:

> In this third video I am showing the live skill proofs: Storage, Wallet,
> Messaging, paid A2A, and Program operations. These run against local Logos
> Core/localnet setups because they exercise module behavior that is not all
> available through the hosted LEZ transaction endpoint.

Start with:

```bash
cd ~/Projects/logos/logos-agent
git status --short --branch
export RISC0_DEV_MODE=0
echo "RISC0_DEV_MODE=$RISC0_DEV_MODE"
```

Explain:

> I am still on the submitted code. `RISC0_DEV_MODE=0` is shown again because
> this video includes proof-generating LEZ localnet runs.

### 1. Storage: Personal File Vault

Run:

```bash
export RUN=.local/video/storage-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-storage-smoke.sh --run-root "$RUN"
cat "$RUN/storage-list-uploaded.json"
cat "$RUN/share.json"
cmp "$RUN/input.txt" "$RUN/downloaded.txt" && echo "downloaded file matches original"
```

Say:

> This is the personal file vault use case. The agent encrypts and uploads a
> file, records a content address, lists it, creates a share payload, downloads
> it again, and proves the downloaded file matches the original.

Explain the script output:

- `ok: true`: the storage proof passed.
- `address`: the content address for the stored encrypted file.
- `input`: the original file.
- `downloaded`: the retrieved file.
- `proofs`: JSON evidence files saved by the script.

Explain `storage-list-uploaded.json`:

- `files`: the agent's stored-file index.
- `label`: human-readable file name.
- `status: uploaded`: upload completed.
- `encryption.alg: aes-256-gcm`: local encryption was used before storage.
- `plain_sha256`: hash of the original file.
- `cipher_sha256`: hash of the encrypted file.

Explain `share.json`:

- `type: logos.storage.share.v1`: this is a storage-share payload.
- `key_wrap`: the file key is wrapped for a recipient; the raw file key is not
  exposed.
- `recipient_public_key_hex`: recipient encryption key.
- `wrapped_key_hex`, `wrap_nonce_hex`, and `wrap_tag_hex`: cryptographic fields
  needed for secure sharing.

Explain `cmp`:

> `cmp` compares the original and downloaded files byte by byte. If it prints
> `downloaded file matches original`, the storage round trip is proven.

### 2. Wallet: Spending Controls And Transfer History

Run:

```bash
export RUN=.local/video/wallet-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-wallet-smoke.sh --run-root "$RUN" --localnet-timeout 240
cat "$RUN/wallet-send-approval-required.json"
cat "$RUN/wallet-send.json"
cat "$RUN/wallet-history.json"
```

Say:

> This proves the wallet and spending-policy path. First, the agent creates a
> pending approval for a blocked spend. Then it submits an allowed transfer and
> records it in wallet history.

Explain the script output:

- `ok: true`: the wallet proof passed.
- `from`: funded sender account.
- `to`: recipient account.
- `amount`: transfer amount.
- `topup.status: success`: the local faucet funded the sender for this proof.
- `tx_hash`: localnet transaction hash.
- `balance_before` and `balance_after` can look unchanged if top-up and
  transfer happen in the same smoke flow; the stronger evidence is the tx hash
  and wallet history.

Explain `wallet-send-approval-required.json`:

- `requires_approval: true`: the spend policy blocked automatic spending.
- `policy.allowed: false`: the transaction was not executed.
- `approval.status: pending`: the owner must approve.
- `per_transaction_limit: 0`: the default policy is strict.

Explain `wallet-send.json`:

- `ok: true`: allowed transfer path succeeded.
- `transaction.result.success: true`: wallet call succeeded.
- `tx_hash`: transaction proof.
- `spending_controlled: true`: transfer went through the policy engine.

Explain `wallet-history.json`:

- `transactions`: durable local history.
- It should include the same recipient, amount, and transaction hash.

### 3. Messaging: Delivery Topic Proof

Run:

```bash
export RUN=.local/video/messaging-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-messaging-smoke.sh --run-root "$RUN" --message-timeout 90 --daemon-timeout 45
cat "$RUN/messaging-create-group.json"
cat "$RUN/messaging-join.json"
cat "$RUN/messaging-send.json"
tail -n 5 "$RUN/receiver-events.ndjson"
```

Say:

> This proves the agent can send through Logos Delivery. The script starts an
> agent and a separate raw Delivery receiver. The agent creates a topic, joins
> it, sends a message, and the receiver records the delivered event.

Explain `messaging-create-group.json`:

- `ok: true`: group/topic creation passed.
- `group_id`: the Delivery topic.
- `members`: intended participants.
- `transport: delivery_topic`: group transport is represented by a Delivery
  topic because Chat group APIs are not exposed yet.

Explain `messaging-join.json`:

- `ok: true`: the agent joined/subscribed to the topic.

Explain `messaging-send.json`:

- `ok: true`: the send request was accepted.
- `request_id`: send operation ID.
- `topic`: where the message was sent.

Explain `receiver-events.ndjson`:

- `event: messageReceived`: another receiver saw the message.
- `arg1`: the topic.
- `arg2`: the message payload.

Say:

> This is not only an internal function call. A separate receiver observed a
> Delivery event.

### 4. Paid A2A: Agent Services Marketplace

Run:

```bash
export RUN=.local/video/a2a-paid-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-a2a-paid-smoke.sh --run-root "$RUN" --localnet-timeout 240
cat "$RUN/a2a-summary.json"
cat "$RUN/a2a/client-discover-final.json"
cat "$RUN/a2a/client-task-submit.json"
```

Say:

> This is the paid skill marketplace use case. A client agent discovers a
> server Agent Card, reads the advertised price, pays the server, submits an
> A2A task, and both agents reach a completed state.

Explain the script output:

- `ok: true`: paid A2A proof passed.
- `from`: client/payer account.
- `to`: server/payment recipient account.
- `payment_tx_hash`: local LEZ payment transaction.
- `a2a.task_id`: A2A task identifier.
- `paid: true`: payment was attached.
- `canceled: false`: normal completed task path.

Explain `a2a-summary.json`:

- `client_address` and `server_address`: the two agents.
- `task_id`: shared task record.
- `client_discover_final`: discovered Agent Card evidence.
- `client_task_submit`: submitted task evidence.
- `client_completed_status` and `server_completed_status`: both sides reached
  completion.

Explain `client-discover-final.json`:

- `agents`: discovered agents.
- `signature_alg: ed25519`: the Agent Card is signed.
- `logos.payment.price: 1`: advertised 1 LEZ price.
- `logos.payment.recipient`: payment destination.
- `skills`: what the server offers.
- `preferredTransport: logos-messaging`: A2A is bound to Logos Messaging /
  Delivery instead of plain HTTP.

Explain `client-task-submit.json`:

- `task.state: TASK_STATE_SUBMITTED`: task request was created and sent.
- `payment.ok: true`: payment was attached.
- `payment.transfer.transaction.result.tx_hash`: payment proof.
- `transport.ok: true`: task envelope was sent over the task topic.

### 5. Program Operations

Run:

```bash
export RUN=.local/video/program-$(date -u +%Y%m%dT%H%M%SZ)
./scripts/agent-program-smoke.sh --run-root "$RUN" --localnet-timeout 240 --daemon-timeout 45
cat "$RUN/program-query-health.json"
cat "$RUN/program-call-wallet-health.json"
cat "$RUN/program-deploy.json"
```

Say:

> This proves the program skill category. The agent can query LEZ
> health/state, call through the supported wallet/helper bridge, and deploy a
> program binary.

Explain the script output:

- `ok: true`: program proof passed.
- `program_binary`: binary being deployed.
- `program_id`: deterministic identifier for the binary.
- `program_id_source: sha256-fallback`: helper derived the ID from the binary
  hash in this path.

Explain `program-query-health.json`:

- `ok: true`: query path succeeded.
- `mode: wallet-cli`: helper used the LEZ wallet CLI.
- `stdout: All looks good!`: wallet health check passed.

Explain `program-call-wallet-health.json`:

- This proves the program adapter can invoke a supported LEZ/wallet call path
  without crashing the module.

Explain `program-deploy.json`:

- `ok: true`: deploy completed.
- `binary_path`: compiled program binary.
- `program_id`: resulting program identifier.

### Video 3 Closing

Say:

> This third video proves the working skill layer: encrypted storage, wallet
> policy, Messaging over Delivery, paid A2A task coordination, and LEZ program
> operations.

## Common Recording Mistakes

Do not split long flags across lines. This fails:

```bash
./scripts/agent-wallet-smoke.sh --run-root "$RUN" --localnet-
timeout 240
```

Use one line:

```bash
./scripts/agent-wallet-smoke.sh --run-root "$RUN" --localnet-timeout 240
```

The same applies to:

```bash
--message-timeout
--localnet-timeout
--daemon-timeout
```

If you accidentally run the wrong script, say:

> I accidentally ran the wrong smoke script. I am now running the correct one.

Then continue.

## Final Checklist

Across the three videos, make sure you showed:

- Clean repository state.
- `RISC0_DEV_MODE=0`.
- Preflight success.
- Basecamp package/profile install proof.
- Submission bundle and checksums.
- Hosted testnet wallet transfer tx hash.
- Hosted testnet program deploy and call tx hashes.
- Hosted testnet paid A2A payment tx hash.
- Three separate agent evidence.
- CU report status.
- Clean LGX GitHub Actions status.
- Basecamp owner-to-agent Chat messages and replies.
- `wallet.send` pending approval over owner Chat.
- Storage upload/list/share/download and file match.
- Wallet approval gate, transfer tx, and history.
- Messaging Delivery receiver event.
- Paid A2A Agent Card discovery, payment, and task submit.
- Program query/call/deploy.
