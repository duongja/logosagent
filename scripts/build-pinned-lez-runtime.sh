#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"

SCaffold_LEZ_REV_DEFAULT="35d8df0d031315219f94d1546ceb862b0e5b208f"
LEZ_REV="${LEZ_REV:-$SCaffold_LEZ_REV_DEFAULT}"
PINNED_LEZ_REPO="${PINNED_LEZ_REPO:-$ROOT/.local/localnet-integration/cache/repos/lez/$LEZ_REV}"
LEZ_MODULE_SRC="${LEZ_MODULE_SRC:-$WORKSPACE/logos-execution-zone-module}"
MODULE_BUILDER_ROOT="${LOGOS_MODULE_BUILDER_ROOT:-$WORKSPACE/logos-module-builder}"
LOGOS_CPP_SDK_ROOT="${LOGOS_CPP_SDK_ROOT:-$ROOT/.local/sdk-shims/logos-cpp-sdk-installed-layout}"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules}"
SCRATCH="${SCRATCH:-$ROOT/.local/direct-src/logos_execution_zone-pinned-ffi}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.local/direct-build/logos_execution_zone-pinned-ffi}"
CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-1}"
INSTALL=1
RUN_CHECK=1

usage() {
  cat <<'USAGE'
Usage: scripts/build-pinned-lez-runtime.sh [options]

Builds a Logos Execution Zone runtime module against the LEZ revision pinned by
logos-co/scaffold localnet, then installs it into .local/live-modules.

This is the compatibility path used by the local LP-0008 proof harness. The
scaffold localnet currently pins LEZ to an older wallet FFI generation than the
normal logos_execution_zone flake input. Without this alignment, wallet.send and
paid A2A smokes can fail even though the agent code is correct.

Options:
  --no-install       Build only; do not replace .local/live-modules.
  --skip-check       Do not run scripts/check-runtime-modules.sh after install.
  --modules-dir P    Runtime module install dir. Default: .local/live-modules.
  --pinned-lez P     Pinned LEZ checkout. Default: localnet cache checkout.
  --lez-module-src P Logos execution-zone module source checkout.
  --scratch P        Scratch source dir. Default: .local/direct-src/...
  --build-dir P      CMake build dir. Default: .local/direct-build/...
  -h, --help         Show this help.

Run this through the stable runner on this laptop:
  ./scripts/stable-test-runner.sh --jobs 1 --nix-cores 1 -- ./scripts/build-pinned-lez-runtime.sh
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-install) INSTALL=0 ;;
    --skip-check) RUN_CHECK=0 ;;
    --modules-dir)
      MODULES_DIR="${2:-}"
      shift
      ;;
    --pinned-lez)
      PINNED_LEZ_REPO="${2:-}"
      shift
      ;;
    --lez-module-src)
      LEZ_MODULE_SRC="${2:-}"
      shift
      ;;
    --scratch)
      SCRATCH="${2:-}"
      shift
      ;;
    --build-dir)
      BUILD_DIR="${2:-}"
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

die() {
  echo "error: $*" >&2
  exit 1
}

first_existing_dir() {
  local path
  for path in "$@"; do
    if [ -n "$path" ] && [ -d "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

first_glob_dir() {
  local pattern="$1"
  local path
  for path in $pattern; do
    if [ -d "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

require_file() {
  [ -f "$1" ] || die "missing required file: $1"
}

require_dir() {
  [ -d "$1" ] || die "missing required directory: $1"
}

require_dir "$PINNED_LEZ_REPO"
require_dir "$LEZ_MODULE_SRC"
require_file "$LEZ_MODULE_SRC/CMakeLists.txt"
require_file "$LEZ_MODULE_SRC/src/logos_execution_zone_wallet_module.cpp"
require_file "$LEZ_MODULE_SRC/src/logos_execution_zone_wallet_module.h"
require_file "$LEZ_MODULE_SRC/src/i_logos_execution_zone_wallet_module.h"
require_file "$ROOT/patches/logos-execution-zone-module-pinned-localnet-ffi.patch"
require_dir "$MODULE_BUILDER_ROOT/cmake"
require_dir "$LOGOS_CPP_SDK_ROOT"

if ! grep -q "import_public_account" "$LEZ_MODULE_SRC/src/logos_execution_zone_wallet_module.h"; then
  die "$LEZ_MODULE_SRC is missing import_public_account; run scripts/bootstrap-workspace.sh first"
fi

if ! grep -q "jsonToFfiRecipientIdentifier" "$LEZ_MODULE_SRC/src/logos_execution_zone_wallet_module.cpp"; then
  die "$LEZ_MODULE_SRC is not patched for the current wallet wrapper; run scripts/bootstrap-workspace.sh first"
fi

qtbase_root="$(first_existing_dir "${QTBASE_ROOT:-}" "$(first_glob_dir '/nix/store/*-qtbase-6.9.2' || true)" "$(first_glob_dir '/nix/store/*-qtbase-*' || true)")" \
  || die "could not find Qt base in /nix/store; set QTBASE_ROOT"
qtremote_root="$(first_existing_dir "${QTREMOTEOBJECTS_ROOT:-}" "$(first_glob_dir '/nix/store/*-qtremoteobjects-6.9.2' || true)" "$(first_glob_dir '/nix/store/*-qtremoteobjects-*' || true)")" \
  || die "could not find Qt RemoteObjects in /nix/store; set QTREMOTEOBJECTS_ROOT"
boost_dev_root="$(first_existing_dir "${BOOST_DEV_ROOT:-}" "$(first_glob_dir '/nix/store/*-boost-1.87.0-dev' || true)" "$(first_glob_dir '/nix/store/*-boost-*-dev' || true)")" \
  || die "could not find Boost dev package in /nix/store; set BOOST_DEV_ROOT"
boost_lib_root="$(first_existing_dir "${BOOST_LIB_ROOT:-}" "$(first_glob_dir '/nix/store/*-boost-1.87.0' || true)" "$(first_glob_dir '/nix/store/*-boost-*' || true)")" \
  || die "could not find Boost runtime package in /nix/store; set BOOST_LIB_ROOT"
openssl_dev_root="$(first_existing_dir "${OPENSSL_DEV_ROOT:-}" "$(first_glob_dir '/nix/store/*-openssl-3.5.1-dev' || true)" "$(first_glob_dir '/nix/store/*-openssl-*-dev' || true)")" \
  || die "could not find OpenSSL dev package in /nix/store; set OPENSSL_DEV_ROOT"
nlohmann_root="$(first_existing_dir "${NLOHMANN_JSON_ROOT:-}" "$(first_glob_dir '/nix/store/*-nlohmann_json-3.11.3' || true)" "$(first_glob_dir '/nix/store/*-nlohmann_json-*' || true)")" \
  || die "could not find nlohmann_json package in /nix/store; set NLOHMANN_JSON_ROOT"
logos_module_root="$(first_existing_dir "${LOGOS_MODULE_ROOT:-}" "$(first_glob_dir '/nix/store/*-logos-module-0.1.0' || true)" "$(first_glob_dir '/nix/store/*-logos-module-*' || true)")" \
  || die "could not find logos-module package in /nix/store; set LOGOS_MODULE_ROOT"

openssl_lib_root="${OPENSSL_LIB_ROOT:-}"
if [ -z "$openssl_lib_root" ] && [ -f "$openssl_dev_root/nix-support/propagated-build-inputs" ]; then
  openssl_lib_root="$(
    tr ' ' '\n' < "$openssl_dev_root/nix-support/propagated-build-inputs" |
      grep -E '/openssl-[0-9.]+$' |
      head -1 || true
  )"
fi
openssl_lib_root="$(first_existing_dir "$openssl_lib_root" "$(first_glob_dir '/nix/store/*-openssl-3.5.1' || true)" "$(first_glob_dir '/nix/store/*-openssl-*' || true)")" \
  || die "could not find OpenSSL runtime package in /nix/store; set OPENSSL_LIB_ROOT"

gcc_lib_root="$(first_existing_dir "${GCC_LIB_ROOT:-}" "$(first_glob_dir '/nix/store/*-gcc-14.3.0-lib' || true)" "$(first_glob_dir '/nix/store/*-gcc-*-lib' || true)")" \
  || die "could not find GCC runtime package in /nix/store; set GCC_LIB_ROOT"
glibc_root="$(first_existing_dir "${GLIBC_ROOT:-}" "$(first_glob_dir '/nix/store/*-glibc-2.40-66' || true)" "$(first_glob_dir '/nix/store/*-glibc-*' || true)")" \
  || die "could not find glibc runtime package in /nix/store; set GLIBC_ROOT"

echo "pinned LEZ repo: $PINNED_LEZ_REPO"
echo "LEZ module source: $LEZ_MODULE_SRC"
echo "modules dir: $MODULES_DIR"
echo "building wallet-ffi with CARGO_BUILD_JOBS=$CARGO_BUILD_JOBS"

(
  cd "$PINNED_LEZ_REPO"
  CARGO_BUILD_JOBS="$CARGO_BUILD_JOBS" cargo build -p wallet-ffi --release --no-default-features
)

wallet_ffi="$PINNED_LEZ_REPO/target/release/libwallet_ffi.so"
require_file "$wallet_ffi"

rm -rf "$SCRATCH" "$BUILD_DIR"
mkdir -p "$SCRATCH" "$BUILD_DIR"
cp -a "$LEZ_MODULE_SRC"/. "$SCRATCH"/
rm -rf "$SCRATCH/.git"
rm -rf "$SCRATCH/lib"
mkdir -p "$SCRATCH/lib"
ln -s "$wallet_ffi" "$SCRATCH/lib/libwallet_ffi.so"

(
  cd "$SCRATCH"
  patch -p1 < "$ROOT/patches/logos-execution-zone-module-pinned-localnet-ffi.patch"
)

prefix_path="$qtbase_root;$qtremote_root;$LOGOS_CPP_SDK_ROOT;$boost_dev_root;$boost_lib_root;$openssl_dev_root;$nlohmann_root"
include_path="$PINNED_LEZ_REPO/wallet-ffi:$nlohmann_root/include"

echo "configuring pinned LEZ module wrapper"
CPLUS_INCLUDE_PATH="$include_path" \
LOGOS_MODULE_BUILDER_ROOT="$MODULE_BUILDER_ROOT" \
cmake -S "$SCRATCH" -B "$BUILD_DIR" \
  -DLOGOS_CPP_SDK_ROOT="$LOGOS_CPP_SDK_ROOT" \
  -DLOGOS_MODULE_ROOT="$logos_module_root" \
  -DQt6_DIR="$qtbase_root/lib/cmake/Qt6" \
  -DQt6Core_DIR="$qtbase_root/lib/cmake/Qt6Core" \
  -DQt6Network_DIR="$qtbase_root/lib/cmake/Qt6Network" \
  -DQt6RemoteObjects_DIR="$qtremote_root/lib/cmake/Qt6RemoteObjects" \
  -DQt6RemoteObjectsTools_DIR="$qtremote_root/lib/cmake/Qt6RemoteObjectsTools" \
  -DCMAKE_PREFIX_PATH="$prefix_path"

echo "building pinned LEZ module wrapper with CMAKE_BUILD_PARALLEL_LEVEL=$CMAKE_BUILD_PARALLEL_LEVEL"
CPLUS_INCLUDE_PATH="$include_path" cmake --build "$BUILD_DIR" --parallel "$CMAKE_BUILD_PARALLEL_LEVEL"

built_plugin="$BUILD_DIR/modules/logos_execution_zone_plugin.so"
built_ffi="$BUILD_DIR/modules/libwallet_ffi.so"
require_file "$built_plugin"
require_file "$built_ffi"

if [ "$INSTALL" -eq 0 ]; then
  echo "build complete: $BUILD_DIR/modules"
  exit 0
fi

module_dir="$MODULES_DIR/logos_execution_zone"
backup_root="$ROOT/.local/live-modules-backup/$(date -u +%Y%m%dT%H%M%SZ)-lez-pinned-ffi"
mkdir -p "$MODULES_DIR" "$module_dir"

if [ -e "$module_dir" ] || [ -L "$module_dir" ]; then
  mkdir -p "$backup_root"
  cp -a "$module_dir" "$backup_root/logos_execution_zone"
fi

chmod u+w \
  "$module_dir/logos_execution_zone_plugin.so" \
  "$module_dir/libwallet_ffi.so" \
  "$module_dir/manifest.json" \
  "$module_dir/variant" 2>/dev/null || true

cp "$built_plugin" "$module_dir/logos_execution_zone_plugin.so"
cp "$wallet_ffi" "$module_dir/libwallet_ffi.so"

if [ -f "$module_dir/manifest.json" ]; then
  :
elif [ -f "$ROOT/.local/module-builds/logos_execution_zone-install/modules/logos_execution_zone/manifest.json" ]; then
  cp "$ROOT/.local/module-builds/logos_execution_zone-install/modules/logos_execution_zone/manifest.json" "$module_dir/manifest.json"
else
  python3 - "$module_dir/manifest.json" <<'PY'
import json
import sys
manifest = {
    "author": "Logos Blockchain Team",
    "category": "blockchain",
    "dependencies": [],
    "description": "Logos Execution Zone Module for Logos Core",
    "icon": "",
    "main": {"linux-amd64-dev": "logos_execution_zone_plugin.so"},
    "manifestVersion": "0.3.0",
    "name": "logos_execution_zone",
    "type": "core",
    "version": "1.0.0",
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
fi

if [ ! -f "$module_dir/variant" ]; then
  printf 'linux-amd64-dev' > "$module_dir/variant"
fi

rpath="\$ORIGIN:$boost_lib_root/lib:$openssl_lib_root/lib:$qtbase_root/lib:$qtremote_root/lib:$glibc_root/lib:$gcc_lib_root/lib"
patchelf_bin="${PATCHELF:-$(command -v patchelf || true)}"
if [ -z "$patchelf_bin" ]; then
  patchelf_bin="$(first_glob_dir '/nix/store/*-patchelf-*/bin' || true)/patchelf"
fi
if [ -x "$patchelf_bin" ]; then
  "$patchelf_bin" --set-rpath "$rpath" "$module_dir/logos_execution_zone_plugin.so"
else
  echo "warning: patchelf not found; plugin may not resolve Nix Qt/OpenSSL libs outside the build shell" >&2
fi

chmod 555 "$module_dir/logos_execution_zone_plugin.so" "$module_dir/libwallet_ffi.so"
chmod 444 "$module_dir/manifest.json" "$module_dir/variant" 2>/dev/null || true

echo "installed pinned LEZ runtime: $module_dir"
if [ -d "$backup_root/logos_execution_zone" ]; then
  echo "backup: $backup_root/logos_execution_zone"
fi

if [ "$RUN_CHECK" -eq 1 ]; then
  "$ROOT/scripts/check-runtime-modules.sh" --modules-dir "$MODULES_DIR"
fi
