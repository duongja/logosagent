#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="${STAGE_DIR:-$ROOT/.local/railway-deployment}"
SERVICE="${RAILWAY_SERVICE:-logos-agent}"
ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"
VOLUME_ID=""
RAILWAY_BIN="${RAILWAY_BIN:-railway}"
CONFIRMED=false
DRY_RUN=false
PYTHON_IMAGE="python:3.12-slim-trixie@sha256:646fb0bca3dd3ea1bcc6feb72c17ed16eed6e10cffc732fcc1478bd3e7f02d7b"

usage() {
  cat <<'USAGE'
Usage: scripts/deploy-railway-volume.sh --volume-id ID [options] --yes

Uploads the staged, checksum-pinned Logos runtime to an existing Railway volume
and deploys only the selected service from a pinned Python image.

Options:
  --volume-id ID       Existing volume mounted at /data (required)
  --service NAME       Linked Railway service (default: logos-agent)
  --environment NAME   Railway environment (default: production)
  --stage-dir PATH     Output from stage-railway-deployment.sh
  --yes                Confirm the selected service mutation
  --dry-run            Validate and print the exact target without mutation

Environment override: RAILWAY_BIN.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --volume-id) VOLUME_ID="${2:-}"; shift ;;
    --service) SERVICE="${2:-}"; shift ;;
    --environment) ENVIRONMENT="${2:-}"; shift ;;
    --stage-dir) STAGE_DIR="${2:-}"; shift ;;
    --yes) CONFIRMED=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$VOLUME_ID" ]; then
  echo "--volume-id is required" >&2
  exit 2
fi
if [ "$DRY_RUN" != true ] && [ "$CONFIRMED" != true ]; then
  echo "refusing to mutate Railway without --yes" >&2
  exit 2
fi
if ! command -v "$RAILWAY_BIN" >/dev/null 2>&1; then
  echo "Railway CLI is not installed: $RAILWAY_BIN" >&2
  exit 1
fi
for path in "$STAGE_DIR/runtime.tar.gz" "$STAGE_DIR/runtime.tar.gz.sha256" \
  "$ROOT/deploy/railway/entrypoint.py" "$ROOT/deploy/railway/start-from-volume.sh"; do
  if [ ! -f "$path" ]; then
    echo "missing deployment input: $path" >&2
    exit 1
  fi
done

(cd "$STAGE_DIR" && sha256sum -c runtime.tar.gz.sha256)
runtime_sha256="$(sha256sum "$STAGE_DIR/runtime.tar.gz" | cut -d ' ' -f 1)"
status_file="$(mktemp)"
trap 'rm -f "$status_file"' EXIT
"$RAILWAY_BIN" status --json >"$status_file"

mapfile -t selection < <(python3 - "$status_file" "$SERVICE" "$ENVIRONMENT" "$VOLUME_ID" <<'PY'
import json
import sys

status = json.load(open(sys.argv[1], encoding="utf-8"))
service_name, environment_name, volume_id = sys.argv[2:]
services = {
    edge["node"]["name"]: edge["node"]["id"]
    for edge in status.get("services", {}).get("edges", [])
}
service_id = services.get(service_name)
if not service_id:
    raise SystemExit(f"service is not in the linked project: {service_name}")
environments = {
    edge["node"]["name"]: edge["node"]
    for edge in status.get("environments", {}).get("edges", [])
}
environment = environments.get(environment_name)
if not environment:
    raise SystemExit(f"environment is not in the linked project: {environment_name}")
matching_volumes = [
    item["node"]
    for item in environment.get("volumeInstances", {}).get("edges", [])
    if item["node"].get("volume", {}).get("id") == volume_id
]
if len(matching_volumes) != 1:
    raise SystemExit("volume is not attached in the selected environment")
volume = matching_volumes[0]
if volume.get("serviceId") != service_id or volume.get("mountPath") != "/data":
    raise SystemExit("volume must be attached only to the selected service at /data")
print(service_id)
print(environment["id"])
print(status["id"])
print(status["name"])
PY
)

if [ "${#selection[@]}" -ne 4 ]; then
  echo "could not resolve the selected Railway target" >&2
  exit 1
fi
service_id="${selection[0]}"
environment_id="${selection[1]}"
project_id="${selection[2]}"
project_name="${selection[3]}"

echo "Railway target: project=$project_name ($project_id), environment=$ENVIRONMENT, service=$SERVICE ($service_id)"
echo "Volume target: $VOLUME_ID mounted only at /data"
if [ "$DRY_RUN" = true ]; then
  echo "Runtime SHA-256: $runtime_sha256"
  echo "Base image: $PYTHON_IMAGE"
  echo "Dry run complete; Railway was not changed."
  exit 0
fi

"$RAILWAY_BIN" volume files --volume "$VOLUME_ID" upload \
  "$STAGE_DIR/runtime.tar.gz" /runtime.tar.gz --overwrite --json >/dev/null
"$RAILWAY_BIN" volume files --volume "$VOLUME_ID" upload \
  "$ROOT/deploy/railway/entrypoint.py" /entrypoint.py --overwrite --json >/dev/null
"$RAILWAY_BIN" volume files --volume "$VOLUME_ID" upload \
  "$ROOT/deploy/railway/start-from-volume.sh" /start-from-volume.sh --overwrite --json >/dev/null
"$RAILWAY_BIN" variable set "LOGOS_RUNTIME_SHA256=$runtime_sha256" \
  --service "$SERVICE" --skip-deploys --json >/dev/null

update_variables="$(python3 - "$service_id" "$environment_id" "$PYTHON_IMAGE" <<'PY'
import json
import sys

print(json.dumps({
    "serviceId": sys.argv[1],
    "environmentId": sys.argv[2],
    "input": {
        "source": {"image": sys.argv[3]},
        "startCommand": "/bin/sh /data/start-from-volume.sh",
        "healthcheckPath": "/healthz",
        "healthcheckTimeout": 300,
        "restartPolicyType": "ON_FAILURE",
        "restartPolicyMaxRetries": 10,
    },
}, separators=(",", ":")))
PY
)"
update_result="$($RAILWAY_BIN api \
  'mutation Update($serviceId:String!,$environmentId:String!,$input:ServiceInstanceUpdateInput!){serviceInstanceUpdate(serviceId:$serviceId,environmentId:$environmentId,input:$input)}' \
  --variables "$update_variables" --compact)"
python3 -c 'import json,sys; assert json.load(sys.stdin)["data"]["serviceInstanceUpdate"] is True' \
  <<<"$update_result"

deploy_variables="$(python3 - "$service_id" "$environment_id" <<'PY'
import json
import sys
print(json.dumps({"serviceId": sys.argv[1], "environmentId": sys.argv[2]}))
PY
)"
deploy_result="$($RAILWAY_BIN api \
  'mutation Deploy($environmentId:String!,$serviceId:String!){serviceInstanceDeployV2(environmentId:$environmentId,serviceId:$serviceId)}' \
  --variables "$deploy_variables" --compact)"
deployment_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["serviceInstanceDeployV2"])' <<<"$deploy_result")"

echo "Railway deployment started: $deployment_id"
echo "Verify with: railway logs $deployment_id --service $SERVICE"
