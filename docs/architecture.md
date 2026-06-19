# Architecture

`logos_agent` is a Logos Core module. It is built as a Qt plugin, loaded by
Logos Core, and depends on existing Core modules:

- `logos_execution_zone` for LEZ account and token operations,
- `storage_module` for Logos Storage,
- `chat_module` for owner private chat,
- `delivery_module` for pub/sub discovery, groups, and A2A task transport.

The runtime is centered on `AgentRuntime`:

- `SkillRegistry` stores names, schemas, category, price, and handler function.
- `PolicyEngine` decides whether token-spending skills may execute or need
  owner approval.
- `AgentState` persists config, approvals, transactions, files, messages, tasks,
  and discovered Agent Cards.
- Adapters isolate dependency-specific code:
  - `WalletAdapter`
  - `StorageAdapter`
  - `MessagingAdapter`
  - `A2AAdapter`
  - `ProgramAdapter`

## State

State is stored in `state.json` under `instancePersistencePath`.

The current bounded queues are small enough for JSON and easy evaluator
inspection. Move to SQLite if task and message volume become large.

## Startup

1. Logos Core calls `initLogos(LogosAPI*)`.
2. The plugin creates `LogosModules`.
3. The runtime reads `instancePersistencePath`.
4. `init(configJson)` merges config into state.
5. `start()` initializes wallet, storage, chat, and delivery adapters.
6. Optional A2A card publish runs if `a2a.publish_on_start` is true.

## Spending

Skills marked `spendsTokens` are checked before execution. If the request exceeds
the per-transaction or period limit, the runtime stores a pending approval and
emits `approvalRequired`. `approve(approvalId, {"approved": true})` executes the
stored request.

Default policy fails closed:

```json
{
  "per_transaction_limit": "0",
  "period_limit": "0",
  "period_seconds": 86400
}
```

## Async Dependencies

Storage upload/download and chat operations are event-driven in the underlying
modules. The agent returns the initial session/request information and updates
durable state from dependency events.
