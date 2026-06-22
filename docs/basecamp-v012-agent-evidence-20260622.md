# Basecamp v0.1.2 Agent Evidence - 2026-06-22

This run verifies the LP-0008 module set against the Basecamp build recommended
by the Logos team.

## Environment

- Basecamp: `0.1.2` dev build.
- `logos-basecamp` commit:
  `63b35e8a0e826789ba15a46766df9fedc6794bc8`.
- Scaffold workspace: `/tmp/lb`.
- Basecamp profile: `alice`.
- Agent config:
  `.local/basecamp-safe-config/agent-config.json`.
- Runtime settings used for this Basecamp-safe proof:
  `runtime.async_start = true` and `autostart_storage = false`.

## Commands

```bash
cmake --build .local/direct-build/logos_agent-basecamp-sdk --parallel 1
cp .local/direct-build/logos_agent-basecamp-sdk/modules/logos_agent_plugin.so \
  .local/live-modules/logos_agent/logos_agent_plugin.so
./scripts/package-live-modules-lgx.sh

cd /tmp/lb
/home/agate/Projects/logos/scaffold/target/release/logos-scaffold basecamp install
/home/agate/Projects/logos/scaffold/target/release/logos-scaffold basecamp launch alice
```

The Basecamp QML inspector was then used to call:

- `backend.loadCoreModule("storage_module")`
- `backend.loadCoreModule("chat_module")`
- `backend.loadCoreModule("delivery_module")`
- `backend.loadCoreModule("logos_execution_zone")`
- `backend.loadCoreModule("logos_agent")`
- `backend.getCoreModuleMethods("logos_agent")`
- `backend.callCoreModuleMethod("logos_agent", "skills", "[]")`
- `backend.callCoreModuleMethod("logos_agent", "init", [config])`
- `backend.callCoreModuleMethod("logos_agent", "start", "[]")`
- `backend.callCoreModuleMethod("logos_agent", "status", "[]")`
- `backend.callCoreModuleMethod("logos_agent", "invoke", ["agent.card", "{}"])`

The inspector client must wait between module loads. Sending several module
loads back-to-back can leave Basecamp waiting while module registration is still
settling.

## Results

Basecamp log:

```text
/tmp/lb/.scaffold/logs/manual-launch/20260622T130642Z-alice-agent-safe-slow-inspector.log
```

Relevant log anchors:

- Lines 18-20: Basecamp `0.1.2` and `logos-basecamp`
  `63b35e8a0e826789ba15a46766df9fedc6794bc8`.
- Line 449: `storage_module` loaded.
- Line 470: `chat_module` loaded.
- Line 493: `delivery_module` loaded.
- Line 516: `logos_execution_zone` loaded.
- Line 537: `logos_agent` loaded.
- Line 941: `DeliveryModuleImpl::start called`.
- Line 1073: `DeliveryModuleImpl: Delivery start completed with success`.
- Lines 1075-1079: Delivery connection status changed to `Connected` and
  emitted `connectionStateChanged`.

Inspector result summary:

- `logos_agent` exposed the expected invokable methods:
  `init`, `start`, `stop`, `invoke`, `approve`, `skills`, and `status`.
- `skills()` returned the full LP-0008 default skill surface.
- `init()` succeeded and persisted state under the Basecamp profile module data
  path.
- `start()` returned quickly with:
  - chat started,
  - Delivery created and starting asynchronously,
  - storage configured but not autostarted,
  - wallet open failure expected for this smoke config because no real wallet
    config was provided.
- Delayed `status()` showed the agent started and no longer starting.
- `agent.card` returned a signed A2A-compatible card with
  `protocolVersion = "1.0"`, `preferredTransport = "logos-messaging"`, and
  `signature_alg = "ed25519"`.

## Known Limitations

- This proof intentionally does not start the Storage node inside Basecamp.
  A separate Basecamp run with storage autostart enabled reached `Started
  Storage node`, then `storage_module` crashed with heap corruption. Headless
  storage skill tests still pass through `storage_module`, including
  upload/list/share/download and byte-for-byte recovery.
- `delivery_module.start()` can return an empty failed result over the SDK while
  the Delivery module logs show successful startup and a connected node. The
  agent now reports this as `return_unverified = true` instead of blocking the
  UI startup path.
- The safe Basecamp config intentionally leaves `messaging_address`,
  `lez_account`, and wallet paths empty. It proves Basecamp module load/start,
  not funded wallet or deployed-agent A2A identity. Those flows are covered by
  the headless localnet and hosted-testnet evidence docs.
- Final prize evidence still needs a recorded Basecamp Chat UI owner-channel
  interaction from a separate owner profile.
