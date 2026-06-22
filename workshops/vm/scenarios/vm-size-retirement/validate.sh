#!/usr/bin/env bash
# Validation — VM Size Retirement. Passes (exit 0) when no VM in the resource
# group remains on a retiring size; fails (exit 1) otherwise.
set -euo pipefail

RESOURCE_GROUP="rg-srelabvm"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

FILTER="[?hardwareProfile.vmSize=='Standard_DS1_v2' || hardwareProfile.vmSize=='Standard_DS2_v2'].name"
REMAINING=$(az vm list --resource-group "$RESOURCE_GROUP" --query "$FILTER" -o tsv)

if [ -n "$(printf '%s' "$REMAINING" | tr -d '[:space:]')" ]; then
  echo "FAIL: VMs still on a retiring size:" >&2
  printf '%s\n' "$REMAINING" >&2
  exit 1
fi

echo "PASS: no VMs on a retiring size in $RESOURCE_GROUP."
