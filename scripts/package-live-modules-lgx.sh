#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
OUT_ROOT="${OUT_ROOT:-$ROOT/.local/artifacts/basecamp-lgx}"
LGX_BIN="${LGX_BIN:-}"
TARGET_VARIANT="${VARIANT:-}"

modules=(
  delivery_module
  storage_module
  chat_module
  logos_execution_zone
  logos_agent
)

usage() {
  cat <<'USAGE'
Usage: scripts/package-live-modules-lgx.sh [--modules-dir PATH] [--out-root PATH] [--variant NAME]

Packages the currently installed local runtime modules into verified dev LGX
files suitable for scaffold/Basecamp profile installation.

Output layout:
  .local/artifacts/basecamp-lgx/<module>/<module>.lgx
  .local/artifacts/basecamp-lgx/<module>/metadata.json

The sibling metadata.json files let `logos-scaffold basecamp modules --path`
capture the correct module names for path-based LGX sources.

Environment:
  LGX_BIN       Path to lgx. Auto-detected from PATH or /nix/store.
  MODULES_DIR  Source module directory. Default: .local/live-modules.
  OUT_ROOT     Output root. Default: .local/artifacts/basecamp-lgx.
  VARIANT      Optional target variant override, e.g. linux-amd64 for AppImage.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --modules-dir)
      MODULES_DIR="${2:-}"
      shift
      ;;
    --out-root)
      OUT_ROOT="${2:-}"
      shift
      ;;
    --variant)
      TARGET_VARIANT="${2:-}"
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

MODULES_DIR="$(cd "$MODULES_DIR" && pwd)"
mkdir -p "$OUT_ROOT"
OUT_ROOT="$(cd "$OUT_ROOT" && pwd)"

if [ -z "$LGX_BIN" ]; then
  if command -v lgx >/dev/null 2>&1; then
    LGX_BIN="$(command -v lgx)"
  else
    LGX_BIN="$(find /nix/store -maxdepth 3 -type f -path '*/bin/lgx' 2>/dev/null | sort | tail -n 1 || true)"
  fi
fi

if [ -z "$LGX_BIN" ] || [ ! -x "$LGX_BIN" ]; then
  echo "lgx binary not found; pass LGX_BIN=/path/to/lgx" >&2
  exit 1
fi

if [ ! -f "$WORKSPACE/nix-bundle-lgx/bundle.sh" ]; then
  echo "nix-bundle-lgx bundle helper not found: $WORKSPACE/nix-bundle-lgx/bundle.sh" >&2
  exit 1
fi

package_module() {
  local module="$1"
  local module_dir="$MODULES_DIR/$module"
  local manifest="$module_dir/manifest.json"
  local variant_file="$module_dir/variant"
  local out_dir="$OUT_ROOT/$module"
  local work
  local variant
  local source_variant
  local main_file
  local main_base

  if [ ! -f "$manifest" ]; then
    echo "missing manifest for $module: $manifest" >&2
    return 1
  fi
  if [ ! -f "$variant_file" ]; then
    echo "missing variant file for $module: $variant_file" >&2
    return 1
  fi

  source_variant="$(cat "$variant_file")"
  if [ -n "$TARGET_VARIANT" ]; then
    variant="$TARGET_VARIANT"
  else
    variant="$source_variant"
  fi
  main_file="$(
    python3 - "$manifest" "$source_variant" <<'PY'
import json
import sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
variant = sys.argv[2]
main = manifest.get("main") or {}
if not isinstance(main, dict):
    raise SystemExit("manifest main is not a variant map")
if variant in main:
    print(main[variant])
elif main:
    print(next(iter(main.values())))
else:
    raise SystemExit("manifest main map is empty")
PY
  )"
  main_base="${main_file%.so}"

  work="$(mktemp -d "$ROOT/.local/lgx-package-work.$module.XXXXXX")"
  mkdir -p "$work/src/lib" "$out_dir"

  find "$module_dir" -maxdepth 1 \( -type f -o -type l \) \
    ! -name manifest.json \
    ! -name variant \
    -exec cp -L {} "$work/src/lib/" \;

  python3 - "$manifest" "$variant" "$main_base" "$out_dir/metadata.json" <<'PY'
import json
import sys

manifest_path, variant, main_base, out_path = sys.argv[1:5]
manifest = json.load(open(manifest_path, encoding="utf-8"))
metadata = {
    "name": manifest.get("name", ""),
    "version": manifest.get("version", "0"),
    "type": manifest.get("type", "core"),
    "category": manifest.get("category", ""),
    "description": manifest.get("description", ""),
    "author": manifest.get("author", ""),
    "icon": manifest.get("icon", ""),
    "main": main_base,
    "dependencies": manifest.get("dependencies", []),
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(metadata, f, indent=2)
    f.write("\n")
PY

  (
    cd "$work"
    PATH="$(dirname "$LGX_BIN"):$PATH" \
    SRC_DRV="$work/src" \
    VARIANT="$variant" \
    PACKAGE_NAME="$module" \
    METADATA_FILE="$out_dir/metadata.json" \
    LIB_EXT=".so" \
    MODULE_SRC="$ROOT" \
    EXTRA_DIRS="" \
      bash "$WORKSPACE/nix-bundle-lgx/bundle.sh"
  )

  cp "$work/$module.lgx" "$out_dir/$module.lgx"
  "$LGX_BIN" verify "$out_dir/$module.lgx" >/dev/null
  rm -rf "$work"

  echo "$out_dir/$module.lgx"
}

for module in "${modules[@]}"; do
  package_module "$module"
done

cat <<EOF
Basecamp LGX module set created under:
  $OUT_ROOT
EOF
