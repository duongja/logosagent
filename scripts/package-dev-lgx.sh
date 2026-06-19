#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
MODULE_DIR="${MODULE_DIR:-$ROOT/.local/live-modules/logos_agent}"
OUT_DIR="${OUT_DIR:-$ROOT/.local/artifacts/lgx-dev}"
RESULT_LINK="${RESULT_LINK:-$ROOT/result}"
LGX_BIN="${LGX_BIN:-}"
PKG_NAME="${PKG_NAME:-logos-logos_agent-module-lib}"
VARIANT="${VARIANT:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/package-dev-lgx.sh [--module-dir PATH] [--out-dir PATH] [--no-result-link]

Creates a dev-style LGX package from the already installed local
.local/live-modules/logos_agent payload. This avoids rebuilding the full Logos
dependency graph when the module payload has already been built and tested.

The resulting package has the same shape as the Logos Nix dev LGX output:
  result/logos-logos_agent-module-lib.lgx

Options:
  --module-dir PATH   Installed logos_agent module directory.
  --out-dir PATH      Output directory for the LGX package.
  --no-result-link    Do not update ./result to point at the output directory.
  -h, --help          Show this help.

Environment:
  LGX_BIN             Path to the lgx executable. Auto-detected when possible.
  VARIANT             Variant name. Defaults to module_dir/variant.
USAGE
}

UPDATE_RESULT=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --module-dir)
      MODULE_DIR="${2:-}"
      shift
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift
      ;;
    --no-result-link)
      UPDATE_RESULT=0
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

if [ -z "$LGX_BIN" ]; then
  if command -v lgx >/dev/null 2>&1; then
    LGX_BIN="$(command -v lgx)"
  else
    LGX_BIN="$(find /nix/store -maxdepth 3 -type f -path '*/bin/lgx' 2>/dev/null | sort | tail -n 1 || true)"
  fi
fi

if [ -z "$LGX_BIN" ] || [ ! -x "$LGX_BIN" ]; then
  cat >&2 <<'EOF'
lgx binary not found.

Build it from the sibling logos-package checkout or pass LGX_BIN:
  nix build /home/agate/Projects/logos/logos-package#lgx
  LGX_BIN=/path/to/lgx scripts/package-dev-lgx.sh
EOF
  exit 1
fi

if [ ! -d "$MODULE_DIR" ]; then
  echo "module directory not found: $MODULE_DIR" >&2
  exit 1
fi

if [ ! -f "$MODULE_DIR/logos_agent_plugin.so" ]; then
  echo "module plugin not found: $MODULE_DIR/logos_agent_plugin.so" >&2
  exit 1
fi

if [ -z "$VARIANT" ]; then
  if [ ! -f "$MODULE_DIR/variant" ]; then
    echo "variant file not found: $MODULE_DIR/variant" >&2
    exit 1
  fi
  VARIANT="$(cat "$MODULE_DIR/variant")"
fi

if [ ! -f "$ROOT/metadata.json" ]; then
  echo "metadata.json not found in repo root" >&2
  exit 1
fi

if [ ! -f "$WORKSPACE/nix-bundle-lgx/bundle.sh" ]; then
  echo "nix-bundle-lgx bundle helper not found: $WORKSPACE/nix-bundle-lgx/bundle.sh" >&2
  exit 1
fi

work="$(mktemp -d "$ROOT/.local/lgx-package-work.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src/lib" "$OUT_DIR"
cp "$MODULE_DIR/logos_agent_plugin.so" "$work/src/lib/"

(
  cd "$work"
  PATH="$(dirname "$LGX_BIN"):$PATH" \
  SRC_DRV="$work/src" \
  VARIANT="$VARIANT" \
  PACKAGE_NAME="$PKG_NAME" \
  METADATA_FILE="$ROOT/metadata.json" \
  LIB_EXT=".so" \
  MODULE_SRC="$ROOT" \
  EXTRA_DIRS="" \
    bash "$WORKSPACE/nix-bundle-lgx/bundle.sh"
)

cp "$work/$PKG_NAME.lgx" "$OUT_DIR/$PKG_NAME.lgx"
"$LGX_BIN" verify "$OUT_DIR/$PKG_NAME.lgx"

if [ "$UPDATE_RESULT" -eq 1 ]; then
  ln -sfn "${OUT_DIR#$ROOT/}" "$RESULT_LINK"
fi

cat <<EOF
LGX package created:
  $OUT_DIR/$PKG_NAME.lgx

Variant:
  $VARIANT

Result link:
  $RESULT_LINK
EOF
