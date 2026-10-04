# Rapyd Sentinel – Findings

Everything discovered along the way that is worth putting in the final README: permission problems, surprises, and decisions forced by the environment. Each finding says where it was found (activity numbers match `PROGRESS.md` / `RESULTS.md`), what happened, and what a real environment would do differently.

Add new findings at the bottom and keep numbering.

## Permission problems

- **Finding 1 – `servicequotas:GetServiceQuota` is denied** (activity 3)
  - **What happened:** the Elastic IP quota could not be read.
  - **Impact:** four NAT Gateways need four Elastic IPs and the default quota is 5 per region. We cannot confirm there is room before applying.
  - **Workaround / real environment:** if the apply fails on the EIP limit, fall back to one NAT per VPC. In a real environment, grant read access to Service Quotas and request an increase beforehand.

- **Finding 2 – `iam:UpdateAssumeRolePolicy` is denied** (activity 12)
  - **What happened:** the IAM user can create a role (`sentinel-damian-gha`) but cannot edit its trust policy afterwards.
  - **Impact:** a trust policy mistake cannot be fixed in place, so the role has to be replaced.
  - **Workaround / real environment:** created a new role, `sentinel-damian-gha-v2`, with the corrected trust policy. In a real environment the role would live in Terraform, where a trust change is an in-place update, applied by someone with the right permission.

- **Finding 3 – `iam:DeleteRolePolicy` is denied, so a role cannot be cleaned up** (activity 12)
  - **What happened:** the bootstrap tried to remove the superseded `sentinel-damian-gha` role and failed at deleting its inline policy.
  - **Impact:** an unused role stays in the account. It is harmless (it trusts only this repository) but it is clutter.
  - **Workaround / real environment:** documented and left in place. An administrator would delete it.

- **Finding 4 – what IS allowed** (activities 4, 5)
  - Creating and configuring an S3 state bucket, creating `eks-*` and `sentinel-*` roles, attaching AWS managed policies such as `AmazonEKSClusterPolicy`, and putting inline policies on our own roles all work.
  - This is what makes the whole design (IAM roles per cluster, OIDC deploy role) possible without bypassing any restriction.

- **Finding 16 – `iam:GetRole` on service-linked roles is needed for EKS node groups** (activity 13)
  - **What happened:** creating a managed node group failed with `Failed to validate if SLR: AWSServiceRoleForAmazonEKSNodegroup already exists due to missing permissions for 'iam:GetRole'`. EKS calls IAM as the caller to check its service-linked role.
  - **Cause:** the CI role policy only allowed IAM actions on `eks-damian-*` / `sentinel-damian-*` roles.
  - **Fix:** allow `iam:GetRole` on `arn:aws:iam::*:role/aws-service-role/*`. Real environment: same read permission, or pre-create the service-linked roles once per account.

## Environment surprises

- **Finding 5 – the AWS account is shared with many other candidates** (activity 3)
  - About 25 state buckets and hundreds of IAM roles from other people exist in the same account.
  - IAM role names are global, so common names like `eks-gateway-cluster-role` are already taken. All our roles carry a `damian` segment (`eks-damian-gateway-cluster`, `sentinel-damian-gha-v2`) and the state bucket is `sentinel-tfstate-damian-<account>`.
  - EKS cluster names are per region, so the clusters can keep the required names `eks-gateway` and `eks-backend`.
  - Real environment: one account per environment, or a strict naming and tagging convention enforced by policy.

- **Finding 6 – the GitHub OIDC provider already existed** (activities 3, 5)
  - An account can have only one provider per URL, so ours is reused (looked up, not created). It already listed `sts.amazonaws.com` as a client ID, so only a new role was needed.

- **Finding 7 – the repository uses GitHub's immutable subject claim** (activity 12)
  - **What happened:** the first OIDC login failed with `Not authorized to perform sts:AssumeRoleWithWebIdentity`, even though the provider and audience were correct.
  - **Cause:** the token subject is `repo:damvp0320@<ownerId>/rapyd-sentinel@<repoId>:...` (read from `gh api repos/.../actions/oidc/customization/sub`), not the plain `repo:owner/name:...` form the trust policy matched.
  - **Fix:** the trust policy now allows both formats, restricted to this repository. Worth mentioning in the README because it is easy to miss and the error message gives no hint.

- **Finding 8 – `brew install terraform` no longer works** (activity 2)
  - Terraform is no longer in Homebrew core. Install with `brew install hashicorp/tap/terraform`. The tflint formula is also not in core: use `brew install terraform-linters/tap/tflint`. Include in the "how to run" section.

## Design decisions forced or confirmed by the environment

- **Finding 9 – bootstrap is a shell script, not Terraform** (activity 4)
  - A Terraform bootstrap needs somewhere to keep its own state, and CI runners start empty each time (chicken-and-egg with the state bucket it would create). An idempotent script avoids that and doubles as a permission probe that prints PASS/DENIED per step.
  - Trade-off: it is not declarative. Real environment: a separate, protected bootstrap stack with its own state.

- **Finding 10 – explicit cluster admins, not "creator is admin"** (activity 9)
  - `bootstrap_cluster_creator_admin_permissions` is false and admins are listed as EKS access entries. Otherwise the identity that creates the cluster (static keys first, OIDC role later) would be the only admin, and switching identities would lock us out.

- **Finding 11 – public plus private Kubernetes API endpoint** (activity 9)
  - GitHub-hosted runners are outside the VPC and need to reach the API for `kubectl`. The endpoint is public but IAM-authenticated. Real environment: private endpoint only with self-hosted runners inside the VPC, or a VPN/SSM path.

- **Finding 12 – Kubernetes 1.35 chosen on purpose** (activity 9)
  - `aws eks describe-cluster-versions` showed 1.33 and older are already in extended support (extra cost) while 1.34 to 1.37 are in standard support.

- **Finding 13 – Terraform 1.10 minimum** (activities 10, 11)
  - S3-native state locking (`use_lockfile`) removes the need for a DynamoDB lock table but needs Terraform 1.10 or newer. CI is pinned to 1.10.5.

- **Finding 14 – AWS tflint ruleset not enabled** (activity 11)
  - It downloads a plugin from GitHub at run time and can fail on rate limits. Only the built-in `terraform` ruleset (recommended preset) runs. Improvement: cache the plugin or pass a GitHub token.

## Follow-ups to remember

- **Finding 15 – static AWS keys are still in GitHub secrets** (activity 6)
  - They are used only by the manual bootstrap workflow; the deploy workflow uses OIDC. They expire with the challenge access, but at the end they should be deleted from the repository secrets and the bootstrap switched to OIDC as well. Mention in the README.

- **Finding 17 – a failed apply is safe to resume** (activity 13)
  - The first apply stopped at the node groups after creating 68 resources. State was saved in S3, so the next run planned only the 2 missing resources. Because the plan is a saved artifact per run, never re-run an old failed run (its plan is stale): push a new commit instead.

- **Finding 18 – timing and cost to expect** (activity 13)
  - Each EKS control plane takes about 9 minutes to create; the whole first apply is about 12 minutes before node groups. While deployed the main costs are 2 EKS control planes ($0.10/h each), 4 NAT gateways and 4 t3.medium nodes, so run `destroy` when finished.
