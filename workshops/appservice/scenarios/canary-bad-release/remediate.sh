#!/usr/bin/env bash
set -euo pipefail
RESOURCE_GROUP="rg-srelabapp"
WORKLOAD="srelabapp"
SLOT="staging"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../../src"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -w|--workload) WORKLOAD="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>] [--workload <name>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

WEB=$(az webapp list -g "$RESOURCE_GROUP" --query "[?starts_with(name,'${WORKLOAD}-web-')].name | [0]" -o tsv)
if [ -z "$WEB" ]; then echo "No web app found in $RESOURCE_GROUP" >&2; exit 1; fi

az webapp traffic-routing clear -g "$RESOURCE_GROUP" --name "$WEB"
echo "Cleared traffic routing: 100% to the production slot on $WEB."

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
cp -r "$SRC_DIR/." "$BUILD_DIR/"
dotnet publish "$BUILD_DIR/Shop.csproj" -c Release -o "$BUILD_DIR/publish"
( cd "$BUILD_DIR/publish" && zip -r "$BUILD_DIR/app.zip" . >/dev/null )
az webapp deploy -g "$RESOURCE_GROUP" --name "$WEB" --slot "$SLOT" --type zip --src-path "$BUILD_DIR/app.zip"

echo "Remediation complete: traffic cleared and the good build redeployed to slot '$SLOT'."
