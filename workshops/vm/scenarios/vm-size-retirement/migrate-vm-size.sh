#!/usr/bin/env bash
# Approval-gated remediation — VM Size Retirement.
# Resizes every VM in the resource group that is on a retiring size to the current
# target size. Invoked only through tools/invoke-approved-remediation.sh; the
# gate passes --vm-name, which is intentionally ignored (the whole fleet migrates).
set -euo pipefail

RESOURCE_GROUP="rg-srelabvm"
VM_NAME=""
TARGET_SIZE="Standard_D2s_v5"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -n|--vm-name) VM_NAME="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>] [--vm-name <ignored>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

FILTER="[?hardwareProfile.vmSize=='Standard_DS1_v2' || hardwareProfile.vmSize=='Standard_DS2_v2'].name"

AFFECTED=""
while IFS= read -r name; do
  [ -n "$name" ] && AFFECTED="$AFFECTED $name"
done < <(az vm list --resource-group "$RESOURCE_GROUP" --query "$FILTER" -o tsv)

if [ -z "$(printf '%s' "$AFFECTED" | tr -d '[:space:]')" ]; then
  echo "No VMs on a retiring size in $RESOURCE_GROUP. Nothing to migrate."
  exit 0
fi

COUNT=0
for vm in $AFFECTED; do
  echo "Resizing $vm -> $TARGET_SIZE ..."
  az vm resize --resource-group "$RESOURCE_GROUP" --name "$vm" --size "$TARGET_SIZE" --only-show-errors >/dev/null
  COUNT=$((COUNT + 1))
done

echo "Migration complete. Resized $COUNT VM(s) to $TARGET_SIZE."
