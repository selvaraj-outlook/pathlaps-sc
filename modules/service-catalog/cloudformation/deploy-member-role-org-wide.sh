#!/usr/bin/env bash
# =============================================================================
# deploy-member-role-org-wide.sh
#
# Deploys the Service Catalog member role (member-account-role.yaml) to every
# account in the AWS Organization using a SERVICE_MANAGED CloudFormation
# StackSet. Run this script from the Organizations MANAGEMENT account
# (476846833787) or from an account already registered as a delegated
# administrator for servicecatalog.amazonaws.com and
# stacksets.cloudformation.amazonaws.com.
#
# Usage:
#   ./deploy-member-role-org-wide.sh [OPTIONS]
#
# Options:
#   --profile        AWS CLI profile to use (must be management/delegated-admin account)
#   --region         AWS region to deploy the StackSet in (default: us-east-1)
#   --root-id        Organizations root ID (e.g. r-ab12). Auto-detected if omitted.
#   --trusted-arns   Comma-separated IAM principal ARNs trusted to assume the
#                    member role in each spoke account. Use 'arn:aws:iam::*:root'
#                    to allow the account root (admin-only, not recommended for prod).
#                    Example: arn:aws:iam::853973692277:role/AWSReservedSSO_developer_xxxx
#   --role-name      Name for the member IAM role (default: path-labs-service-catalog-member-role)
#   --stack-set-name Name for the StackSet (default: path-labs-service-catalog-member-role)
#   --dry-run        Print what would be done without making any AWS API calls
#   --delete         Delete the StackSet and all stack instances (rollback)
#
# Examples:
#   # Deploy to entire org with SSO developer role trusted
#   ./deploy-member-role-org-wide.sh \
#     --profile management-account \
#     --trusted-arns "arn:aws:iam::*:role/AWSReservedSSO_developer_abc123"
#
#   # Deploy to a specific OU only
#   ./deploy-member-role-org-wide.sh \
#     --profile management-account \
#     --root-id ou-ab12-xyz789 \
#     --trusted-arns "arn:aws:iam::*:role/AWSReservedSSO_developer_abc123"
#
#   # Dry run first to see what will happen
#   ./deploy-member-role-org-wide.sh \
#     --profile management-account \
#     --trusted-arns "arn:aws:iam::*:role/AWSReservedSSO_developer_abc123" \
#     --dry-run
#
#   # Delete everything (rollback)
#   ./deploy-member-role-org-wide.sh \
#     --profile management-account \
#     --delete
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PROFILE=""
REGION="us-east-1"
ROOT_ID=""
TRUSTED_ARNS=""
ROLE_NAME="path-labs-service-catalog-member-role"
STACK_SET_NAME="path-labs-service-catalog-member-role"
DRY_RUN=false
DELETE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/member-account-role.yaml"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No colour

log()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()    { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()    { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)        PROFILE="$2";        shift 2 ;;
    --region)         REGION="$2";         shift 2 ;;
    --root-id)        ROOT_ID="$2";        shift 2 ;;
    --trusted-arns)   TRUSTED_ARNS="$2";   shift 2 ;;
    --role-name)      ROLE_NAME="$2";      shift 2 ;;
    --stack-set-name) STACK_SET_NAME="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true;        shift   ;;
    --delete)         DELETE=true;         shift   ;;
    *) die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
[[ -z "$PROFILE" ]] && die "--profile is required (must be management or delegated-admin account)"
[[ -f "$TEMPLATE_FILE" ]] || die "Template not found: $TEMPLATE_FILE"

AWS="aws --profile ${PROFILE} --region ${REGION}"

if [[ "$DELETE" == "false" && -z "$TRUSTED_ARNS" ]]; then
  die "--trusted-arns is required. Provide comma-separated IAM principal ARNs that users in spoke accounts will assume."
fi

# ---------------------------------------------------------------------------
# Dry-run mode
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  warn "DRY RUN — no AWS API calls will be made"
  echo ""
  log "Would use profile       : ${PROFILE}"
  log "Would use region        : ${REGION}"
  log "StackSet name           : ${STACK_SET_NAME}"
  log "Template                : ${TEMPLATE_FILE}"
  log "Role name               : ${ROLE_NAME}"
  log "Trusted principal ARNs  : ${TRUSTED_ARNS}"
  [[ -n "$ROOT_ID" ]] && log "Target OU/Root ID       : ${ROOT_ID}" || log "Target OU/Root ID       : (auto-detect org root)"
  echo ""
  exit 0
fi

# ---------------------------------------------------------------------------
# Verify caller identity
# ---------------------------------------------------------------------------
log "Verifying caller identity..."
CALLER=$(${AWS} sts get-caller-identity --output json)
CALLER_ACCOUNT=$(echo "$CALLER" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
CALLER_ARN=$(echo "$CALLER" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")
ok "Running as: ${CALLER_ARN} (account ${CALLER_ACCOUNT})"

# ---------------------------------------------------------------------------
# Auto-detect org root ID if not provided
# ---------------------------------------------------------------------------
if [[ -z "$ROOT_ID" ]]; then
  log "Auto-detecting organization root ID..."
  ROOT_ID=$(${AWS} organizations list-roots \
    --query 'Roots[0].Id' \
    --output text 2>/dev/null) || die "Could not list org roots. Ensure this account has organizations:ListRoots permission, or pass --root-id manually."
  ok "Org root ID: ${ROOT_ID}"
fi

# ---------------------------------------------------------------------------
# Step 1: Enable trusted access for CloudFormation StackSets (idempotent)
# ---------------------------------------------------------------------------
log "Step 1/5 — Enabling CloudFormation StackSets trusted access in Organizations..."
${AWS} organizations enable-aws-service-access \
  --service-principal stacksets.cloudformation.amazonaws.com 2>/dev/null \
  && ok "StackSets trusted access enabled" \
  || warn "Already enabled or insufficient permissions — continuing"

# ---------------------------------------------------------------------------
# Step 2: Enable trusted access for Service Catalog (idempotent)
# ---------------------------------------------------------------------------
log "Step 2/5 — Enabling Service Catalog trusted access in Organizations..."
${AWS} organizations enable-aws-service-access \
  --service-principal servicecatalog.amazonaws.com 2>/dev/null \
  && ok "Service Catalog trusted access enabled" \
  || warn "Already enabled or insufficient permissions — continuing"

# ---------------------------------------------------------------------------
# Step 3: Create or update the StackSet
# ---------------------------------------------------------------------------
log "Step 3/5 — Creating/updating StackSet '${STACK_SET_NAME}'..."

EXISTING=$(${AWS} cloudformation describe-stack-set \
  --stack-set-name "${STACK_SET_NAME}" \
  --query 'StackSet.StackSetName' \
  --output text 2>/dev/null || echo "NONE")

TEMPLATE_BODY=$(cat "${TEMPLATE_FILE}")

STACKSET_PARAMS=$(cat <<EOF
[
  {"ParameterKey":"RoleName","ParameterValue":"${ROLE_NAME}"},
  {"ParameterKey":"TrustedPrincipalArns","ParameterValue":"${TRUSTED_ARNS}"}
]
EOF
)

if [[ "$EXISTING" == "NONE" ]]; then
  log "  StackSet does not exist — creating..."
  ${AWS} cloudformation create-stack-set \
    --stack-set-name "${STACK_SET_NAME}" \
    --description "Service Catalog end-user member role - deployed org-wide by deploy-member-role-org-wide.sh" \
    --template-body "${TEMPLATE_BODY}" \
    --parameters "${STACKSET_PARAMS}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --permission-model SERVICE_MANAGED \
    --auto-deployment "Enabled=true,RetainStacksOnAccountRemoval=false" \
    --tags '[{"Key":"ManagedBy","Value":"CloudFormation"},{"Key":"Purpose","Value":"path-labs-service-catalog-member-role"}]'
  ok "StackSet created"
else
  log "  StackSet exists — updating template and parameters..."
  ${AWS} cloudformation update-stack-set \
    --stack-set-name "${STACK_SET_NAME}" \
    --template-body "${TEMPLATE_BODY}" \
    --parameters "${STACKSET_PARAMS}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --permission-model SERVICE_MANAGED \
    --auto-deployment "Enabled=true,RetainStacksOnAccountRemoval=false" \
    --operation-preferences "MaxConcurrentPercentage=100,FailureTolerancePercentage=20" \
    2>/dev/null && ok "StackSet updated" || warn "No changes to update"
fi

# ---------------------------------------------------------------------------
# Step 4: Create stack instances across the entire org
# ---------------------------------------------------------------------------
log "Step 4/5 — Creating stack instances in all accounts under root '${ROOT_ID}'..."
log "  (This deploys to every existing account and auto-deploys to new ones)"

OPERATION_ID=$(${AWS} cloudformation create-stack-instances \
  --stack-set-name "${STACK_SET_NAME}" \
  --deployment-targets "OrganizationalUnitIds=[\"${ROOT_ID}\"]" \
  --regions "${REGION}" \
  --parameter-overrides \
    "ParameterKey=RoleName,ParameterValue=${ROLE_NAME}" \
    "ParameterKey=TrustedPrincipalArns,ParameterValue=${TRUSTED_ARNS}" \
  --operation-preferences "MaxConcurrentPercentage=100,FailureTolerancePercentage=20" \
  --query 'OperationId' \
  --output text 2>/dev/null || echo "FAILED")

if [[ "$OPERATION_ID" == "FAILED" ]]; then
  warn "create-stack-instances returned an error — instances may already exist."
  warn "If updating existing instances, use: aws cloudformation update-stack-instances"
else
  ok "Stack instances operation started — Operation ID: ${OPERATION_ID}"
fi

# ---------------------------------------------------------------------------
# Step 5: Poll until the operation completes
# ---------------------------------------------------------------------------
if [[ "$OPERATION_ID" != "FAILED" ]]; then
  log "Step 5/5 — Waiting for stack instances operation to complete..."
  log "  (This can take several minutes depending on org size)"

  while true; do
    STATUS=$(${AWS} cloudformation describe-stack-set-operation \
      --stack-set-name "${STACK_SET_NAME}" \
      --operation-id "${OPERATION_ID}" \
      --query 'StackSetOperation.Status' \
      --output text 2>/dev/null || echo "UNKNOWN")

    case "$STATUS" in
      SUCCEEDED)
        ok "Operation SUCCEEDED — member role deployed to all accounts"
        break ;;
      FAILED)
        err "Operation FAILED — check CloudFormation StackSets console for details"
        ${AWS} cloudformation list-stack-set-operation-results \
          --stack-set-name "${STACK_SET_NAME}" \
          --operation-id "${OPERATION_ID}" \
          --query 'Summaries[?Status==`FAILED`].{Account:Account,Status:Status,Reason:StatusReason}' \
          --output table 2>/dev/null || true
        exit 1 ;;
      STOPPED)
        err "Operation was STOPPED manually"
        exit 1 ;;
      RUNNING|QUEUED)
        echo -ne "  Status: ${STATUS} — waiting...\r"
        sleep 10 ;;
      *)
        warn "Unknown status: ${STATUS} — waiting..."
        sleep 10 ;;
    esac
  done
else
  log "Step 5/5 — Skipped (no operation to wait for)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================================="
ok "DEPLOYMENT COMPLETE"
echo "======================================================================="
log "StackSet name   : ${STACK_SET_NAME}"
log "Role name       : ${ROLE_NAME}"
log "Region          : ${REGION}"
log "Target          : ${ROOT_ID} (org-wide, all accounts)"
log "Trusted ARNs    : ${TRUSTED_ARNS}"
echo ""
log "Next steps:"
log "  1. In each spoke account, accept the Service Catalog portfolio share:"
log "     aws servicecatalog accept-portfolio-share \\"
log "       --portfolio-id port-lxqf7crikfwqu \\"
log "       --region ${REGION} \\"
log "       --profile <spoke-account-profile>"
log ""
log "  2. Associate the member role with the imported portfolio in each spoke account:"
log "     aws servicecatalog associate-principal-with-portfolio \\"
log "       --portfolio-id port-lxqf7crikfwqu \\"
log "       --principal-arn arn:aws:iam::<spoke-account-id>:role/${ROLE_NAME} \\"
log "       --principal-type IAM \\"
log "       --region ${REGION} \\"
log "       --profile <spoke-account-profile>"
echo ""

# ---------------------------------------------------------------------------
# DELETE mode
# ---------------------------------------------------------------------------
if [[ "$DELETE" == "true" ]]; then
  echo ""
  warn "DELETE mode — removing all stack instances and the StackSet..."

  log "Deleting stack instances from org root ${ROOT_ID}..."
  DEL_OP=$(${AWS} cloudformation delete-stack-instances \
    --stack-set-name "${STACK_SET_NAME}" \
    --deployment-targets "OrganizationalUnitIds=[\"${ROOT_ID}\"]" \
    --regions "${REGION}" \
    --no-retain-stacks \
    --query 'OperationId' \
    --output text 2>/dev/null || echo "NONE")

  if [[ "$DEL_OP" != "NONE" ]]; then
    log "Waiting for instance deletion (Operation ID: ${DEL_OP})..."
    while true; do
      STATUS=$(${AWS} cloudformation describe-stack-set-operation \
        --stack-set-name "${STACK_SET_NAME}" \
        --operation-id "${DEL_OP}" \
        --query 'StackSetOperation.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")
      [[ "$STATUS" == "SUCCEEDED" ]] && break
      [[ "$STATUS" == "FAILED"    ]] && die "Delete instances FAILED"
      echo -ne "  Status: ${STATUS} — waiting...\r"
      sleep 10
    done
    ok "Stack instances deleted"
  fi

  log "Deleting StackSet '${STACK_SET_NAME}'..."
  ${AWS} cloudformation delete-stack-set \
    --stack-set-name "${STACK_SET_NAME}" \
    && ok "StackSet deleted" \
    || warn "Could not delete StackSet — it may still have instances"
  exit 0
fi
