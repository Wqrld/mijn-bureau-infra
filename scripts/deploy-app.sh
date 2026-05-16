#!/usr/bin/env bash
# deploy-app.sh — Fast per-app deploy using tier label selectors.
#
# Usage:
#   ./scripts/deploy-app.sh <app> [<app2> ...] [options]
#
# Options:
#   --with-infra    Also deploy infrastructure releases (postgresql/redis/minio)
#                   before deploying the application. Required for initial deploys.
#   --update-deps   Run 'helm dependency build' before deploying (updates chart
#                   downloads). By default this is skipped since deps are already
#                   on disk. Only needed after a chart version bump.
#   -e <env>        Helmfile environment (default: demo)
#   --diff          Run 'diff' instead of 'apply'
#   --sync          Run 'sync' instead of 'apply' (no wait)
#   --template      Run 'template' instead of 'apply' (render manifests to stdout)
#
# Examples:
#   ./scripts/deploy-app.sh drive                        # app only (fast path)
#   ./scripts/deploy-app.sh drive --with-infra           # full deploy (initial)
#   ./scripts/deploy-app.sh drive nextcloud grist        # multiple apps, app only
#   ./scripts/deploy-app.sh drive nextcloud --with-infra # multiple apps with infra
#   ./scripts/deploy-app.sh drive -e production          # production app deploy
#   ./scripts/deploy-app.sh drive --diff                 # preview changes
#   ./scripts/deploy-app.sh drive --template             # render manifests locally
#   ./scripts/deploy-app.sh drive --update-deps          # rebuild chart deps first

set -euo pipefail

# Auto-detect apps: any directory under helmfile/apps/ with a helmfile-child.yaml.gotmpl
mapfile -t APPS < <(
  for dir in helmfile/apps/*/; do
    app="${dir%/}"; app="${app##*/}"
    [[ -f "helmfile/apps/${app}/helmfile-child.yaml.gotmpl" ]] && echo "$app"
  done | sort
)

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  echo ""
  echo "Available apps: ${APPS[*]}"
  exit 1
}

SELECTED_APPS=()
ENV="demo"
WITH_INFRA=false
UPDATE_DEPS=false
CMD="apply"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-infra)   WITH_INFRA=true; shift ;;
    --update-deps)  UPDATE_DEPS=true; shift ;;
    --diff)         CMD="diff"; shift ;;
    --sync)         CMD="sync"; shift ;;
    --template)     CMD="template"; shift ;;
    -e)             ENV="$2"; shift 2 ;;
    -h|--help)      usage ;;
    -*)             echo "Unknown option: $1"; usage ;;
    *)              SELECTED_APPS+=("$1"); shift ;;
  esac
done

if [[ ${#SELECTED_APPS[@]} -eq 0 ]]; then
  echo "Error: at least one app name required."
  usage
fi

# Returns true if the app's main chart has its dependencies downloaded.
app_deps_built() {
  local charts_dir="helmfile/apps/${1}/charts/${1}/charts"
  [[ -d "$charts_dir" ]] && [[ -n "$(ls -A "$charts_dir" 2>/dev/null)" ]]
}

deploy_app() {
  local app="$1"
  local child_file="helmfile/apps/${app}/helmfile-child.yaml.gotmpl"

  if [[ ! -f "$child_file" ]]; then
    echo "Error: app not found: $app"
    echo "Available apps: ${APPS[*]}"
    exit 1
  fi

  if [[ "$CMD" == "template" ]]; then
    echo "==> Rendering ${app} (env: ${ENV})"
  else
    echo "==> Deploying ${app} (env: ${ENV}, cmd: ${CMD})"
  fi

  if $UPDATE_DEPS; then
    echo "  Updating chart dependencies..."
    helmfile -e "$ENV" -f "$child_file" deps
  elif ! app_deps_built "$app"; then
    echo "  Chart dependencies not found, building (first deploy)..."
    helmfile -e "$ENV" -f "$child_file" deps
  fi

  if $WITH_INFRA; then
    helmfile -e "$ENV" -f "$child_file" --skip-deps "$CMD"
  else
    helmfile -e "$ENV" -f "$child_file" -l tier=app --skip-deps "$CMD"
  fi
}

for app in "${SELECTED_APPS[@]}"; do
  deploy_app "$app"
done

echo "==> Done."
