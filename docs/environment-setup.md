# Environment Setup

This repo needs a Logos/Nix/Qt build environment for the C++ Core module.

## What Is Installed Here

The local machine now has the baseline build tools for this project:

- Nix single-user install in `/nix`
- persistent Nix flakes support in `~/.config/nix/nix.conf`
- Qt 6 development packages
- C/C++ build tools
- `pkg-config`, `xz`, certificates, and curl
- user-level CMake in `~/.local/bin`
- Rust/Cargo from the user toolchain

Use these paths in a fresh shell:

```bash
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
export PATH="$HOME/.local/bin:$PATH"
```

## Verification

Quick checks:

```bash
nix --version
cmake --version
qmake6 -v
pkg-config --modversion Qt6Core
python3 -m py_compile cli/logos-agent-cli
cd agent_lez && cargo fmt --check && cargo check
```

## Stable Real-Test Runner

Heavy Logos builds and LEZ proofs can stress this laptop. Before running real
integration tests, plug in AC power, close browser-heavy workloads, and use the
stable runner:

```bash
./scripts/stable-test-runner.sh -- nix build --impure .#unit-tests-fast -L --max-jobs 1 --cores 2
./scripts/stable-test-runner.sh -- ./scripts/delivery-smoke.sh --preset logos.dev --api-only
```

The runner refuses battery power by default, blocks GNOME/logind
shutdown/sleep/idle requests while the command runs, limits common build
parallelism to 2 jobs, and writes logs under `.local/test-runs/<timestamp>/`.
Use `--allow-battery` only for deliberately light smoke tests.

Before module-level smoke tests, verify that the locally installed runtime
modules still point at live Nix store outputs:

```bash
./scripts/check-runtime-modules.sh
```

If this reports broken symlinks under `.local/live-modules`, rebuild or reinstall
the missing module packages before running Delivery, Storage, LEZ, or full agent
smokes. A Nix garbage collection can remove the store paths behind those
symlinks.

To repair the local development module directory:

```bash
./scripts/stable-test-runner.sh -- ./scripts/repair-live-modules.sh
```

This rebuilds only broken required modules and refreshes their directories under
`.local/live-modules`. Run it on AC power; Delivery, Storage, and LEZ builds can
be expensive on this laptop.

## Pinned LEZ Localnet Runtime

The scaffold localnet currently pins LEZ to commit
`35d8df0d031315219f94d1546ceb862b0e5b208f`, which exposes an older
`wallet-ffi` ABI than the normal `logos_execution_zone` flake input used by the
module build. For local wallet and paid A2A proofs, align the runtime
`logos_execution_zone` module with the scaffold-pinned FFI:

```bash
./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 -- ./scripts/build-pinned-lez-runtime.sh
```

The script builds `wallet-ffi` from the scaffold-pinned LEZ checkout with
`--no-default-features`, patches a scratch copy of `logos-execution-zone-module`
with `patches/logos-execution-zone-module-pinned-localnet-ffi.patch`, installs
the resulting module under `.local/live-modules/logos_execution_zone`, preserves
a timestamped backup, and runs `scripts/check-runtime-modules.sh`.

Run this after `scripts/repair-live-modules.sh` if that script refreshed
`logos_execution_zone` from the normal flake input. The current pinned FFI also
rejects one scaffold recipient public-key base58 form, so the wallet and paid
A2A smoke scripts default that recipient to the equivalent account hex:
`15145aee2e6c9c57d2847b8ca2e100937f11ee76fdfd75fcb588488aa2064547`.

Full project checks:

```bash
cd logos-agent
./scripts/stable-test-runner.sh -- nix build --impure .#unit-tests-fast -L --max-jobs 1 --cores 2
./scripts/stable-test-runner.sh -- nix build --impure .#unit-tests -L --max-jobs 1 --cores 2
./scripts/stable-test-runner.sh -- nix build --impure .#lgx -L --max-jobs 1 --cores 2
```

`unit-tests-fast` is the quick local C++ test target. It avoids realizing the
full Logos Storage/Chat/Delivery/LEZ dependency closure, so use it while
iterating. `unit-tests` and `lgx` are the heavier integration/package checks.

If the current machine already has a tested agent payload at
`.local/live-modules/logos_agent`, regenerate the dev LGX artifact without the
full Nix package rebuild:

```bash
./scripts/package-dev-lgx.sh
```

This creates `result/logos-logos_agent-module-lib.lgx` and verifies the package
with the local `lgx` binary.

For Basecamp profile installation, package the full locally tested runtime
module set:

```bash
./scripts/package-live-modules-lgx.sh
```

This emits verified path-based LGXs for `delivery_module`, `storage_module`,
`chat_module`, `logos_execution_zone`, and `logos_agent` under
`.local/artifacts/basecamp-lgx/`.

## Local Logos Sources

The project flake is wired to sibling Logos repositories next to `logos-agent`,
including storage, chat, delivery, execution zone, module builder, and shared
Nix/helper inputs. Storage, chat, and delivery sources are referenced with
submodules enabled so vendored dependencies are present.

From a clean workspace, run:

```bash
./scripts/bootstrap-workspace.sh
```

The bootstrap script clones pinned sibling repos and applies the temporary
compatibility patches in `patches/`.

## Remaining External Tools

`protoc` and `risc0`/`r0vm` are not installed globally on PATH. The Nix build
pulls its own pinned dependency set, so do not install them globally unless a
specific non-Nix demo path requires it.

If a later demo script needs host-level RISC Zero tooling, install it in a
separate step and keep `RISC0_DEV_MODE=0` for recorded prize evidence.

## Local Sequencer Harness

The opt-in harness uses `logos-co/scaffold` to manage a standalone LEZ
sequencer:

```bash
./scripts/localnet-integration.sh --setup --prebuilt
```

It creates an isolated workspace under `.local/localnet-integration`, sets
`risc0_dev_mode = false`, starts localnet, and runs `agent_lez` wallet
health/query calls against the live sequencer. Omit `--setup` when scaffold has
already built its project-local `sequencer_service` and `wallet` binaries.

The script also bootstraps two host prerequisites when they are not already set:
`LOGOS_BLOCKCHAIN_CIRCUITS` points at a project-local placeholder so scaffold can
download the pinned circuits release, and `BINDGEN_EXTRA_CLANG_ARGS` is derived
from `gcc -print-file-name=include` so LEZ dependency bindgen builds can find
standard C headers. For source builds, `CARGO_BUILD_JOBS` defaults to at most
`4` to keep native RocksDB compilation inside typical laptop memory limits;
override it explicitly on larger build hosts.

Current scaffold pins may fail while building the optional SPel CLI because the
SPel dependency graph references an older LEZ tag without the `nssa` package.
The harness treats that as non-fatal only after the LEZ `sequencer_service` and
`wallet` binaries exist, then prepares the wallet home from LEZ's debug wallet
config and continues the wallet/sequencer smoke.

## Basecamp Owner App Harness

The owner-channel helper uses `logos-co/scaffold` Basecamp commands:

```bash
./scripts/basecamp-owner-channel.sh --setup
```

It creates `.local/basecamp-owner-channel`, captures the local runtime module
LGXs, and installs them into scaffold's `alice`/`bob` Basecamp profiles. Use
`--capture-only` to validate the module table without building Basecamp, and
`--launch` only when you want to open the app; the recorded demo remains a later
step.

When the Basecamp GUI build is too large for the local machine, validate the
install layer separately:

```bash
./scripts/basecamp-profile-install-smoke.sh
```

This uses the real `lgpm` CLI to install `delivery_module`, `storage_module`,
`chat_module`, `logos_execution_zone`, and `logos_agent` into scaffold-shaped
Basecamp `alice`/`bob` profile directories. It does not build or launch the GUI.

## Delivery Preset Smoke

Use the Delivery smoke harness to test the module-first messaging path before
running the full agent:

```bash
./scripts/delivery-smoke.sh --preset logos.dev
./scripts/delivery-smoke.sh --preset logos.test --api-only
```

The default run starts two isolated `logoscore` daemons, creates a
`delivery_module` node in each, subscribes one instance to
`/logos-agent/1/smoke-json/json`, sends from the other, and waits for
`messageReceived`. `--api-only` validates `createNode`, `start`, `subscribe`,
and `send` when network propagation is not expected to complete in the local
environment.
