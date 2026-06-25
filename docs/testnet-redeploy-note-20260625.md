# LEZ Testnet Redeploy Note - 2026-06-25

On 2026-06-25 the Logos builders channel announced a LEZ redeploy in
preparation for v0.2 Testnet. The announcement said LEZ state was wiped and
builders should recompile and redeploy programs against:

```text
https://github.com/logos-blockchain/logos-execution-zone/tree/v0.2.0-rc5
```

This affects the hosted-testnet evidence captured on 2026-06-19. Those tx
hashes remain accurate historical evidence for the previous hosted LEZ testnet
state, but they should not be presented as currently queryable post-redeploy
evidence.

## Current Checks

After the announcement, a compatibility check against
`https://testnet.lez.logos.co/` showed the old wallet/RPC evidence path is no
longer valid:

- direct calls to the old public methods `checkHealth`, `getProgramIds`,
  `getTransaction`, and `getAccount` returned `METHOD_NOT_FOUND`;
- the locally built pre-v0.2 wallet failed `check-health` against the current
  endpoint because the endpoint error shape changed.

The v0.2 release was then fetched and built locally:

- LEZ `v0.2.0-rc5` at commit
  `27360cb7d6ccb2bfbcca7d171bab8a3938490264`;
- `cargo +1.94.0 build -p wallet --release -j1` succeeded;
- the v0.2 wallet still expects `checkHealth`, `getProgramIds`, and
  `getLastBlockId`;
- the advertised endpoint still returned `METHOD_NOT_FOUND` for those methods;
- the explorer returned `502 Bad Gateway` during the same check.

The sanitized v0.2 check is documented in
`docs/testnet-v020-compatibility-evidence-20260625.md`. Raw local check
directories were written under:

```text
.local/testnet-evidence/redeploy-check-20260625T174028Z
.local/testnet-evidence/v020-rc5-check-20260625T182442Z
```

That raw directory is intentionally not committed because testnet evidence runs
can contain local wallet state.

## Submission Impact

The Basecamp owner-channel, Storage, Messaging/Delivery, local A2A, local
wallet, and local program-operation evidence are not invalidated by the hosted
LEZ redeploy.

The hosted LEZ testnet evidence needs a v0.2 refresh before it should be
claimed as current testnet evidence. The current PR should explicitly say:

- pre-redeploy hosted LEZ evidence exists from 2026-06-19;
- Logos redeployed/wiped LEZ on 2026-06-25 for v0.2;
- the local `v0.2.0-rc5` wallet builds and has been checked;
- a post-redeploy transaction refresh is pending on the confirmed v0.2
  sequencer RPC endpoint/funding path;
- the Logos team advised applying for LP-0008 anyway and continuing the CU /
  testnet refresh discussion in the PR.

Do not reuse the old June 19 tx hashes as current post-redeploy proof unless a
new explorer or RPC endpoint can still retrieve them.
