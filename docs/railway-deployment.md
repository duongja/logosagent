# Optional Railway Deployment

`logos_agent` remains local-first. `./demo.sh` and the headless Core scripts do
not require Railway. Railway is an optional host for keeping one agent process
online continuously while it connects to the same public `logos.test` Delivery
and Storage presets and the Testnet v0.2 LEZ endpoint.

## Architecture

The Railway service runs Logos Core plus the released v0.2 modules. A volume at
`/data` preserves the wallet, signed A2A identity, agent state, and Storage
state across deployments. Its HTTP domain exposes only sanitized readiness
data and the signed Agent Card. Module calls remain available through
`railway ssh` and are not exposed as an unauthenticated HTTP API.

The released Chat module v0.2.1 intentionally keeps its cryptographic identity
ephemeral. Its Chat address therefore changes after a Railway restart or
redeployment. Basecamp must use the current address reported by `/healthz`;
wallet and signed Agent Card identity remain stable on the volume.

## Stage The Verified Runtime

Prepare the exact pinned runtime used by local E2E, then create an ignored
upload context:

```bash
./scripts/prepare-v02-runtime.sh
./scripts/stage-railway-deployment.sh
```

The staging script refuses unexpected module versions and writes a SHA-256
manifest under `.local/railway-deployment`. Native binaries are not committed
to Git.

## Deploy

Create or link an isolated Railway project, add a service, and deploy the
staged context:

```bash
railway init --name logos-agent-v02
railway add --service logos-agent
railway volume add --service logos-agent --mount-path /data
railway variable set --service logos-agent \
  AGENT_ID=logos-agent-v02-online \
  AGENT_NAME="Logos Agent v0.2"
openssl rand -base64 48 | \
  railway variable set --service logos-agent LOGOS_WALLET_PASSWORD --stdin
railway up .local/railway-deployment --path-as-root --service logos-agent
railway domain --service logos-agent
```

Railway supplies `PORT`. The container refuses `localnet` and `logos.dev`, so a
hosted deployment cannot silently be mislabeled as public-testnet activity.
Transaction limits default to zero, meaning spends require an explicit approval.

## Verify

```bash
curl -fsS "https://<railway-domain>/healthz" | jq
curl -fsS "https://<railway-domain>/agent-card" | jq
railway logs --service logos-agent
```

The health response includes the network, `logos.test` preset, current module
versions, Chat address, and public wallet account when available. It never
returns wallet passwords, wallet storage, private keys, file keys, or plaintext
payloads.

Use the reported Chat address to create a private conversation in Basecamp.
For local-only operation, use `scripts/start-owner-chat-agent.sh` instead; the
owner message format is identical in both modes.
