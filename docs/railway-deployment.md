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

Create or link an isolated Railway project and add a service. Link the service
explicitly before creating its volume; current Railway CLI releases otherwise
fail to resolve the service instance:

```bash
railway init --name logos-agent-v02
railway add --service logos-agent
railway service link logos-agent
railway variable set --service logos-agent \
  AGENT_ID=logos-agent-v02-online \
  AGENT_NAME="Logos Agent v0.2"
openssl rand -base64 48 | \
  railway variable set --service logos-agent LOGOS_WALLET_PASSWORD --stdin
```

If the service has never deployed, connect a small temporary image so Railway
creates its service instance. This changes only the new service:

```bash
railway service source connect --image nginx:alpine --service logos-agent
railway volume add --mount-path /data
railway volume list --json
```

Upload the checksum-pinned archive to the returned volume ID, then replace only
the selected temporary service with the pinned image deployment:

```bash
./scripts/deploy-railway-volume.sh --volume-id <volume-id> \
  --service logos-agent --dry-run
./scripts/deploy-railway-volume.sh --volume-id <volume-id> \
  --service logos-agent --yes
railway domain --service logos-agent
```

The helper first confirms that the volume belongs to the selected service and
is mounted at `/data`. It uploads the runtime plus two small tracked bootstrap
files, records the public archive checksum, and updates only that service. The
bootstrap verifies SHA-256 before extracting the runtime. The tracked
self-contained `deploy/railway/Dockerfile` remains available for deployments
through an authenticated image registry.

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

## Current Public Instance

The maintained instance is available at
`https://logos-agent-production.up.railway.app`. Its `/healthz` response is the
current online-status view, not the authoritative paid-task evidence. The
captured two-agent public Testnet v0.2 run, including transaction
`ee5b41972e315f0bca0d2c7745048dfe6e875418ccef1b132160f35995d9d9ea`,
remains under `evidence/current/testnet-v02/`.

The instance was restarted after first deployment to verify volume persistence.
Its public LEZ account and signed Agent Card key remained stable; the Chat
address rotated as expected for Chat v0.2.1. The hosted wallet currently has a
zero balance, so this availability endpoint must not be presented as a new paid
transaction run until it is funded and the full two-agent harness is rerun.
The older transaction is also absent from the reset chain as of 2026-08-05;
see `docs/testnet-chain-status-20260805.md`.
