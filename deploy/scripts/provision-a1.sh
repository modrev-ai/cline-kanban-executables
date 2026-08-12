#!/bin/bash
# Provision an Always Free VM.Standard.A1.Flex (ARM) instance to replace the
# VM.Standard.E2.1.Micro the Kanban stack currently runs on.
#
# Why: the E2.1.Micro shape is 1 burstable OCPU / 1 GB RAM (~498 MB usable).
# A1.Flex gives 4 OCPUs and 24 GB RAM for the same $0. The shapes are different
# architectures (x86_64 vs aarch64), so this cannot be an in-place resize --
# it has to be a new instance.
#
# Everything (compartment, subnet, SSH keys) is discovered from the EXISTING
# instance so no OCIDs are hardcoded in this repo.
#
# Usage:
#   ./provision-a1.sh --source-ip 129.159.69.183 [--ocpus 4] [--memory 24]
#                     [--boot-gb 100] [--name kanban-a1] [--retry 0]
#
# Prerequisites:
#   oci session authenticate      # tokens expire; refresh before running
set -euo pipefail

SOURCE_IP=""
OCPUS=4
MEMORY_GB=24
BOOT_GB=100
NAME="kanban-a1"
RETRY=0          # minutes to keep retrying on "Out of host capacity" (0 = one pass)

while [ $# -gt 0 ]; do
  case "$1" in
    --source-ip) SOURCE_IP="$2"; shift 2 ;;
    --ocpus)     OCPUS="$2"; shift 2 ;;
    --memory)    MEMORY_GB="$2"; shift 2 ;;
    --boot-gb)   BOOT_GB="$2"; shift 2 ;;
    --name)      NAME="$2"; shift 2 ;;
    --retry)     RETRY="$2"; shift 2 ;;
    -h|--help)   sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$SOURCE_IP" ] || { echo "ERROR: --source-ip is required" >&2; exit 1; }

command -v oci >/dev/null || {
  echo "ERROR: the OCI CLI is not installed." >&2
  echo "  Windows: powershell -File deploy/install-oci.ps1" >&2
  echo "  Linux:   bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\"" >&2
  exit 1
}

echo "=== [1/6] Checking OCI authentication ==="
if ! oci iam region list --output table >/dev/null 2>&1; then
  echo "ERROR: OCI CLI is not authenticated (or the session token expired)." >&2
  echo "Run: oci session authenticate" >&2
  exit 1
fi
echo "OCI authentication OK"

echo "=== [2/6] Discovering configuration from existing instance ${SOURCE_IP} ==="
# The tenancy (root compartment) OCID: availability-domain list is invoked against
# the tenancy, so data[0]."compartment-id" is the root compartment OCID.
TENANCY_ID=$(oci iam availability-domain list --query 'data[0]."compartment-id"' --raw-output)

# Build the list of compartments to search: the tenancy root plus every ACTIVE
# compartment in its subtree. `oci compute instance list` is per-compartment (not
# recursive), and the source instance often lives in a CHILD compartment, so a
# single-compartment search silently misses it and the script exits below. Always
# include the root first so this degrades to the old behavior if subtree listing
# is unavailable.
# The trailing `|| true` matters: under `set -e` a command substitution that ends
# in a failing command (grep finds nothing when the caller lacks inspect-compartment
# permission, or the tenancy is flat) would abort the whole script here instead of
# falling back to the root-only search this is supposed to degrade to.
COMPARTMENTS=$(
  printf '%s\n' "$TENANCY_ID"
  oci iam compartment list --compartment-id "$TENANCY_ID" --compartment-id-in-subtree true \
    --all --lifecycle-state ACTIVE --query 'data[].id' --raw-output 2>/dev/null \
    | tr -d '[]," ' | grep -v '^$' || true
)

# Locate the source instance by matching its public IP through its VNIC. The new
# instance is launched into the SAME compartment the source was found in.
SOURCE_INSTANCE_ID=""
SUBNET_ID=""
COMPARTMENT_ID=""
for cid in $COMPARTMENTS; do
  for iid in $(oci compute instance list --compartment-id "$cid" \
                 --lifecycle-state RUNNING --query 'data[].id' --raw-output 2>/dev/null | tr -d '[]," ' | grep -v '^$'); do
    VNIC=$(oci compute instance list-vnics --instance-id "$iid" \
             --query 'data[0].{ip:"public-ip",subnet:"subnet-id"}' --output json 2>/dev/null || echo '{}')
    if echo "$VNIC" | grep -q "\"$SOURCE_IP\""; then
      SOURCE_INSTANCE_ID="$iid"
      COMPARTMENT_ID="$cid"
      SUBNET_ID=$(echo "$VNIC" | grep -oE '"subnet"[^"]*"[^"]*"' | grep -oE 'ocid1[^"]*')
      break 2
    fi
  done
done

[ -n "$SUBNET_ID" ] || {
  echo "ERROR: could not find a RUNNING instance with public IP ${SOURCE_IP}." >&2
  echo "Searched the tenancy root and all subtree compartments. Check that the IP" >&2
  echo "is correct and the CLI session is pointed at the right tenancy/region." >&2
  exit 1
}
echo "Found source instance in compartment: ${COMPARTMENT_ID:0:30}..."
echo "Reusing subnet: ${SUBNET_ID:0:30}..."

echo "=== [3/6] Finding the latest Oracle Linux 9 aarch64 image ==="
IMAGE_ID=$(oci compute image list \
  --compartment-id "$COMPARTMENT_ID" \
  --operating-system "Oracle Linux" \
  --operating-system-version "9" \
  --shape "VM.Standard.A1.Flex" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)

[ -n "$IMAGE_ID" ] && [ "$IMAGE_ID" != "null" ] || {
  echo "ERROR: no Oracle Linux 9 aarch64 image available for VM.Standard.A1.Flex" >&2
  exit 1
}
echo "Image: ${IMAGE_ID:0:30}..."

echo "=== [4/6] Selecting SSH public key ==="
SSH_KEY_FILE=""
for candidate in ~/.ssh/ssh-key-2026-07-30.key.pub ~/.ssh/id_rsa_oracle.pub ~/.ssh/id_ed25519.pub; do
  [ -f "$candidate" ] && { SSH_KEY_FILE="$candidate"; break; }
done
[ -n "$SSH_KEY_FILE" ] || { echo "ERROR: no SSH public key found in ~/.ssh" >&2; exit 1; }
echo "Using SSH key: $SSH_KEY_FILE"

echo "=== [5/6] Launching ${NAME} (A1.Flex ${OCPUS} OCPU / ${MEMORY_GB} GB / ${BOOT_GB} GB boot) ==="
# A1 free-tier capacity is scarce and AD-specific, so try every AD in the region.
ADS=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --query 'data[].name' --raw-output | tr -d '[]," ' | grep -v '^$')

# Pre-flight the A1 service limit. The Always Free A1 allowance is commonly 4 OCPU /
# 24 GB, but plenty of tenancies (trial-converted ones especially) are capped at
# 2 / 12. Asking for more than the cap fails per-AD, which is easy to misread as a
# capacity shortage and then "wait out" forever. Check up front and name the
# values that would actually fit.
PREFLIGHT_AD=$(echo "$ADS" | head -1)
a1_limit() {
  oci limits resource-availability get --compartment-id "$COMPARTMENT_ID" \
    --service-name compute --limit-name "$1" --availability-domain "$PREFLIGHT_AD" \
    --query 'data.available' --raw-output 2>/dev/null || true
}
AVAIL_CORES=$(a1_limit standard-a1-core-count)
AVAIL_MEM=$(a1_limit standard-a1-memory-count)
if [ -n "${AVAIL_CORES:-}" ] && [ -n "${AVAIL_MEM:-}" ] &&
   printf '%s%s' "$AVAIL_CORES" "$AVAIL_MEM" | grep -qE '^[0-9]+$'; then
  if [ "$OCPUS" -gt "$AVAIL_CORES" ] || [ "$MEMORY_GB" -gt "$AVAIL_MEM" ]; then
    echo "ERROR: requested ${OCPUS} OCPU / ${MEMORY_GB} GB, but this tenancy has only" >&2
    echo "       ${AVAIL_CORES} A1 core(s) / ${AVAIL_MEM} GB available in ${PREFLIGHT_AD}." >&2
    echo "       Re-run with: --ocpus ${AVAIL_CORES} --memory ${AVAIL_MEM}" >&2
    exit 1
  fi
  echo "A1 limit check OK (${AVAIL_CORES} core(s) / ${AVAIL_MEM} GB available)"
fi

launch_once() {
  for ad in $ADS; do
    echo "  Trying availability domain: $ad"
    if OUT=$(oci compute instance launch \
        --compartment-id "$COMPARTMENT_ID" \
        --availability-domain "$ad" \
        --shape "VM.Standard.A1.Flex" \
        --shape-config "{\"ocpus\":${OCPUS},\"memoryInGBs\":${MEMORY_GB}}" \
        --image-id "$IMAGE_ID" \
        --subnet-id "$SUBNET_ID" \
        --display-name "$NAME" \
        --assign-public-ip true \
        --boot-volume-size-in-gbs "$BOOT_GB" \
        --ssh-authorized-keys-file "$SSH_KEY_FILE" \
        --wait-for-state RUNNING \
        --output json 2>&1); then
      echo "$OUT" > /tmp/a1-launch.json
      echo "  Launched in $ad"
      return 0
    fi
    # The service reports exhausted ARM capacity as a 500 InternalError whose
    # "message" is "Out of host capacity." -- and the CLI auto-retries 5xx, so the
    # phrase can end up buried above the tail of a long error blob. Match the whole
    # payload, and surface code/message explicitly: a blind `tail` here hid the
    # real reason behind trailing "troubleshooting_tips" boilerplate.
    if echo "$OUT" | grep -qiE "out of (host )?capacity|OutOfCapacity"; then
      echo "  Out of host capacity in $ad"
    else
      echo "  Launch failed in $ad:" >&2
      echo "$OUT" | grep -oE '"(code|message|status)": *"?[^",]*"?' | head -5 >&2 \
        || echo "$OUT" | head -20 >&2
    fi
  done
  return 1
}

DEADLINE=$(( $(date +%s) + RETRY * 60 ))
until launch_once; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "" >&2
    echo "ERROR: could not launch an A1.Flex instance in any availability domain." >&2
    echo "Free-tier ARM capacity in us-ashburn-1 is frequently exhausted." >&2
    echo "Re-run with --retry 120 to keep trying for two hours." >&2
    exit 1
  fi
  echo "All ADs out of capacity; sleeping 60s (retrying until $(date -d "@$DEADLINE" 2>/dev/null || echo "deadline"))..."
  sleep 60
done

echo "=== [6/6] Instance details ==="
NEW_ID=$(grep -oE '"id": "ocid1\.instance[^"]*"' /tmp/a1-launch.json | head -1 | grep -oE 'ocid1[^"]*')
NEW_IP=$(oci compute instance list-vnics --instance-id "$NEW_ID" --query 'data[0]."public-ip"' --raw-output)

cat <<SUMMARY

========================================================
  A1.Flex instance is RUNNING
========================================================
  Name        : ${NAME}
  Shape       : VM.Standard.A1.Flex (${OCPUS} OCPU / ${MEMORY_GB} GB)
  Public IP   : ${NEW_IP}
  Instance ID : ${NEW_ID}

Next steps:
  1. Open ports 3484/3485 in the subnet security list (if not inherited).
  2. Confirm SSH works:
       ssh -i ${SSH_KEY_FILE%.pub} opc@${NEW_IP}
  3. Point the deployment at the new host:
       gh secret set ORACLE_HOST --body '${NEW_IP}' --repo modrev-ai/cline-kanban-executables
  4. Run the infrastructure + deploy workflows. deploy-infra.sh now detects
     aarch64 automatically and installs the ARM Node.js build.
  5. Verify, then terminate the old E2.1.Micro instance to free the quota.
========================================================
SUMMARY
