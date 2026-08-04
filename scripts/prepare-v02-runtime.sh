#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules-v02}"
PACKAGES_DIR="${PACKAGES_DIR:-$ROOT/.local/packages-v02}"
LGPD="${LGPD:-lgpd}"
LGPM="${LGPM:-lgpm}"
LOGOSCORE="${LOGOSCORE:-logoscore}"

if ! command -v nix >/dev/null 2>&1; then
  echo "missing required v0.2 tool: nix" >&2
  echo "Install Nix using https://docs.logos.co/run-a-node" >&2
  exit 1
fi

resolve_tool() {
  local requested="$1"
  local name="$2"
  local source="$3"
  local expected_commit="$4"
  local out_link="$ROOT/.local/tools-v02/$name"
  local cached="$ROOT/.local/official-v02/bin/$name"

  if command -v "$requested" >/dev/null 2>&1; then
    local candidate
    candidate="$(command -v "$requested")"
    if "$candidate" --version 2>&1 | grep -Fq "commit: $expected_commit"; then
      echo "$candidate"
      return
    fi
    echo "ignoring non-v0.2 $name on PATH: $candidate" >&2
  fi
  if [ -x "$cached" ] && "$cached" --version 2>&1 | grep -Fq "commit: $expected_commit"; then
    echo "$cached"
    return
  fi

  mkdir -p "$(dirname "$out_link")"
  nix build --no-write-lock-file "$source#cli" --out-link "$out_link" >&2
  if [ ! -x "$out_link/bin/$name" ]; then
    echo "pinned $name build did not produce bin/$name" >&2
    exit 1
  fi
  echo "$out_link/bin/$name"
}

verify_tool() {
  local tool="$1"
  local name="$2"
  local version="$3"
  local commit="$4"
  local output

  output="$("$tool" --version 2>&1)"
  if ! grep -Fq "$name version $version" <<<"$output" || ! grep -Fq "commit: $commit" <<<"$output"; then
    cat >&2 <<EOF
$name does not match the locked Testnet v0.2 tool revision.
Expected version: $version
Expected commit:  $commit
Resolved path:    $tool
Reported version:
$output
EOF
    exit 1
  fi
}

LGPD="$(resolve_tool "$LGPD" lgpd github:logos-co/logos-package-downloader/cf814220bfd78a0e07e042a8d29fae026bf652fd cf814220bfd78a0e07e042a8d29fae026bf652fd)"
LGPM="$(resolve_tool "$LGPM" lgpm github:logos-co/logos-package-manager/7a1f1cf35b22dc1a3407d6b5cafce333321be584 7a1f1cf35b22dc1a3407d6b5cafce333321be584)"
LOGOSCORE="$(resolve_tool "$LOGOSCORE" logoscore github:logos-co/logos-logoscore-cli/797b98a02bb009c477cfe82a7bb75f5fc6cb75d7 797b98a02bb009c477cfe82a7bb75f5fc6cb75d7)"
verify_tool "$LGPD" lgpd 0.2.0 cf814220bfd78a0e07e042a8d29fae026bf652fd
verify_tool "$LGPM" lgpm 0.2.0 7a1f1cf35b22dc1a3407d6b5cafce333321be584
verify_tool "$LOGOSCORE" logoscore 0.2.0 797b98a02bb009c477cfe82a7bb75f5fc6cb75d7
mkdir -p "$ROOT/.local/tools-v02"
printf '%s\n' "$LOGOSCORE" > "$ROOT/.local/tools-v02/logoscore.path"

mkdir -p "$MODULES_DIR" "$PACKAGES_DIR"

download_install() {
  local name="$1"
  local version="$2"
  "$LGPD" download "$name" --version "$version" --output "$PACKAGES_DIR"
  local package
  package="$(find "$PACKAGES_DIR" -maxdepth 1 -type f -name "${name}*.lgx" | sort | tail -1)"
  if [ -z "$package" ]; then
    echo "lgpd did not produce an LGX for $name $version" >&2
    exit 1
  fi
  "$LGPM" --modules-dir "$MODULES_DIR" install --file "$package"
}

download_install delivery_module 0.1.3
download_install storage_module 2.0.1
download_install chat_module 0.2.1

# The public v0.2 sequencer exposes the LEZ v0.2.0 RPC surface. Build the
# matching portable production variant instead of the moving catalog or the
# Nix-store-only `lgx` development variant.
LEZ_CORE_REF="92dd9e25bcc6be04f841671e8da7b94bd2449f39"
LEZ_RESULT="$ROOT/.local/lez-core-v020-portable-result"
AGENT_RESULT="$ROOT/.local/logos-agent-v020-portable-result"
nix build --no-write-lock-file \
  "github:logos-blockchain/logos-execution-zone-module/$LEZ_CORE_REF#lgx-portable" \
  --out-link "$LEZ_RESULT"
LEZ_PACKAGE="$(find -L "$LEZ_RESULT" -maxdepth 1 -type f -name '*.lgx' | head -1)"
if [ -z "$LEZ_PACKAGE" ]; then
  echo "official LEZ Core v0.2.0 build did not produce an LGX" >&2
  exit 1
fi
cp --remove-destination "$LEZ_PACKAGE" "$PACKAGES_DIR/lez_core-0.2.0.lgx"
"$LGPM" --modules-dir "$MODULES_DIR" --allow-unsigned install \
  --file "$PACKAGES_DIR/lez_core-0.2.0.lgx"

(cd "$ROOT" && nix build --impure --no-write-lock-file --recreate-lock-file \
  .#lgx-portable -L --out-link "$AGENT_RESULT")
"$LGPM" --modules-dir "$MODULES_DIR" --allow-unsigned install \
  --file "$AGENT_RESULT/logos-logos_agent-module-lib.lgx"
MODULES_DIR="$MODULES_DIR" "$ROOT/scripts/check-runtime-modules.sh"

python3 - "$ROOT" "$MODULES_DIR" "$PACKAGES_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys

root, modules, packages = map(pathlib.Path, sys.argv[1:])
artifacts = []
agent_result = root / ".local" / "logos-agent-v020-portable-result"
for path in sorted(packages.glob("*.lgx")) + sorted(agent_result.glob("*.lgx")):
    artifacts.append({
        "path": str(path.resolve()),
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    })
lock = json.loads((root / "dependencies-v0.2.json").read_text())
lock["artifacts"] = artifacts
out = root / ".local" / "dependencies-v0.2.resolved.json"
out.write_text(json.dumps(lock, indent=2) + "\n")
print(out)
PY
