#!/bin/bash
# ============================================================================
# enable-oci-ingress.sh
# ----------------------------------------------------------------------------
# Enable the OCI VCN Security List ingress rule for the public Kanban proxy
# port (TCP 3484) from YOUR WORKSTATION, using your already-configured local
# OCI CLI (~/.oci/config with an API key / user auth).
#
# This replaces the previous approach that installed the OCI CLI on the Oracle
# instance and used instance-principal auth (which needed a tenancy-level
# dynamic-group + policy). Running it locally with your own credentials avoids
# all of that: you already have permission in the OCI Console, so the CLI you
# already use has it too.
#
# The rule added is idempotent (it is a no-op if 3484 is already open):
#   Stateless: No | Source: 0.0.0.0/0 | Protocol: TCP | Dest port: 3484
#
# Usage (provide exactly ONE target):
#   deploy/scripts/enable-oci-ingress.sh --instance-id <ocid> [--port 3484]
#   deploy/scripts/enable-oci-ingress.sh --subnet-id   <ocid> [--port 3484]
#   deploy/scripts/enable-oci-ingress.sh --security-list-id <ocid> [--port 3484]
#
# Extra options:
#   --profile <name>   OCI CLI config profile to use (default: DEFAULT)
#   --source  <cidr>   Source CIDR for the rule (default: 0.0.0.0/0)
#   -h | --help        Show this help.
#
# Requires: oci (OCI CLI) and python3 on PATH.
# ============================================================================
set -euo pipefail

PORT=3484
SOURCE_CIDR="0.0.0.0/0"
PROFILE=""
INSTANCE_ID=""
SUBNET_ID=""
SL_ID=""

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --instance-id)       INSTANCE_ID="${2:-}"; shift 2 ;;
    --subnet-id)         SUBNET_ID="${2:-}"; shift 2 ;;
    --security-list-id)  SL_ID="${2:-}"; shift 2 ;;
    --port)              PORT="${2:-}"; shift 2 ;;
    --source)            SOURCE_CIDR="${2:-}"; shift 2 ;;
    --profile)           PROFILE="${2:-}"; shift 2 ;;
    -h|--help)           usage 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage 1 ;;
  esac
done

# --- Preconditions ----------------------------------------------------------
if ! command -v oci >/dev/null 2>&1; then
  echo "ERROR: the OCI CLI ('oci') is not on PATH." >&2
  echo "       Install it and run 'oci setup config' first: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required (used to compute the updated rule set)." >&2
  exit 1
fi

# Count how many targets were supplied.
TARGETS=0
[ -n "$INSTANCE_ID" ] && TARGETS=$((TARGETS+1))
[ -n "$SUBNET_ID" ] && TARGETS=$((TARGETS+1))
[ -n "$SL_ID" ] && TARGETS=$((TARGETS+1))
if [ "$TARGETS" -ne 1 ]; then
  echo "ERROR: provide exactly one of --instance-id / --subnet-id / --security-list-id." >&2
  usage 1
fi

# Build the common '--profile' argument (empty if not set -> CLI uses DEFAULT).
OCI_ARGS=()
[ -n "$PROFILE" ] && OCI_ARGS+=(--profile "$PROFILE")

echo "=== Enabling OCI VCN ingress for TCP ${PORT} (source ${SOURCE_CIDR}) ==="

# --- Resolve instance -> subnet ---------------------------------------------
if [ -n "$INSTANCE_ID" ]; then
  echo "Resolving primary VNIC / subnet for instance ${INSTANCE_ID}..."
  COMPARTMENT_ID=$(oci "${OCI_ARGS[@]}" compute instance get --instance-id "$INSTANCE_ID" \
    --query 'data."compartment-id"' --raw-output 2>/dev/null || echo "")
  if [ -z "$COMPARTMENT_ID" ]; then
    echo "ERROR: could not read the instance (check the OCID, profile, and permissions)." >&2
    exit 1
  fi
  SUBNET_ID=$(oci "${OCI_ARGS[@]}" compute instance list-vnics --instance-id "$INSTANCE_ID" \
    --compartment-id "$COMPARTMENT_ID" --query 'data[0]."subnet-id"' --raw-output 2>/dev/null || echo "")
  if [ -z "$SUBNET_ID" ]; then
    echo "ERROR: could not resolve the instance's subnet." >&2
    exit 1
  fi
  echo "Subnet: $SUBNET_ID"
fi

# --- Resolve subnet -> security list ----------------------------------------
if [ -n "$SUBNET_ID" ] && [ -z "$SL_ID" ]; then
  SL_ID=$(oci "${OCI_ARGS[@]}" network subnet get --subnet-id "$SUBNET_ID" \
    --query 'data."security-list-ids"[0]' --raw-output 2>/dev/null || echo "")
  if [ -z "$SL_ID" ]; then
    echo "ERROR: could not resolve the subnet's security list." >&2
    exit 1
  fi
fi
echo "Target security list: $SL_ID"

# --- Fetch current ingress rules --------------------------------------------
CUR=$(oci "${OCI_ARGS[@]}" network security-list get --security-list-id "$SL_ID" \
  --query 'data."ingress-security-rules"' --output json 2>/dev/null || echo "")
if [ -z "$CUR" ]; then
  echo "ERROR: could not read current ingress rules for $SL_ID." >&2
  exit 1
fi

# --- Compute the updated rule set (idempotent) ------------------------------
# The CLI returns kebab-case JSON; the update command expects camelCase. The
# python helper converts, checks whether the port is already covered, and (if
# not) appends the new rule and writes the full set to $RULES_FILE.
RULES_FILE="$(mktemp -t oci-ingress-rules.XXXXXX.json)"
trap 'rm -f "$RULES_FILE"' EXIT

ADD_NEEDED=$(printf '%s' "$CUR" | PORT="$PORT" SRC="$SOURCE_CIDR" OUT="$RULES_FILE" python3 - <<'PY'
import sys, json, os
port = int(os.environ["PORT"])
src = os.environ["SRC"]
rules = json.load(sys.stdin) or []

def to_camel(s):
    a = s.split('-')
    return a[0] + ''.join(w[:1].upper() + w[1:] for w in a[1:])

def conv(o):
    if isinstance(o, dict):
        return {to_camel(k): conv(v) for k, v in o.items()}
    if isinstance(o, list):
        return [conv(x) for x in o]
    return o

crules = conv(rules)

def covers(r):
    if r.get("source") != src:
        return False
    proto = str(r.get("protocol"))
    if proto == "all":
        return True
    if proto != "6":  # 6 = TCP
        return False
    tcp = r.get("tcpOptions") or {}
    dpr = tcp.get("destinationPortRange")
    if not dpr:            # no port range == all TCP ports
        return True
    return dpr.get("min", 1) <= port <= dpr.get("max", 65535)

if any(covers(r) for r in crules):
    print("no")
else:
    crules.append({
        "source": src,
        "sourceType": "CIDR_BLOCK",
        "protocol": "6",
        "isStateless": False,
        "tcpOptions": {"destinationPortRange": {"min": port, "max": port}},
    })
    with open(os.environ["OUT"], "w") as f:
        json.dump(crules, f)
    print("yes")
PY
)

# --- Apply -------------------------------------------------------------------
if [ "$ADD_NEEDED" = "no" ]; then
  echo "[OK] OCI ingress for TCP ${PORT} (source ${SOURCE_CIDR}) already present - nothing to do."
  exit 0
elif [ "$ADD_NEEDED" = "yes" ]; then
  echo "Adding ingress rule for TCP ${PORT}..."
  if oci "${OCI_ARGS[@]}" network security-list update --security-list-id "$SL_ID" \
       --ingress-security-rules "file://${RULES_FILE}" --force >/dev/null 2>&1; then
    echo "[OK] Added OCI ingress rule for TCP ${PORT} (source ${SOURCE_CIDR})."
  else
    echo "ERROR: failed to update the security list." >&2
    echo "       Re-run showing CLI output to see why:" >&2
    echo "         oci ${OCI_ARGS[*]} network security-list update --security-list-id $SL_ID --ingress-security-rules file://${RULES_FILE} --force" >&2
    exit 1
  fi
else
  echo "ERROR: could not evaluate current ingress rules; nothing changed." >&2
  exit 1
fi
