#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ROOT="${RUN_ROOT:-$ROOT/.local/test-runs/$(date -u +%Y%m%dT%H%M%SZ)}"
ALLOW_BATTERY=0
USE_INHIBIT=1
JOBS="${STABLE_TEST_JOBS:-2}"
NIX_CORES="${STABLE_TEST_NIX_CORES:-2}"
MONITOR_INTERVAL="${STABLE_TEST_MONITOR_INTERVAL:-15}"

usage() {
  cat <<'USAGE'
Usage: scripts/stable-test-runner.sh [options] -- command [args...]

Runs a real integration/build command with a safer laptop profile:
  - refuses battery power unless --allow-battery is set
  - blocks shutdown/sleep/idle through systemd-inhibit while the command runs
  - limits common build parallelism to reduce memory and thermal pressure
  - records preflight, postflight, command output, and resource monitor logs

Options:
  --allow-battery     Permit running while AC power is offline.
  --no-inhibit        Do not wrap the command in systemd-inhibit.
  --jobs N            Set CARGO/CMake/Make parallelism. Default: 2.
  --nix-cores N       Set Nix build cores via NIX_CONFIG. Default: 2.
  --run-root PATH     Log directory. Default: .local/test-runs/<utc timestamp>.
  -h, --help          Show this help.

Examples:
  scripts/stable-test-runner.sh -- nix build --impure .#unit-tests-fast -L --max-jobs 1 --cores 2
  scripts/stable-test-runner.sh --allow-battery -- ./scripts/delivery-smoke.sh --preset logos.dev --api-only
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow-battery) ALLOW_BATTERY=1 ;;
    --no-inhibit) USE_INHIBIT=0 ;;
    --jobs)
      JOBS="${2:-}"
      shift
      ;;
    --nix-cores)
      NIX_CORES="${2:-}"
      shift
      ;;
    --run-root)
      RUN_ROOT="${2:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$#" -eq 0 ]; then
  echo "missing command to run" >&2
  usage >&2
  exit 2
fi

case "$JOBS" in
  ''|*[!0-9]*|0)
    echo "--jobs must be a positive integer" >&2
    exit 2
    ;;
esac

case "$NIX_CORES" in
  ''|*[!0-9]*|0)
    echo "--nix-cores must be a positive integer" >&2
    exit 2
    ;;
esac

mkdir -p "$RUN_ROOT"
PREFLIGHT="$RUN_ROOT/preflight.txt"
POSTFLIGHT="$RUN_ROOT/postflight.txt"
COMMAND_LOG="$RUN_ROOT/command.log"
MONITOR_LOG="$RUN_ROOT/resource-monitor.log"

on_ac_power_safe() {
  if command -v on_ac_power >/dev/null 2>&1; then
    on_ac_power >/dev/null 2>&1
    return $?
  fi

  if command -v upower >/dev/null 2>&1; then
    while IFS= read -r device; do
      if upower -i "$device" 2>/dev/null | grep -Eq 'online:[[:space:]]+yes'; then
        return 0
      fi
    done < <(upower -e 2>/dev/null | grep -F line_power || true)
    return 1
  fi

  return 2
}

snapshot() {
  local label="$1"
  {
    echo "label: $label"
    echo "timestamp: $(date -Ins)"
    echo
    echo "uname:"
    uname -a || true
    echo
    echo "uptime:"
    uptime || true
    echo
    echo "memory:"
    free -h || true
    echo
    echo "swap:"
    swapon --show || true
    echo
    echo "disk:"
    df -h / /nix /tmp 2>/dev/null || df -h / /tmp || true
    echo
    echo "power:"
    if command -v upower >/dev/null 2>&1; then
      upower -d || true
    else
      echo "upower not available"
    fi
    echo
    echo "nix config:"
    if command -v nix >/dev/null 2>&1; then
      nix show-config 2>/dev/null | grep -E '^(max-jobs|cores|sandbox|substituters|trusted-public-keys)' || true
    else
      echo "nix not available"
    fi
    echo
    echo "top memory processes:"
    ps -eo pid,ppid,comm,%mem,%cpu,rss,args --sort=-%mem | head -n 20 || true
    echo
    echo "active inhibitors:"
    if command -v systemd-inhibit >/dev/null 2>&1; then
      systemd-inhibit --list || true
    else
      echo "systemd-inhibit not available"
    fi
  }
}

warn_if_low_swap() {
  local swap_kib
  swap_kib="$(awk 'NR > 1 { total += $3 } END { print total + 0 }' /proc/swaps 2>/dev/null || echo 0)"
  if [ "$swap_kib" -lt 8388608 ]; then
    cat >&2 <<EOF
Warning: active swap is below 8 GiB.

Heavy Nix/Rust/RISC0 builds on this 8 GiB RAM laptop can trigger systemd-oomd
and restart the desktop session. Activate the extra swap file before long builds:

  sudo swapon /swapfile-logos-agent-8g

EOF
  fi
}

monitor_resources() {
  while true; do
    echo "timestamp: $(date -Ins)"
    free -h || true
    df -h / /nix /tmp 2>/dev/null || df -h / /tmp || true
    echo "memory pressure:"
    cat /proc/pressure/memory 2>/dev/null || true
    echo "io pressure:"
    cat /proc/pressure/io 2>/dev/null || true
    echo "top memory processes:"
    ps -eo pid,ppid,comm,%mem,%cpu,rss,args --sort=-rss | head -n 18 || true
    if command -v sensors >/dev/null 2>&1; then
      sensors 2>/dev/null | head -n 80 || true
    fi
    echo
    sleep "$MONITOR_INTERVAL"
  done
}

if ! on_ac_power_safe; then
  if [ "$ALLOW_BATTERY" -eq 0 ]; then
    cat >&2 <<EOF
Refusing to run: AC power appears to be offline.

Plug in the laptop, then rerun this command. For a deliberately light smoke test,
you can override this check with --allow-battery.

Logs directory prepared at: $RUN_ROOT
EOF
    snapshot "battery-refused" > "$PREFLIGHT"
    exit 75
  fi
fi

export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$JOBS}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$JOBS}"
export MAKEFLAGS="${MAKEFLAGS:--j$JOBS}"

if [ -n "${NIX_CONFIG:-}" ]; then
  export NIX_CONFIG="${NIX_CONFIG}
max-jobs = 1
cores = $NIX_CORES"
else
  export NIX_CONFIG="max-jobs = 1
cores = $NIX_CORES"
fi

snapshot "preflight" > "$PREFLIGHT"
warn_if_low_swap | tee -a "$PREFLIGHT" >&2
monitor_resources > "$MONITOR_LOG" 2>&1 &
MONITOR_PID=$!

cleanup() {
  kill "$MONITOR_PID" >/dev/null 2>&1 || true
  wait "$MONITOR_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "run_root: $RUN_ROOT"
echo "command_log: $COMMAND_LOG"
echo "preflight: $PREFLIGHT"
echo "resource_monitor: $MONITOR_LOG"

set +e
if [ "$USE_INHIBIT" -eq 1 ] && command -v systemd-inhibit >/dev/null 2>&1; then
  systemd-inhibit \
    --what=shutdown:sleep:idle \
    --who=logos-agent-tests \
    --why="running Logos real integration test" \
    --mode=block \
    "$@" 2>&1 | tee "$COMMAND_LOG"
  STATUS=${PIPESTATUS[0]}
else
  "$@" 2>&1 | tee "$COMMAND_LOG"
  STATUS=${PIPESTATUS[0]}
fi
set -e

snapshot "postflight" > "$POSTFLIGHT"

echo "postflight: $POSTFLIGHT"
echo "exit_status: $STATUS"
exit "$STATUS"
