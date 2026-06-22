# Basecamp Owner Chat Evidence - 2026-06-22

This run verifies the user-facing owner-to-agent path: Basecamp Chat as the
owner app, a headless `logos_agent` instance as the agent, and skill calls sent
as JSON messages in the private Chat conversation.

## Environment

- Basecamp AppImage: `LogosBasecamp`, version `0.1.2`.
- Agent modules: regenerated from the patched module set with
  `scripts/package-live-modules-lgx.sh`.
- Agent run root:
  `.local/owner-chat-agent/20260622T144124Z-peers`.
- Basecamp log:
  `$HOME/.local/share/Logos/LogosBasecamp/logs/basecamp_20260622_173647.log`.
- Owner conversation id:
  `6ceca915db6fcc4c3869e08f480469cc14c0`.

The agent Chat config intentionally omits `staticPeers`, allowing
`chat_module` to use its default Logos development bootstrap peers. Earlier
isolated configs with `staticPeers: []` did not receive owner messages.

## Commands Sent From Basecamp Chat

The owner sent these JSON skill calls in the Basecamp Chat UI:

```json
{"skill":"meta.status","params":{}}
{"skill":"agent.card","params":{}}
{"skill":"wallet.balance","params":{}}
{"skill":"storage.list","params":{}}
{"skill":"messaging.send","params":{"recipient":"6ceca915db6fcc4c3869e08f480469cc14c0","message":"agent echo proof"}}
{"skill":"wallet.send","params":{"recipient":"deadbeef","amount":"1"}}
```

## Results

The agent received the Chat messages through the real `chat_module` wrapped
push-event payload and replied into the same conversation with
`type = "skill_result"` messages.

Confirmed behavior:

- `meta.status` returned agent status over the owner Chat conversation.
- `agent.card` returned a signed A2A-compatible Agent Card.
- `wallet.balance` dispatched through the wallet skill. In this GUI-only proof
  the wallet was not funded/opened, so a controlled wallet error is expected.
- `storage.list` returned successfully with no stored files for this isolated
  owner-chat run.
- `messaging.send` sent the requested echo message to the owner conversation.
- `wallet.send` did not execute immediately. With zero spend limits, it created
  a durable pending owner approval.

Pending approval created by the owner Chat `wallet.send` test:

```json
{
  "approval_id": "appr_29deccb3d30d7ab1842b43b8f42f1285",
  "skill": "wallet.send",
  "amount": "1",
  "status": "pending",
  "origin": "owner-chat"
}
```

The live daemon logs showed `ChatModuleImpl::sendMessage` calls returning
`ret: 0` after each owner command. Basecamp logs also showed relay messages
arriving around the same timestamps, confirming the owner app received the
agent replies.

## Prize Relevance

This proof covers the owner-facing Basecamp requirement:

- owner interacts from a separate Basecamp app instance;
- no exposed HTTP API is used;
- owner messages invoke agent skills;
- the agent replies over the encrypted Chat conversation;
- above-threshold spending remains pending for owner approval.

Storage round trip, funded wallet transfer, Messaging/Delivery group send,
paid A2A, and program operations are covered separately by the localnet
evidence refresh and hosted-testnet evidence docs.

