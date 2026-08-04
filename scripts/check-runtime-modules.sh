#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"

usage() {
  cat <<'USAGE'
Usage: scripts/check-runtime-modules.sh [--modules-dir PATH]

Validates that the locally installed Logos runtime modules are discoverable
enough for real integration smoke tests:
  - required module directories exist
  - manifest.json contains a module name and main entry
  - plugin symlinks resolve to real files
  - plugin shared libraries can be inspected with ldd
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --modules-dir)
      MODULES_DIR="${2:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

required_modules=(
  delivery_module
  storage_module
  chat_module
  lez_core
  logos_agent
)

missing=0

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) platform="linux-amd64" ;;
  Linux-aarch64|Linux-arm64) platform="linux-arm64" ;;
  Darwin-arm64) platform="darwin-arm64" ;;
  Darwin-x86_64) platform="darwin-amd64" ;;
  *)
    echo "unsupported runtime platform: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

if [ ! -d "$MODULES_DIR" ]; then
  echo "modules dir does not exist: $MODULES_DIR" >&2
  exit 1
fi

for module in "${required_modules[@]}"; do
  module_dir="$MODULES_DIR/$module"
  manifest="$module_dir/manifest.json"

  if [ ! -d "$module_dir" ]; then
    echo "missing module directory: $module_dir" >&2
    missing=1
    continue
  fi

  if [ ! -f "$manifest" ]; then
    echo "missing manifest: $manifest" >&2
    missing=1
    continue
  fi

  plugin=$(
    python3 - "$manifest" "$platform" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    manifest = json.load(f)
main = manifest.get("main") or {}
if not isinstance(main, dict) or sys.argv[2] not in main:
    raise SystemExit(2)
print(main[sys.argv[2]])
PY
  ) || {
    echo "manifest has no usable main entry: $manifest" >&2
    missing=1
    continue
  }

  plugin_path="$module_dir/$plugin"
  if [ ! -e "$plugin_path" ]; then
    echo "missing plugin target: $plugin_path" >&2
    if [ -L "$plugin_path" ]; then
      echo "  broken symlink -> $(readlink "$plugin_path")" >&2
    fi
    missing=1
    continue
  fi

  if command -v readelf >/dev/null 2>&1 && ! readelf -h "$plugin_path" >/dev/null 2>&1; then
    echo "plugin is not a valid ELF shared library: $plugin_path" >&2
    missing=1
    continue
  fi

  if command -v ldd >/dev/null 2>&1; then
    unresolved="$(ldd "$plugin_path" 2>/dev/null \
      | awk '/=> not found/ {print $1}' \
      | grep -Ev '^libQt6(Core|Network|RemoteObjects)\.so\.6$' || true)"
    if [ -n "$unresolved" ]; then
      echo "plugin has unresolved shared libraries: $plugin_path" >&2
      printf '  %s\n' $unresolved >&2
      missing=1
      continue
    fi
  fi

  echo "ok: $module -> $plugin_path"
done

exit "$missing"
