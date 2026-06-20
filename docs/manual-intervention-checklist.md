# Manual Intervention Checklist

Everything below needs either a GUI session, external Logos infrastructure
decision, or final narrated recording. The repository now contains the local
module implementation, local smoke evidence, hosted-testnet transaction
evidence, and packaging helpers.

## Must Be Recorded For Final Prize Submission

1. Basecamp owner-channel proof
   - Launch Basecamp with separate owner and agent profiles.
   - Show the module set loaded.
   - Send at least one owner chat JSON skill call to the agent.
   - Show the agent response and matching agent/Core logs.

2. Three testnet agent deployments
   - Use `.local/testnet-agents/latest/storage-agent/deploy.sh`.
   - Use `.local/testnet-agents/latest/messaging-agent/deploy.sh`.
   - Use `.local/testnet-agents/latest/blockchain-agent/deploy.sh`.
   - Record `agent.card`, `meta.skills`, and `meta.status` for each agent.

3. Live two-agent Delivery/A2A run
   - Two agents discover each other through Agent Cards.
   - Client submits a paid task to the server.
   - Server reaches a valid terminal A2A state.
   - The LEZ payment tx is shown in the same flow.

4. Three illustrative use cases
   - Personal file vault: upload/list/share/download and hash-match the file.
   - Paid skill marketplace: discover a priced Agent Card, pay, and receive the result.
   - Program operation: deploy/call/query a LEZ program or show a monitoring/notary workflow.

5. Narrated demo video
   - Explain what was built and why.
   - Show terminal output for proof-generating runs.
   - Show `RISC0_DEV_MODE=0`.
   - Show hosted-testnet tx hashes from the evidence docs.

6. CU values
   - Fill `docs/cu-report.md` if Logos exposes CU through explorer, sequencer metadata, or logs.
   - If CU is not exposed, get evaluator/Discord confirmation that `TBD` plus tx hashes and benchmark notes are acceptable.

7. Official clean package build
   - Run `nix build --impure .#lgx -L` on a stable machine or GitHub workflow.
   - Keep the generated `.lgx` checksum with the final evidence bundle.

## Bundle Command

Create a sanitized review bundle with:

```bash
./scripts/create-submission-bundle.py
```

The bundle is written under `.local/submission-bundle/<timestamp>` and avoids
copying wallet state or raw runtime secrets.
