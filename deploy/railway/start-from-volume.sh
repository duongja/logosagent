#!/bin/sh
set -eu

archive="${LOGOS_RUNTIME_ARCHIVE:-/data/runtime.tar.gz}"
expected="${LOGOS_RUNTIME_SHA256:-}"
entrypoint="${LOGOS_ENTRYPOINT:-/data/entrypoint.py}"

export LOGOSCORE="${LOGOSCORE:-/opt/logos/runtime/logoscore/AppRun}"
export LOGOS_MODULES_DIR="${LOGOS_MODULES_DIR:-/opt/logos/modules}"
export LOGOS_DATA_DIR="${LOGOS_DATA_DIR:-/data}"
export HOME="${LOGOS_HOME:-/data/home}"
export LOGOS_NETWORK="${LOGOS_NETWORK:-logos-testnet-v0.2}"
export DELIVERY_PRESET="${DELIVERY_PRESET:-logos.test}"
export STORAGE_NETWORK="${STORAGE_NETWORK:-logos.test}"
export PYTHONUNBUFFERED=1

if [ ! -f "$archive" ]; then
  echo "missing pinned Logos runtime archive: $archive" >&2
  exit 1
fi
if [ -z "$expected" ]; then
  echo "LOGOS_RUNTIME_SHA256 is required" >&2
  exit 1
fi

actual="$(sha256sum "$archive" | cut -d ' ' -f 1)"
if [ "$actual" != "$expected" ]; then
  echo "Logos runtime archive checksum mismatch" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi

if [ ! -f "$entrypoint" ]; then
  echo "missing Logos Agent entrypoint: $entrypoint" >&2
  exit 1
fi

mkdir -p /opt/logos
tar -xzf "$archive" -C /opt/logos
exec python3 "$entrypoint"
