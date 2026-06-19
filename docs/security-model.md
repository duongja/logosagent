# Security Model

The agent can act without owner approval only inside configured limits.

## Allowed Without Approval

- Non-spending skills.
- Spending skills whose amount stays within both:
  - `policy.per_transaction_limit`
  - `policy.period_limit` over `policy.period_seconds`

## Requires Approval

- `wallet.send`
- `program.call`
- `program.deploy`
- `agent.task` when it includes payment

If a spend exceeds policy, the agent writes a pending approval to durable state
and emits `approvalRequired`. The transaction is not submitted until the owner
approves it.

## Failure Rules

- A failed owner notification must not execute the transaction.
- Pending approvals survive restart.
- Skill failures return `ok:false` and should not crash the module.
- External call results are stored in transaction/task history.

## Storage Encryption

New storage uploads are encrypted locally with AES-256-GCM before calling Logos
Storage. The metadata records the algorithm, nonce, tag, and content hashes.
Downloads verify the ciphertext hash and AEAD tag before writing plaintext.

`storage.share` does not expose the raw file key in the returned payload. The
agent wraps the file key to the recipient X25519 public key using
X25519/HKDF-SHA256 plus AES-256-GCM. The recipient can pass the received share
payload to `storage.download` so the agent unwraps it with its local X25519
identity key before decrypting the downloaded ciphertext.

Legacy `xor-sha256-stream-dev` metadata is only accepted when
`security.allow_dev_file_cipher=true`.

## Current Hardening Gaps

- Bind A2A signing keys directly to future Logos Messaging/LEZ account key
  material. The current implementation uses an agent Ed25519 identity key stored
  in agent config.
- Avoid passing wallet passwords on command lines.
- Run and promote the opt-in localnet integration harness against a real
  sequencer with `RISC0_DEV_MODE=0`.
