#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
BASECAMP_ROOT="$ROOT/.local/basecamp-owner-channel"
SCAFFOLD_REPO="${SCAFFOLD_REPO:-$WORKSPACE/scaffold}"
SCAFFOLD_BIN="${SCAFFOLD_BIN:-}"
BASECAMP_SOURCE="${BASECAMP_SOURCE:-https://github.com/logos-co/logos-basecamp.git}"
BASECAMP_PIN="${BASECAMP_PIN:-63b35e8a0e826789ba15a46766df9fedc6794bc8}"
DEFAULT_LGX="$ROOT/result/logos-logos_agent-module-lib.lgx"
LGX="${LGX:-$DEFAULT_LGX}"
BASECAMP_LGX_ROOT="${BASECAMP_LGX_ROOT:-$ROOT/.local/artifacts/basecamp-lgx}"
RUN_SETUP=0
RUN_LAUNCH=0
CAPTURE_ONLY=0
PROFILE="${PROFILE:-alice}"

usage() {
  cat <<'USAGE'
Usage: scripts/basecamp-owner-channel.sh [--setup] [--capture-only] [--launch] [--profile alice|bob]

Prepares a reference Basecamp owner-channel environment:
  1. Creates an isolated scaffold project under .local/basecamp-owner-channel.
  2. Captures the built logos_agent .lgx as a Basecamp project module.
  3. Installs it into scaffold's alice/bob Basecamp profiles.
  4. Optionally launches one profile.

Options:
  --setup        Run `logos-scaffold basecamp setup` first.
  --capture-only
                 Capture module paths in scaffold.toml but skip profile install.
  --launch       Launch Basecamp after install.
  --profile      Profile to launch with --launch, default alice.

Environment:
  SCAFFOLD_BIN   Path to logos-scaffold binary.
  SCAFFOLD_REPO  Path to logos-co/scaffold checkout.
  BASECAMP_SOURCE
                 Basecamp repository. Default: https://github.com/logos-co/logos-basecamp.git.
  BASECAMP_PIN   Basecamp commit/tag for scaffold.toml. Default: tutorial-v3
                 commit 63b35e8a0e826789ba15a46766df9fedc6794bc8.
  LGX            Path to logos_agent .lgx artifact.
  BASECAMP_LGX_ROOT
                 Directory created by scripts/package-live-modules-lgx.sh.
  PROFILE        Profile used by --launch, default alice.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --setup) RUN_SETUP=1 ;;
    --capture-only) CAPTURE_ONLY=1 ;;
    --launch) RUN_LAUNCH=1 ;;
    --profile)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--profile requires a value" >&2
        exit 2
      fi
      PROFILE="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SCAFFOLD_BIN" ]; then
  if command -v logos-scaffold >/dev/null 2>&1; then
    SCAFFOLD_BIN="$(command -v logos-scaffold)"
  elif [ -x "$SCAFFOLD_REPO/target/release/logos-scaffold" ]; then
    SCAFFOLD_BIN="$SCAFFOLD_REPO/target/release/logos-scaffold"
  elif [ -x "$SCAFFOLD_REPO/target/debug/logos-scaffold" ]; then
    SCAFFOLD_BIN="$SCAFFOLD_REPO/target/debug/logos-scaffold"
  fi
fi

if [ -z "$SCAFFOLD_BIN" ] || [ ! -x "$SCAFFOLD_BIN" ]; then
  cat >&2 <<EOF
logos-scaffold binary not found.

Build or install it first, for example:
  cd "$SCAFFOLD_REPO"
  cargo build --release --bin logos-scaffold

Or pass:
  SCAFFOLD_BIN=/path/to/logos-scaffold $0
EOF
  exit 1
fi
SCAFFOLD_BIN="$(cd "$(dirname "$SCAFFOLD_BIN")" && pwd)/$(basename "$SCAFFOLD_BIN")"

if [ ! -f "$LGX" ]; then
  if [ "$LGX" = "$DEFAULT_LGX" ] && [ -x "$ROOT/scripts/package-dev-lgx.sh" ]; then
    "$ROOT/scripts/package-dev-lgx.sh"
  fi
fi

if [ ! -f "$LGX" ]; then
  cat >&2 <<EOF
logos_agent LGX not found at:
  $LGX

Build it first:
  nix build --impure .#lgx -L

Or package the already installed local dev module:
  ./scripts/package-dev-lgx.sh
EOF
  exit 1
fi

if [ -x "$ROOT/scripts/package-live-modules-lgx.sh" ]; then
  "$ROOT/scripts/package-live-modules-lgx.sh" --out-root "$BASECAMP_LGX_ROOT" >/dev/null
fi

module_paths=()
for module in delivery_module storage_module chat_module logos_execution_zone logos_agent; do
  path="$BASECAMP_LGX_ROOT/$module/$module.lgx"
  if [ ! -f "$path" ]; then
    echo "Basecamp module LGX not found: $path" >&2
    echo "Generate it with: ./scripts/package-live-modules-lgx.sh" >&2
    exit 1
  fi
  module_paths+=(--path "$path")
done

mkdir -p "$BASECAMP_ROOT"
cd "$BASECAMP_ROOT"

if [ ! -f scaffold.toml ]; then
  "$SCAFFOLD_BIN" init
fi

python3 - "$BASECAMP_SOURCE" "$BASECAMP_PIN" <<'PY'
import pathlib
import sys

path = pathlib.Path("scaffold.toml")
source = sys.argv[1]
pin = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()

out = []
in_basecamp = False
seen_basecamp = False
seen_source = False
seen_pin = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_basecamp:
            if not seen_source:
                out.append(f'source = "{source}"')
            if not seen_pin:
                out.append(f'pin = "{pin}"')
        in_basecamp = stripped == "[repos.basecamp]"
        seen_basecamp = seen_basecamp or in_basecamp
        seen_source = False
        seen_pin = False
        out.append(line)
        continue

    if in_basecamp and stripped.startswith("source"):
        out.append(f'source = "{source}"')
        seen_source = True
    elif in_basecamp and stripped.startswith("pin"):
        out.append(f'pin = "{pin}"')
        seen_pin = True
    else:
        out.append(line)

if in_basecamp:
    if not seen_source:
        out.append(f'source = "{source}"')
    if not seen_pin:
        out.append(f'pin = "{pin}"')

if not seen_basecamp:
    if out and out[-1].strip():
        out.append("")
    out.extend([
        "[repos.basecamp]",
        f'source = "{source}"',
        f'pin = "{pin}"',
        'build = "nix-flake"',
        'attr = "app"',
    ])

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

echo "Using Basecamp pin: $BASECAMP_PIN"

if [ "$RUN_SETUP" -eq 1 ]; then
  "$SCAFFOLD_BIN" basecamp setup
fi

"$SCAFFOLD_BIN" basecamp modules "${module_paths[@]}"

if [ "$CAPTURE_ONLY" -eq 1 ]; then
  cat <<EOF
Basecamp owner-channel module set captured.
Project: $BASECAMP_ROOT

Install later:
  cd "$BASECAMP_ROOT"
  "$SCAFFOLD_BIN" basecamp setup
  "$SCAFFOLD_BIN" basecamp install
EOF
  exit 0
fi

"$SCAFFOLD_BIN" basecamp install

cat <<EOF
Basecamp owner-channel profile prepared.
Project: $BASECAMP_ROOT
Installed module sources:
  ${module_paths[*]}

Launch manually:
  cd "$BASECAMP_ROOT"
  "$SCAFFOLD_BIN" basecamp launch $PROFILE
EOF

if [ "$RUN_LAUNCH" -eq 1 ]; then
  "$SCAFFOLD_BIN" basecamp launch "$PROFILE"
fi
