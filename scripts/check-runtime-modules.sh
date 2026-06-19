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
  logos_execution_zone
  logos_agent
)

missing=0

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
    python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    manifest = json.load(f)
main = manifest.get("main") or {}
if not isinstance(main, dict) or not main:
    raise SystemExit(2)
variant = next(iter(main))
print(main[variant])
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

  if command -v ldd >/dev/null 2>&1; then
    if ! ldd "$plugin_path" >/dev/null 2>&1; then
      echo "plugin dependency inspection failed: $plugin_path" >&2
      missing=1
      continue
    fi
    if ldd "$plugin_path" 2>/dev/null | grep -F "not found" >/dev/null; then
      echo "plugin has unresolved shared libraries: $plugin_path" >&2
      ldd "$plugin_path" 2>/dev/null | grep -F "not found" >&2 || true
      missing=1
      continue
    fi
  fi

  echo "ok: $module -> $plugin_path"
done

exit "$missing"
