# Basecamp v0.1.2 Agent Proof - 2026-06-22

This note is a compact support artifact for the Logos team. It records the
current LP-0008 module behavior on the recommended Basecamp `0.1.2` workshop v3
build without committing the full raw peer log.

## What Passed

- Basecamp launched from Scaffold workspace `/tmp/lb`.
- Basecamp reported `LogosBasecamp version 0.1.2 (dev build)`.
- `logos-basecamp` commit:
  `63b35e8a0e826789ba15a46766df9fedc6794bc8`.
- The five LP-0008 runtime modules loaded in the Alice profile:
  `storage_module`, `chat_module`, `delivery_module`, `logos_execution_zone`,
  and `logos_agent`.
- `logos_agent.skills()` returned the full required skill surface.
- `logos_agent.init()` succeeded.
- `logos_agent.start()` succeeded with async startup.
- `logos_agent.status()` returned `started = true`, `starting = false`.
- `logos_agent.invoke("agent.card", "{}")` returned a signed Ed25519
  A2A-compatible Agent Card.
- Delivery started and connected:
  `DeliveryModuleImpl: Delivery start completed with success`, followed by
  `connectionStatus change ... newstatus=Connected`.

## Important Runtime Choices

The safe Basecamp config used:

```json
{
  "runtime": {"async_start": true},
  "autostart_storage": false,
  "delivery": {"preset": "logos.dev", "mode": "Core"}
}
```

Storage is deliberately initialized but not started in this Basecamp proof.
Starting `storage_module` inside Basecamp previously reached `Started Storage
node`, then the `storage_module` host process crashed with:

```text
malloc(): mismatching next->prev_size (unsorted)
```

Headless Logos Core storage tests still pass upload/list/share/download and
byte-for-byte recovery.

## Log Anchors

Raw local log path:

```text
/tmp/lb/.scaffold/logs/manual-launch/20260622T130642Z-alice-agent-safe-slow-inspector.log
```

Committed extracts:

- `basecamp-log-extract.txt`
- `inspector-summary.jsonl`

Relevant lines:

- 18-20: Basecamp version and commit.
- 449: `storage_module` loaded.
- 470: `chat_module` loaded.
- 493: `delivery_module` loaded.
- 516: `logos_execution_zone` loaded.
- 537: `logos_agent` loaded.
- 620-644: `logos_agent` subscribed to storage, chat, Delivery message, and
  Delivery connection events.
- 941: `DeliveryModuleImpl::start called`.
- 1073: `DeliveryModuleImpl: Delivery start completed with success`.
- 1075-1079: Delivery reached `Connected` and emitted
  `connectionStateChanged`.

## Current Open Questions For Logos

1. Is there a known Basecamp/storage ABI or heap issue when `storage_module` is
   started as a loaded Basecamp module, while the same storage flow passes in
   headless Logos Core tests?
2. `delivery_module.start()` can return an empty failed result over the SDK even
   while the Delivery module logs show success and connection. Should clients
   treat the module's connection events as the source of truth for start status?
3. For LP-0008 evaluation, is a Basecamp Chat UI owner-channel recording with
   storage configured but not autostarted acceptable if storage skill proofs are
   provided headlessly through Logos Core?
