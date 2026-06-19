# Skill Interface

Skills are discrete handlers registered by name.

Each skill definition has:

- `name`
- `category`
- `description`
- `input_schema`
- `output_schema`
- `price`
- `spends_tokens`
- `handler(runtime, params, origin)`

The public invocation form is:

```bash
logoscore call logos_agent invoke storage.upload '{"path":"/tmp/a.txt","label":"a"}'
```

## Required Skills

Storage:

- `storage.upload(path, label)`
- `storage.download(address, path, share?)`
- `storage.list()`
- `storage.share(address, recipient, recipient_public_key_hex?)`

`storage.share` accepts `recipient_public_key_hex` directly, or a recipient
object/Agent Card containing `logos.encryption_public_key`. The returned share
payload contains `encryption.key_wrap` instead of the raw file key.

When receiving a share, call `storage.download` with the share payload in
`share`; `address` can be omitted because it is read from `share.address`.

Messaging:

- `messaging.send(recipient, message, transport?)`
- `messaging.join(group_id)`
- `messaging.create_group(members, group_id?)`

Wallet:

- `wallet.balance()`
- `wallet.send(recipient, amount, mode?)`
- `wallet.history()`

Programs:

- `program.query(...)`
- `program.call(program_id, instruction, params, amount?)`
- `program.deploy(binary_path, amount?)`

A2A:

- `agent.card()`
- `agent.discover(topic?)`
- `agent.task(agent_address, skill, params, amount?)`
- `agent.subscribe(task_id)`
- `agent.cancel(agent_address, task_id, reason?)`

Meta:

- `meta.skills()`
- `meta.status()`
- `meta.configure(key, value)`

## Adding A Skill

Add a `SkillDefinition` in `AgentRuntime::registerDefaultSkills()` or split
third-party skill loading into a new registry source. Keep the handler narrow:
validate params, call one adapter, and return a JSON object.

Token-spending skills must set `spendsTokens = true`.

`program.deploy` is backed by `agent_lez`, which invokes the LEZ `wallet`
CLI's `deploy-program` command.

`program.call` is backed by `agent_lez call`. Because the current LEZ wallet
does not expose a stable generic arbitrary-program call command, the helper
supports three concrete call forms:

- `wallet_args`: exact wallet CLI argv, for example
  `["auth-transfer","init","--account-id","Public/..."]`.
- `wallet_command` plus optional `args`: a structured wallet subcommand prefix.
- Known wallet facades via `program`/`program_id`, `instruction`, and `params`
  for `auth-transfer`, `token`, `ata`, `amm`, and `pinata`.

The older `runner`/`args` form remains available for program-specific demo
runners that are not exposed by the wallet CLI.
