#!/usr/bin/env bash
# Idempotent bootstrap: creates the Terraform state bucket and the GitHub OIDC deploy role.
# Runs from CI (bootstrap.yml). Every step reports PASS/DENIED so permission limits are documented.
set -uo pipefail

REGION="${AWS_REGION:-eu-west-3}"
REPO="${GITHUB_REPOSITORY:-damvp0320/rapyd-sentinel}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="sentinel-tfstate-damian-${ACCOUNT_ID}"
ROLE_NAME="sentinel-damian-gha"
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
TRUST="$(cat <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"${OIDC_ARN}"},
"Action":"sts:AssumeRoleWithWebIdentity",
"Condition":{"StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
"StringLike":{"token.actions.githubusercontent.com:sub":"repo:${REPO}:*"}}}]}
JSON
)"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  step "iam:UpdateAssumeRolePolicy" aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST"
else
  step "iam:CreateRole (${ROLE_NAME})" aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST"
fi
POLICY="$(sed "s/__STATE_BUCKET__/${STATE_BUCKET}/g" "$DIR/policies/gha-permissions.json")"
step "iam:PutRolePolicy (inline deploy policy)" aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name sentinel-damian-deploy --policy-document "$POLICY"

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
