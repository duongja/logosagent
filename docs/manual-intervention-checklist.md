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

2. Recorded two-agent Delivery/A2A proof
   - The headless CLI proof already shows Agent Card discovery, paid task
     submission, terminal A2A state, and LEZ payment in one run.
   - Record that command output, or rerun the same proof on the final demo host.

3. Three illustrative use cases
   - Personal file vault: upload/list/share/download and hash-match the file.
   - Paid skill marketplace: discover a priced Agent Card, pay, and receive the result.
   - Program operation: deploy/call/query a LEZ program or show a monitoring/notary workflow.

4. Narrated demo video
   - Explain what was built and why.
   - Show terminal output for proof-generating runs.
   - Show `RISC0_DEV_MODE=0`.
   - Show hosted-testnet tx hashes from the evidence docs.

5. CU values
   - Fill `docs/cu-report.md` if Logos exposes CU through explorer, sequencer metadata, or logs.
   - If CU is not exposed, get evaluator/Discord confirmation that `TBD` plus tx hashes and benchmark notes are acceptable.

6. Official clean package build
   - Run `nix build --impure .#lgx -L` on a stable machine or GitHub workflow.
   - Keep the generated `.lgx` checksum with the final evidence bundle.

## Bundle Command

Create a sanitized review bundle with:

```bash
./scripts/create-submission-bundle.py
```

The bundle is written under `.local/submission-bundle/<timestamp>` and avoids
copying wallet state or raw runtime secrets.
