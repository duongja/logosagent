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

## 2026-06-26 Update

Logos later reported that the testnet was back online and that chain state was
the same as before the outage. A fresh `v0.2.0-rc5` evidence run against
`https://testnet.lez.logos.co/` then passed the compatibility gate and produced
new hosted-testnet transaction evidence:

| Operation | Tx Hash |
| --- | --- |
| `wallet.send` | `3f140331aee32dba313d0eb73e47b1aad7e6f1dd5dfc8721460c16ac8a011c86` |
| `agent.task` payment leg | `2111c69569e0804e28ca4210e9850a7db4171d6d7f3787d10c0f426629e461b4` |
| `program.deploy` | `1db8975f24b5f27a4c271ea17f7db33e9d654964af8ab980ee78d0e351537f03` |
| `program.call` | `e752295333411623035c660016e8b1fb8deffdb4b7fc5c87fa0007eb004a8f30` |

See `docs/testnet-v020-live-evidence-20260626.md`. The June 25 endpoint
failure below is retained as historical diagnosis only.

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

The hosted LEZ testnet evidence has now been refreshed for `v0.2.0-rc5`. The
current PR should explicitly say:

- pre-redeploy hosted LEZ evidence exists from 2026-06-19;
- Logos redeployed/wiped LEZ on 2026-06-25 for v0.2;
- the local `v0.2.0-rc5` wallet builds and passed the hosted compatibility
  gate after the endpoint came back;
- fresh hosted v0.2 transaction evidence was captured on 2026-06-26;
- the Logos team advised applying for LP-0008 anyway and continuing the CU /
  testnet refresh discussion in the PR.

Do not reuse the old June 19 tx hashes as current post-redeploy proof. Use the
June 26 v0.2 hashes in `docs/testnet-v020-live-evidence-20260626.md`.
