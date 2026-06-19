#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
RUN_ALL=0
SKIP_CHECK=0

usage() {
  cat <<'USAGE'
Usage: scripts/repair-live-modules.sh [options]

Rebuilds and refreshes broken entries under .local/live-modules. This is meant
for development machines after Nix garbage collection removed store paths that
installed module symlinks still point to.

Options:
  --all             Rebuild all required runtime modules, not only broken ones.
  --skip-precheck   Do not run check-runtime-modules before deciding what to fix.
  --modules-dir P   Installed runtime modules directory. Default: .local/live-modules.
  -h, --help        Show this help.

Run this through scripts/stable-test-runner.sh on AC power:
  ./scripts/stable-test-runner.sh -- ./scripts/repair-live-modules.sh
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all) RUN_ALL=1 ;;
    --skip-precheck) SKIP_CHECK=1 ;;
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

declare -A input_by_module=(
  [delivery_module]="delivery_module"
  [storage_module]="storage_module"
  [logos_execution_zone]="logos_execution_zone"
  [chat_module]="chat_module"
)

required_modules=(
  delivery_module
  storage_module
  logos_execution_zone
  chat_module
)

module_is_valid() {
  local module="$1"
  local module_dir="$MODULES_DIR/$module"
  local manifest="$module_dir/manifest.json"
  local plugin

  [ -d "$module_dir" ] || return 1
  [ -f "$manifest" ] || return 1

  plugin=$(
    python3 - "$manifest" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    manifest = json.load(f)
main = manifest.get("main") or {}
if not isinstance(main, dict) or not main:
    raise SystemExit(2)
print(next(iter(main.values())))
PY
  ) || return 1

  [ -e "$module_dir/$plugin" ] || return 1

  if command -v ldd >/dev/null 2>&1; then
    ldd "$module_dir/$plugin" >/dev/null 2>&1 || return 1
    ! ldd "$module_dir/$plugin" 2>/dev/null | grep -F "not found" >/dev/null
  fi
}

copy_module() {
  local build_result="$1"
  local module="$2"
  local built_module_dir="$build_result/modules/$module"
  local backup_root="$ROOT/.local/live-modules-backup/$(date -u +%Y%m%dT%H%M%SZ)"

  if [ ! -d "$built_module_dir" ]; then
    echo "built output did not contain modules/$module: $build_result" >&2
    return 1
  fi

  mkdir -p "$MODULES_DIR"
  if [ -e "$MODULES_DIR/$module" ] || [ -L "$MODULES_DIR/$module" ]; then
    mkdir -p "$backup_root"
    mv "$MODULES_DIR/$module" "$backup_root/$module"
  fi
  cp -a "$built_module_dir" "$MODULES_DIR/$module"
}

if [ "$SKIP_CHECK" -eq 0 ]; then
  "$ROOT/scripts/check-runtime-modules.sh" --modules-dir "$MODULES_DIR" || true
fi

to_repair=()
for module in "${required_modules[@]}"; do
  if [ "$RUN_ALL" -eq 1 ] || ! module_is_valid "$module"; then
    to_repair+=("$module")
  fi
done

if [ "${#to_repair[@]}" -eq 0 ]; then
  echo "runtime modules are already valid: $MODULES_DIR"
  exit 0
fi

echo "repairing modules: ${to_repair[*]}"
echo "modules_dir: $MODULES_DIR"

for module in "${to_repair[@]}"; do
  flake_input="${input_by_module[$module]}"

  out_link="$ROOT/.local/module-builds/$module-install"
  expr='let flake = builtins.getFlake "path:'"$ROOT"'"; system = builtins.currentSystem; in flake.inputs.'"$flake_input"'.packages.${system}.install'
  mkdir -p "$(dirname "$out_link")"
  echo "building $module from root flake input $flake_input"
  nix build --impure --expr "$expr" -L --max-jobs 1 --cores "${NIX_BUILD_CORES:-2}" --out-link "$out_link"
  copy_module "$out_link" "$module"
done

"$ROOT/scripts/check-runtime-modules.sh" --modules-dir "$MODULES_DIR"
