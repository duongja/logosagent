# A2A Over Logos Messaging Binding

The module targets A2A protocol version `1.0` at the Agent Card level and uses
Logos Delivery topics as the transport.

## Agent Card

`agent.card()` returns:

- `protocolVersion: "1.0"`
- `name`
- `description`
- `url: logosmsg://<agent-address>`
- `preferredTransport: "logos-messaging"`
- `capabilities`
- `defaultInputModes`
- `defaultOutputModes`
- `skills`
- `securitySchemes`
- `logos` extension object

The `logos` extension includes:

- `agent_address`
- `lez_account`
- `signing_key_id`
- `signing_public_key`
- `encryption_key_id`
- `encryption_public_key`
- `task_topic`
- `discovery_topic`
- `payment`

## Topics

Default discovery:

```text
/logos-agent/1/discovery/json
```

Task inbox:

```text
/logos-agent/1/task-<sha256(agent-address)[0:32]>/json
```

Task status:

```text
/logos-agent/1/status-<sha256(task-id)[0:32]>/json
```

The hash is folded into the content-topic name segment so generated topics
remain valid LIP-23 short-form content topics:
`/<application>/<version>/<name>/<encoding>`.

## Envelope

Delivery payloads are JSON objects:

```json
{
  "logos_agent_protocol": "a2a-logos-messaging-binding",
  "version": "0.1.0",
  "kind": "task.submit",
  "payload": {},
  "created_at": "2026-06-06T00:00:00Z",
  "nonce": "msg_...",
  "signature": "..."
}
```

Kinds:

- `agent.card`
- `task.submit`
- `task.status`
- `task.cancel`

Task states use A2A names:

- `TASK_STATE_SUBMITTED`
- `TASK_STATE_WORKING`
- `TASK_STATE_INPUT_REQUIRED`
- `TASK_STATE_COMPLETED`
- `TASK_STATE_FAILED`
- `TASK_STATE_CANCELED`

## Payment

The card may declare a LEZ price per skill in `logos.payment`. The client calls
`agent.task` with `amount`; the runtime enforces local spending policy before
sending the task.

For the current local implementation, a positive `amount` triggers a LEZ
`wallet.send` before the task is submitted. The task payload carries a
`payment` receipt containing amount, recipient, mode, timestamp, and the wallet
transfer result including `tx_hash`. The receiving agent records that receipt in
its durable transaction history before executing the task.

Cancellation uses the same transport envelope with kind `task.cancel`. When a
paid task is canceled after payment acceptance and refund parameters are
configured, the runtime submits a LEZ refund through `wallet.send`, records the
refund receipt on the task, and exposes the refund transfer in `agent.subscribe`
and `meta.status`.

The local A2A smoke proofs cover discovery, signed Agent Card receipt, payment
acceptance, task completion, and cancellation refund. The hosted-testnet
evidence currently proves the LEZ payment leg with transaction lookup and
balance deltas; CU/cycle values still depend on the target network exposing
that metadata or an evaluator-approved benchmark mapping.

## Signatures And Replay Protection

Agent Cards and task envelopes are signed with the agent identity Ed25519 key
stored under `identity.signing`. Envelopes include:

- `signature_alg: "ed25519"`
- `signature_key_id`
- `signer_public_key`
- `signature`

Inbound envelopes are verified before any state mutation. The runtime stores
accepted `(signature_key_id, nonce)` pairs in durable state and rejects repeats.

The old `logos-hmac-dev` path is retained only as an explicit compatibility
fallback when `security.allow_dev_a2a_secret=true`.
