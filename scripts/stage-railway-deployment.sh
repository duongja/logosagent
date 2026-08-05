#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="${MODULES_DIR:-$ROOT/.local/live-modules-v02}"
LOGOSCORE="${LOGOSCORE:-$ROOT/.local/official-v02/bin/logoscore}"
OUT_DIR="${OUT_DIR:-$ROOT/.local/railway-deployment}"

usage() {
  cat <<'USAGE'
Usage: scripts/stage-railway-deployment.sh [--out-dir PATH]

Creates an ignored Railway upload directory from the locally verified portable
Testnet v0.2 runtime. It does not create or deploy a Railway project.

Environment overrides: MODULES_DIR, LOGOSCORE, OUT_DIR.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ ! -x "$LOGOSCORE" ]; then
  echo "missing portable Logos Core: $LOGOSCORE" >&2
  echo "Run ./scripts/prepare-v02-runtime.sh first." >&2
  exit 1
fi

MODULES_DIR="$(cd "$MODULES_DIR" && pwd)"
OUT_DIR="$(mkdir -p "$(dirname "$OUT_DIR")" && cd "$(dirname "$OUT_DIR")" && pwd)/$(basename "$OUT_DIR")"
work="$(mktemp -d "$ROOT/.local/railway-stage.XXXXXX")"
trap 'rm -rf "$work"' EXIT

MODULES_DIR="$MODULES_DIR" "$ROOT/scripts/check-runtime-modules.sh"

python3 - "$MODULES_DIR" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected = {
    "delivery_module": "0.1.3",
    "storage_module": "2.0.1",
    "chat_module": "0.2.1",
    "lez_core": "0.2.0",
    "logos_agent": "0.2.0",
}
actual = {
    name: json.loads((root / name / "manifest.json").read_text())["version"]
    for name in expected
}
if actual != expected:
    raise SystemExit(f"refusing to stage unexpected module versions: {actual}")
PY

mkdir -p "$work/payload/runtime" "$work/payload/modules" "$work/extract"
(
  cd "$work/extract"
  "$LOGOSCORE" --appimage-extract >/dev/null
)
mv "$work/extract/squashfs-root" "$work/payload/runtime/logoscore"
cp -a "$MODULES_DIR"/. "$work/payload/modules/"

mkdir -p "$OUT_DIR"
cp "$ROOT/deploy/railway/Dockerfile" "$OUT_DIR/Dockerfile"
cp "$ROOT/deploy/railway/entrypoint.py" "$OUT_DIR/entrypoint.py"
printf '*\n!Dockerfile\n!entrypoint.py\n!runtime.tar.gz\n' >"$OUT_DIR/.dockerignore"
tar -C "$work/payload" -czf "$OUT_DIR/runtime.tar.gz.new" runtime modules
mv "$OUT_DIR/runtime.tar.gz.new" "$OUT_DIR/runtime.tar.gz"
rm -f "$OUT_DIR/runtime.tar.zst" "$OUT_DIR/runtime.tar.zst.sha256"
sha256sum "$OUT_DIR/runtime.tar.gz" >"$OUT_DIR/runtime.tar.gz.sha256"

python3 - "$OUT_DIR" "$LOGOSCORE" "$MODULES_DIR" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

out, logoscore, modules = map(pathlib.Path, sys.argv[1:])
archive = out / "runtime.tar.gz"
manifest = {
    "schema": "logos.agent.railway-stage.v1",
    "network": "logos-testnet-v0.2",
    "delivery_preset": "logos.test",
    "archive": {
        "bytes": archive.stat().st_size,
        "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    },
    "logoscore_version": subprocess.check_output([str(logoscore), "--version"], text=True).splitlines()[:2],
    "modules": {},
}
for path in sorted(modules.glob("*/manifest.json")):
    data = json.loads(path.read_text())
    manifest["modules"][data["name"]] = data["version"]
(out / "stage-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
PY

echo "Railway deployment context: $OUT_DIR"
