#!/usr/bin/env bash
# Idempotent bootstrap: creates the Terraform state bucket and the GitHub OIDC deploy role.
# Runs from CI (bootstrap.yml). Every step reports PASS/DENIED so permission limits are documented.
set -uo pipefail

REGION="${AWS_REGION:-eu-west-3}"
REPO="${GITHUB_REPOSITORY:-damvp0320/rapyd-sentinel}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="sentinel-tfstate-damian-${ACCOUNT_ID}"
# The scoped IAM user can create roles but NOT update a trust policy (iam:UpdateAssumeRolePolicy is denied),
# so a trust policy fix means a new role name. v1 trusted only the plain GitHub subject format.
ROLE_NAME="sentinel-damian-gha-v2"
OLD_ROLE_NAME="sentinel-damian-gha"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
DIR="$(cd "$(dirname "$0")" && pwd)"

step() { # step "<label>" cmd...
  local label="$1"; shift
  if out="$("$@" 2>&1)"; then echo "PASS    $label"; else echo "DENIED  $label"; echo "        ${out//$'\n'/$'\n        '}"; return 1; fi
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

echo "== Deploy role: ${ROLE_NAME}"
# GitHub can emit the plain subject ("repo:owner/name:...") or, when the repository uses immutable
# subjects, the ID-based one ("repo:owner@ownerId/name@repoId:..."). Trust both, for this repo only.
SUBJECTS="\"repo:${REPO}:*\""
if [[ -n "${GITHUB_REPOSITORY_OWNER_ID:-}" && -n "${GITHUB_REPOSITORY_ID:-}" ]]; then
  OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
  SUBJECTS="${SUBJECTS},\"repo:${OWNER}@${GITHUB_REPOSITORY_OWNER_ID}/${NAME}@${GITHUB_REPOSITORY_ID}:*\""
fi
TRUST="$(cat <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"${OIDC_ARN}"},
"Action":"sts:AssumeRoleWithWebIdentity",
"Condition":{"StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
"StringLike":{"token.actions.githubusercontent.com:sub":[${SUBJECTS}]}}}]}
JSON
)"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  # iam:UpdateAssumeRolePolicy is denied for this user, so an existing role keeps its trust policy.
  echo "EXISTS  ${ROLE_NAME} (trust policy unchanged; only the inline permissions policy is refreshed)"
else
  step "iam:CreateRole (${ROLE_NAME})" aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST"
fi
POLICY="$(sed -e "s/__STATE_BUCKET__/${STATE_BUCKET}/g" -e "s/__ACCOUNT_ID__/${ACCOUNT_ID}/g" -e "s/__REGION__/${REGION}/g" "$DIR/policies/gha-permissions.json")"
step "iam:PutRolePolicy (inline deploy policy)" aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name sentinel-damian-deploy --policy-document "$POLICY"

echo "== Cleanup of superseded role ${OLD_ROLE_NAME} (best effort)"
if aws iam get-role --role-name "$OLD_ROLE_NAME" >/dev/null 2>&1; then
  step "iam:DeleteRolePolicy (${OLD_ROLE_NAME})" aws iam delete-role-policy --role-name "$OLD_ROLE_NAME" --policy-name sentinel-damian-deploy \
    && step "iam:DeleteRole (${OLD_ROLE_NAME})" aws iam delete-role --role-name "$OLD_ROLE_NAME"
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
echo "ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
