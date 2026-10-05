#!/usr/bin/env bash
# Idempotent bootstrap: creates the Terraform state bucket and the three GitHub OIDC roles, one per stage.
# Runs from CI (bootstrap.yml) with the temporary static keys. Every step reports PASS/DENIED so permission
# limits are documented.
#
#   sentinel-damian-gha-read    plan + verify  read-only; trusted from any branch or pull request of this repository
#   sentinel-damian-gha-apply   apply + destroy  write; trusted only from the "production" environment (main only)
#   sentinel-damian-gha-deploy  kubectl deploys  describe cluster only; trusted only from the "production" environment
set -uo pipefail

REGION="${AWS_REGION:-eu-west-3}"
REPO="${GITHUB_REPOSITORY:-damvp0320/rapyd-sentinel}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="sentinel-tfstate-damian-${ACCOUNT_ID}"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
DIR="$(cd "$(dirname "$0")" && pwd)"

READ_ROLE="sentinel-damian-gha-read"
APPLY_ROLE="sentinel-damian-gha-apply"
DEPLOY_ROLE="sentinel-damian-gha-deploy"
OLD_ROLES=("sentinel-damian-gha-v2" "sentinel-damian-gha")

step() { # step "<label>" cmd...
  local label="$1"; shift
  if out="$("$@" 2>&1)"; then echo "PASS    $label"; else echo "DENIED  $label"; echo "        ${out//$'\n'/$'\n        '}"; return 1; fi
}

render() { # render <policy file>: fill in the placeholders
  sed -e "s/__STATE_BUCKET__/${STATE_BUCKET}/g" -e "s/__ACCOUNT_ID__/${ACCOUNT_ID}/g" -e "s/__REGION__/${REGION}/g" "$DIR/policies/$1"
}

# GitHub can emit the plain subject ("repo:owner/name:...") or, when the repository uses immutable
# subjects, the ID-based one ("repo:owner@ownerId/name@repoId:..."). Trust both, for this repository only.
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
subjects() { # subjects <suffix>  ->  JSON list of subject patterns ending in <suffix>
  local out="\"repo:${REPO}:$1\""
  if [[ -n "${GITHUB_REPOSITORY_OWNER_ID:-}" && -n "${GITHUB_REPOSITORY_ID:-}" ]]; then
    out="${out},\"repo:${OWNER}@${GITHUB_REPOSITORY_OWNER_ID}/${NAME}@${GITHUB_REPOSITORY_ID}:$1\""
  fi
  echo "$out"
}
trust() { # trust <suffix>
  cat <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"${OIDC_ARN}"},
"Action":"sts:AssumeRoleWithWebIdentity",
"Condition":{"StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
"StringLike":{"token.actions.githubusercontent.com:sub":[$(subjects "$1")]}}}]}
JSON
}

ensure_role() { # ensure_role <role> <trust suffix> <policy file> <policy name>
  local role="$1" suffix="$2" file="$3" pname="$4"
  echo "== Role: ${role}"
  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    # iam:UpdateAssumeRolePolicy is denied for this user, so an existing role keeps its trust policy.
    echo "EXISTS  ${role} (trust policy unchanged; only the inline permissions policy is refreshed)"
  else
    step "iam:CreateRole (${role})" aws iam create-role --role-name "$role" --assume-role-policy-document "$(trust "$suffix")"
  fi
  step "iam:PutRolePolicy (${pname})" aws iam put-role-policy --role-name "$role" --policy-name "$pname" --policy-document "$(render "$file")"
}

echo "== Identity"; aws sts get-caller-identity
echo "== State bucket: ${STATE_BUCKET}"
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  echo "EXISTS  bucket"
else
  step "s3:CreateBucket" aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=${REGION}"
fi
step "s3:PutBucketVersioning" aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
step "s3:PutBucketEncryption" aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
step "s3:PutPublicAccessBlock" aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "== GitHub OIDC provider (shared account: reuse, do not create)"
step "iam:GetOpenIDConnectProvider" aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN"

ensure_role "$READ_ROLE"   "*"                       read.json   sentinel-damian-read
ensure_role "$APPLY_ROLE"  "environment:production"  apply.json  sentinel-damian-apply
ensure_role "$DEPLOY_ROLE" "environment:production"  deploy.json sentinel-damian-deploy

if [[ "${NEUTRALIZE_OLD_ROLES:-false}" == "true" ]]; then
  echo "== Neutralize the superseded single-role setup (roles cannot be deleted with this user's permissions)"
  DENY_ALL='{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'
  for r in "${OLD_ROLES[@]}"; do
    if aws iam get-role --role-name "$r" >/dev/null 2>&1; then
      step "iam:PutRolePolicy deny-all (${r})" aws iam put-role-policy --role-name "$r" --policy-name sentinel-damian-deploy --policy-document "$DENY_ALL"
    fi
  done
fi

echo "== Can we create eks-* roles and attach managed policies? (create + delete throwaway role)"
PROBE="eks-damian-probe"
EKS_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if step "iam:CreateRole (${PROBE})" aws iam create-role --role-name "$PROBE" --assume-role-policy-document "$EKS_TRUST"; then
  step "iam:AttachRolePolicy AmazonEKSClusterPolicy" aws iam attach-role-policy --role-name "$PROBE" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
  aws iam detach-role-policy --role-name "$PROBE" --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy >/dev/null 2>&1
  step "iam:DeleteRole (${PROBE})" aws iam delete-role --role-name "$PROBE"
fi

echo
echo "STATE_BUCKET=${STATE_BUCKET}"
echo "ROLE_READ_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${READ_ROLE}"
echo "ROLE_APPLY_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${APPLY_ROLE}"
echo "ROLE_DEPLOY_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${DEPLOY_ROLE}"
