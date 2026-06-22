# Basecamp Crash/Restart Report - 2026-06-20

This folder contains the local evidence for the Basecamp setup/launch instability seen while preparing the LP-0008 Logos agent submission.

## Summary

- Project: LP-0008 autonomous Logos agent module.
- Basecamp source configured by Scaffold: `https://github.com/logos-co/logos-basecamp.git`.
- Basecamp pin in `scaffold.toml`: `a746cdbc521f72ee22c5a4856fd17a9802bb9d69`.
- Scaffold CLI commit used locally: `ae8c0b9`.
- LGX install smoke test passed for two isolated Basecamp profiles, `alice` and `bob`.
- The instability appears around `logos-scaffold basecamp setup` / Basecamp app build or launch, not around the headless Logos Core agent flows.
- The local machine had about 7.6 GiB RAM and 11 GiB swap. The monitored setup run shows high memory and I/O pressure during Nix builds.

## Repro Attempt

The failing setup flow was run from:

```bash
cd /home/agate/Projects/logos/logos-agent/.local/basecamp-owner-channel
/home/agate/Projects/logos/scaffold/target/release/logos-scaffold basecamp setup
```

The command log also points to the main Basecamp setup log:

```text
.scaffold/logs/20260619-163100-138-setup-basecamp.log
```

## Files

- `scaffold.toml`: exact Scaffold project config used for the Basecamp owner-channel profile.
- `logs/20260619-162328-424-setup-basecamp.log`: early Basecamp setup attempt.
- `logs/20260619-163100-138-setup-basecamp.log`: monitored Basecamp setup attempt.
- `logs/20260620-085403-265-setup-basecamp.log`: later Basecamp setup attempt after retry.
- `test-run/preflight.txt`: machine and environment snapshot before the monitored run.
- `test-run/resource-monitor.log`: periodic process, memory, swap, and pressure snapshot during the monitored run.
- `test-run/command.log`: wrapper command used for the monitored setup run.
- `module-sizes.txt`: LGX package sizes generated from this project.

## Observations

The setup logs mostly show Nix fetching/building Basecamp and dependencies such as Qt/WebKit/GTK-related packages. The resource monitor shows memory pressure rising during the setup build. The logs do not show an obvious crash inside the `logos_agent` module.

The generated module packages are small compared with the Basecamp build itself:

- `logos_agent.lgx`: about 810 KiB.
- `storage_module.lgx`: about 6.3 MiB.
- `logos_execution_zone.lgx`: about 6.4 MiB.
- `delivery_module.lgx`: about 14 MiB.
- `chat_module.lgx`: about 14 MiB.

## Questions For Logos

1. Does Basecamp commit `a746cdbc521f72ee22c5a4856fd17a9802bb9d69` correspond to the recommended `v0.1.2-workshop v3` build?
2. Is there a lighter or prebuilt Basecamp path that avoids building `.#app` locally on low-memory hardware?
3. Since LGX profile installation succeeds and the agent module is small, does this look more like Basecamp/Nix/QtWebEngine build pressure than an agent module runtime crash?
