#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LGPM="${LGPM:-}"
LGX_ROOT="${LGX_ROOT:-$ROOT/.local/artifacts/basecamp-lgx}"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/basecamp-profile-install-smoke/latest}"
XDG_SUBPATH="${XDG_SUBPATH:-Logos/LogosBasecampDev}"
VARIANT="${VARIANT:-linux-amd64-dev}"
DIRECT_PROFILE=0

profiles=(alice bob)
modules=(
  delivery_module
  storage_module
  chat_module
  logos_execution_zone
  logos_agent
)

usage() {
  cat <<'USAGE'
Usage: scripts/basecamp-profile-install-smoke.sh [--run-root PATH] [--lgx-root PATH] [--lgpm PATH] [--direct-profile]

Installs the current Basecamp runtime LGX set into scaffold-compatible
Basecamp profile directories using the real Logos Package Manager CLI.

This intentionally does not build or launch the Basecamp GUI. It proves the
module package/install layer that Basecamp uses:
  .scaffold/basecamp/profiles/{alice,bob}/xdg-data/Logos/LogosBasecampDev/modules

Environment:
  LGPM       Path to lgpm. Auto-detected from PATH or /nix/store.
  LGX_ROOT   Directory containing <module>/<module>.lgx packages.
  RUN_ROOT   Output root. Default: .local/basecamp-profile-install-smoke/latest.
  VARIANT    Expected manifest main variant. Default: linux-amd64-dev.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-root)
      RUN_ROOT="${2:-}"
      shift
      ;;
    --lgx-root)
      LGX_ROOT="${2:-}"
      shift
      ;;
    --lgpm)
      LGPM="${2:-}"
      shift
      ;;
    --direct-profile)
      DIRECT_PROFILE=1
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

if [ -z "$LGPM" ]; then
  if command -v lgpm >/dev/null 2>&1; then
    LGPM="$(command -v lgpm)"
  else
    LGPM="$(find /nix/store -maxdepth 4 -type f -path '*/bin/lgpm' -executable 2>/dev/null | sort | tail -n 1 || true)"
  fi
fi

if [ -z "$LGPM" ] || [ ! -x "$LGPM" ]; then
  echo "lgpm binary not found; pass --lgpm /path/to/lgpm or set LGPM" >&2
  exit 1
fi

missing=0
for module in "${modules[@]}"; do
  if [ ! -f "$LGX_ROOT/$module/$module.lgx" ]; then
    missing=1
  fi
done

if [ "$missing" -eq 1 ]; then
  echo "Basecamp LGX set missing under $LGX_ROOT; generating it first." >&2
  "$ROOT/scripts/package-live-modules-lgx.sh" --out-root "$LGX_ROOT" >/dev/null
fi

for module in "${modules[@]}"; do
  if [ ! -f "$LGX_ROOT/$module/$module.lgx" ]; then
    echo "missing LGX package after generation attempt: $LGX_ROOT/$module/$module.lgx" >&2
    exit 1
  fi
done

if [ "$DIRECT_PROFILE" -eq 0 ]; then
  rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT/.scaffold/basecamp/profiles"
else
  mkdir -p "$RUN_ROOT"
fi

for profile in "${profiles[@]}"; do
  if [ "$DIRECT_PROFILE" -eq 1 ]; then
    modules_dir="$RUN_ROOT/modules"
    plugins_dir="$RUN_ROOT/plugins"
  else
    profile_root="$RUN_ROOT/.scaffold/basecamp/profiles/$profile"
    modules_dir="$profile_root/xdg-data/$XDG_SUBPATH/modules"
    plugins_dir="$profile_root/xdg-data/$XDG_SUBPATH/plugins"
    mkdir -p "$profile_root/xdg-config/$XDG_SUBPATH" "$profile_root/xdg-cache/$XDG_SUBPATH" "$profile_root/xdg-tmp"
  fi
  mkdir -p "$modules_dir" "$plugins_dir"

  for module in "${modules[@]}"; do
    "$LGPM" \
      --modules-dir "$modules_dir" \
      --ui-plugins-dir "$plugins_dir" \
      install --file "$LGX_ROOT/$module/$module.lgx"
  done

  "$LGPM" \
    --modules-dir "$modules_dir" \
    --ui-plugins-dir "$plugins_dir" \
    list --json >"$RUN_ROOT/lgpm-list-$profile.json"

  if [ "$DIRECT_PROFILE" -eq 1 ]; then
    break
  fi
done

if [ "$DIRECT_PROFILE" -eq 1 ]; then
  profiles=(basecamp)
fi

python3 - "$RUN_ROOT" "$XDG_SUBPATH" "$VARIANT" "$DIRECT_PROFILE" "${profiles[@]}" -- "${modules[@]}" <<'PY'
import json
import pathlib
import sys

run_root = pathlib.Path(sys.argv[1])
xdg_subpath = sys.argv[2]
variant = sys.argv[3]
direct_profile = sys.argv[4] == "1"
separator = sys.argv.index("--")
profiles = sys.argv[5:separator]
expected_modules = sys.argv[separator + 1 :]

summary = {
    "ok": True,
    "run_root": str(run_root),
    "xdg_subpath": xdg_subpath,
    "expected_variant": variant,
    "direct_profile": direct_profile,
    "profiles": {},
}

for profile in profiles:
    if direct_profile:
        modules_root = run_root / "modules"
    else:
        modules_root = run_root / ".scaffold/basecamp/profiles" / profile / "xdg-data" / xdg_subpath / "modules"
    installed = {}
    missing = []
    variant_missing = []
    dependency_errors = []
    for module in expected_modules:
        manifest_path = modules_root / module / "manifest.json"
        if not manifest_path.exists():
            missing.append(module)
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        main = manifest.get("main") or {}
        deps = manifest.get("dependencies") or []
        installed[module] = {
            "manifest": str(manifest_path),
            "main": main,
            "dependencies": deps,
        }
        if variant not in main:
            variant_missing.append(module)
        for dep in deps:
            if dep not in expected_modules:
                dependency_errors.append(f"{module} declares unknown dependency {dep}")
            elif not (modules_root / dep / "manifest.json").exists():
                dependency_errors.append(f"{module} dependency {dep} is not installed")

    profile_ok = not missing and not variant_missing and not dependency_errors
    summary["profiles"][profile] = {
        "ok": profile_ok,
        "modules_dir": str(modules_root),
        "installed_modules": sorted(installed),
        "missing": missing,
        "variant_missing": variant_missing,
        "dependency_errors": dependency_errors,
    }
    if not profile_ok:
        summary["ok"] = False

out = run_root / "summary.json"
out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))
raise SystemExit(0 if summary["ok"] else 1)
PY
