#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
FIXTURE_DIR="${PROGRAM_FIXTURE_DIR:-$ROOT/.local/v02-program-fixture}"
FIXTURE="$FIXTURE_DIR/hello_world.bin"
EXPECTED_COMMIT="a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a"
EXPECTED_SHA256="707e8f1a3f86b2e44fcc2247aa5b97f2d59932d2ad1c34a9dfc9bfec6e600c52"

LOGOS_EXECUTION_ZONE="${LOGOS_EXECUTION_ZONE:-}"
if [ -z "$LOGOS_EXECUTION_ZONE" ]; then
  for candidate in "$WORKSPACE/logos-execution-zone" "$ROOT/.local/v02-workspace/logos-execution-zone"; do
    if [ -d "$candidate/.git" ] \
      && [ "$(git -C "$candidate" rev-parse HEAD 2>/dev/null || true)" = "$EXPECTED_COMMIT" ]; then
      LOGOS_EXECUTION_ZONE="$candidate"
      break
    fi
  done
fi
LOGOS_EXECUTION_ZONE="${LOGOS_EXECUTION_ZONE:-$WORKSPACE/logos-execution-zone}"
BUILT_FIXTURE="$LOGOS_EXECUTION_ZONE/target/riscv32im-risc0-zkvm-elf/docker/hello_world.bin"

verify_fixture() {
  local path="$1"
  [ -f "$path" ] || return 1
  printf '%s  %s\n' "$EXPECTED_SHA256" "$path" | sha256sum --check --status
}

if verify_fixture "$FIXTURE"; then
  printf '%s\n' "$FIXTURE"
  exit 0
fi

if [ ! -d "$LOGOS_EXECUTION_ZONE/.git" ]; then
  echo "pinned Logos Execution Zone checkout is missing: $LOGOS_EXECUTION_ZONE" >&2
  exit 1
fi
actual_commit="$(git -C "$LOGOS_EXECUTION_ZONE" rev-parse HEAD)"
if [ "$actual_commit" != "$EXPECTED_COMMIT" ]; then
  echo "Logos Execution Zone must be at v0.2 commit $EXPECTED_COMMIT; found $actual_commit" >&2
  exit 1
fi

risczero_version="$(cargo risczero --version 2>&1 || true)"
if [ "$risczero_version" != "cargo-risczero 3.0.5" ]; then
  echo "cargo-risczero 3.0.5 is required; found: ${risczero_version:-missing}" >&2
  exit 1
fi

(cd "$LOGOS_EXECUTION_ZONE" && \
  cargo risczero build \
    --manifest-path examples/program_deployment/methods/guest/Cargo.toml >&2)

if ! verify_fixture "$BUILT_FIXTURE"; then
  echo "built v0.2 hello_world fixture is missing or has an unexpected SHA-256: $BUILT_FIXTURE" >&2
  exit 1
fi

mkdir -p "$FIXTURE_DIR"
install -m 0644 "$BUILT_FIXTURE" "$FIXTURE"
printf '%s\n' "$FIXTURE"
