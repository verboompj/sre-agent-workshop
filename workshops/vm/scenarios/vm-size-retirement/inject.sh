#!/usr/bin/env bash
# Scenario — VM Size Retirement.
# Plants 3 deallocated "legacy" VMs on a retiring DSv2 size so the SRE Agent can
# enumerate every affected VM in the resource group, then emits a simulated Azure
# Service Health retirement advisory for the attendee to paste into the agent.
set -euo pipefail

RESOURCE_GROUP="rg-srelabvm"
WORKLOAD="srelabvm"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -w|--workload) WORKLOAD="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>] [--workload <name>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

VNET_NAME="${WORKLOAD}-vnet"
SUBNET_NAME="${WORKLOAD}-subnet"
ADMIN_USER="azureuser"
ADMIN_PASSWORD="Sre$(openssl rand -hex 12)#Aa9"

# name|size|space-separated tags
LEGACY_VMS="
${WORKLOAD}-legacy-01|Standard_DS1_v2|env=prod app=billing-legacy owner=unknown
${WORKLOAD}-legacy-02|Standard_DS2_v2|env=test app=reporting-legacy
${WORKLOAD}-legacy-03|Standard_DS1_v2|env=prod app=batch-legacy owner=unknown
"

LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)

printf '%s\n' "$LEGACY_VMS" | while IFS='|' read -r vm size tags; do
  [ -z "$vm" ] && continue
  if az vm show --resource-group "$RESOURCE_GROUP" --name "$vm" >/dev/null 2>&1; then
    echo "Resetting $vm to retiring size $size ..."
    az vm resize --resource-group "$RESOURCE_GROUP" --name "$vm" --size "$size" --only-show-errors >/dev/null
  else
    echo "Creating legacy VM $vm ($size) ..."
    if ! az network nic show --resource-group "$RESOURCE_GROUP" --name "${vm}-nic" >/dev/null 2>&1; then
      az network nic create --resource-group "$RESOURCE_GROUP" --name "${vm}-nic" \
        --vnet-name "$VNET_NAME" --subnet "$SUBNET_NAME" --only-show-errors >/dev/null
    fi
    az vm create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$vm" \
      --image Ubuntu2204 \
      --size "$size" \
      --nics "${vm}-nic" \
      --storage-sku StandardSSD_LRS \
      --admin-username "$ADMIN_USER" \
      --admin-password "$ADMIN_PASSWORD" \
      --authentication-type password \
      --tags $tags workshop=sre-agent track=vm scenario=vm-size-retirement \
      --only-show-errors --no-wait
  fi
done

# Wait for any newly created VMs to finish provisioning, then deallocate to cut cost.
printf '%s\n' "$LEGACY_VMS" | while IFS='|' read -r vm size tags; do
  [ -z "$vm" ] && continue
  az vm wait --resource-group "$RESOURCE_GROUP" --name "$vm" --created --only-show-errors >/dev/null 2>&1 || true
  az vm deallocate --resource-group "$RESOURCE_GROUP" --name "$vm" --no-wait --only-show-errors >/dev/null 2>&1 || true
done

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RETIREMENT_DATE="2027-05-31"
TRACKING_ID="0BNF-9X8"
EVENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat <<EOF

================================================================
Paste the following Azure Service Health advisory into the SRE Agent:
================================================================
{
  "eventSource": "ServiceHealth",
  "category": "ServiceHealth",
  "level": "Warning",
  "operationName": "Microsoft.ServiceHealth/healthadvisory/action",
  "eventTimestamp": "$EVENT_TS",
  "properties": {
    "title": "Action required: migrate off retiring Dv2/DSv2-series virtual machine sizes",
    "service": "Virtual Machines",
    "region": "$LOCATION",
    "incidentType": "ActionRequired",
    "trackingId": "$TRACKING_ID",
    "impactedService": "Virtual Machines",
    "impactedSizes": "Standard_DS1_v2 / Standard_DS2_v2 (DSv2-series)",
    "retirementDate": "$RETIREMENT_DATE",
    "subscriptionId": "$SUBSCRIPTION_ID",
    "communication": "The Dv2/DSv2-series VM sizes are being retired on $RETIREMENT_DATE. Identify all virtual machines in your control on these sizes and resize them to a current series (for example Standard_D2s_v5) before the retirement date to avoid service disruption."
  }
}
================================================================
Legacy VMs planted in $RESOURCE_GROUP: ${WORKLOAD}-legacy-01, ${WORKLOAD}-legacy-02, ${WORKLOAD}-legacy-03
EOF
