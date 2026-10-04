# Rapyd Sentinel – Results

Same structure as `PROGRESS.md`. Each completed activity records what actually happened, and each stage ends with a summary. Pending activities stay `RESULT: pending`.

## Day 1 – Infrastructure working through CI


### Stage 1: Setup and permission discovery
**Purpose:** Find out what we are allowed to do before designing anything. Get the credentials, map the shared AWS account, and record every permission limit so the design and the README rest on facts.

- [x] 1. Request AWS credentials from maxh@rapyd.net and note the 72h deadline
  - **RESULT:** Credentials received (IAM user `damian.vegapolanco2@gmail.com`, account `721500739616`, region `eu-west-3`). They expire about 2 days after issue, so the deadline drives the schedule.
- [x] 2. Install terraform and tflint (`brew install terraform tflint`)
  - **RESULT:** Terraform and tflint were not actually installed at the start. Installed on 2026-10-04 via Homebrew (`hashicorp/tap/terraform` 1.16.4, because plain `brew install terraform` no longer finds it, and the `terraform-linters/tap/tflint` cask 0.64.0). CI installs its own copies on the runner.
- [x] 3. Run read-only permission probes (region, S3, OIDC provider, `eks-*` / `sentinel-*` roles, managed policy attachment) and record every denial
  - **RESULT:** Account is shared with many other candidates (about 25 state buckets, hundreds of IAM roles). eu-west-3 is clean: no EKS clusters, only the default VPC `172.31.0.0/16`, no Elastic IPs in use, AZs a/b/c available. The GitHub OIDC provider already exists, so it is reused, not created. IAM role names are global and heavily used, so ours carry a `damian` suffix. One DENIED: `servicequotas:GetServiceQuota`, so the Elastic IP quota could not be read (risk for 4 NAT gateways; fallback is 1 NAT per VPC).

> **Stage 1 summary:** Credentials work and the account was mapped. It is shared with many candidates, so every global name (IAM roles, state bucket) needs a `damian` suffix. eu-west-3 is empty (no clusters, only the default VPC), the GitHub OIDC provider already exists and will be reused. The only denial found was `servicequotas:GetServiceQuota`, which leaves the Elastic IP quota unchecked.

### Stage 2: Bootstrap
**Purpose:** Create the minimum foundations that Terraform and the pipeline need before any infrastructure exists: a remote state bucket, a deploy identity (OIDC role) and the GitHub secrets and variables, all created from CI.

- [x] 4. Create the S3 state bucket via a one-off workflow (not from the laptop)
  - **RESULT:** PASS via the bootstrap workflow (run 37167733098): bucket `sentinel-tfstate-damian-721500739616` created with versioning, AES256 encryption and public access block. Done by CI, not from the laptop.
- [x] 5. Create the GitHub OIDC provider and `sentinel-github-actions` role, or fall back to secrets and document the block
  - **RESULT:** OIDC provider already existed, so it was reused. Role `sentinel-damian-gha` created, trusted only by `repo:damvp0320/rapyd-sentinel:*`, with an inline policy scoped to `eks-damian-*` / `sentinel-damian-*` roles. Also confirmed that creating an `eks-*` role and attaching the managed `AmazonEKSClusterPolicy` is allowed (probe role created then deleted). No permission blocks hit.
- [x] 6. Add GitHub repo secrets/variables (region, role ARN, state bucket)
  - **RESULT:** Repo secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and variables `AWS_REGION`, `STATE_BUCKET`, `AWS_ROLE_ARN` set. Static keys are used for bootstrap; the deploy workflow will switch to OIDC (`AWS_ROLE_ARN`).

> **Stage 2 summary:** Everything was created from CI, not the laptop. The state bucket (versioned, encrypted, private) and the OIDC deploy role `sentinel-damian-gha` exist, and creating `eks-*` roles with managed policies is confirmed to work. Repo secrets and variables are set. No IAM or S3 blocks were hit, so the OIDC bonus is feasible once the deploy workflow is written.

### Stage 3: Terraform modules
**Purpose:** Write the reusable Terraform building blocks: `network`, `peering` and `eks` as separate modules with clear inputs and outputs, plus the `envs/poc` root that wires two VPCs, the peering link and two clusters together. Nothing is applied yet.

- [x] 7. `network` module: VPC, 2 public + 2 private subnets, IGW, 1 NAT per AZ, private route table per AZ, EKS subnet tags
  - **RESULT:** Module in `terraform/modules/network`. Inputs: name, cidr_block, azs, public/private subnet CIDRs (one per AZ, validated), cluster_name, tags. Creates the VPC, IGW, one public and one private subnet per AZ, one EIP + NAT Gateway per AZ, a shared public route table, and one private route table per AZ defaulting to the NAT in the same AZ. Subnets carry the `kubernetes.io/role/elb`, `internal-elb` and `cluster/<name>` tags. No instances and no auto-assigned public IPs. Outputs: vpc_id, vpc_cidr_block, public/private subnet IDs, private_route_table_ids (consumed by the peering module), nat_gateway_ids, nat_public_ips. `fmt`, `validate` and `tflint` pass locally and in CI (provider resolved to aws 6.67.0).
- [x] 8. `peering` module: peering connection and cross-VPC routes in both private route tables
  - **RESULT:** Module in `terraform/modules/peering`. Inputs: requester/accepter VPC ID, CIDR and list of private route table IDs, plus name and tags. Creates one `aws_vpc_peering_connection` (same account and region, so `auto_accept = true`) and one route per private route table in each direction (`10.20.0.0/16` in the gateway tables, `10.10.0.0/16` in the backend tables), so with two AZs per VPC that is 4 routes. Public route tables are deliberately untouched. Security groups are left to the EKS module so each cluster owns its own rules. Outputs: `peering_connection_id` and `peering_status`. `fmt`, `validate` and `tflint` pass locally.
- [x] 9. `eks` module: cluster, `eks-*` roles, managed node group in private subnets, access entries, SG rules
  - **RESULT:** Module in `terraform/modules/eks`. Inputs: cluster_name, role_name_prefix (validated to start with `eks-`), private_subnet_ids (>= 2), kubernetes_version (default 1.35, in standard support), admin_principal_arns, node sizing, allowed_ingress_cidrs and NodePort range. Creates the cluster role (`AmazonEKSClusterPolicy`) and node role (worker, CNI, ECR read-only), the cluster with `authentication_mode = API` and private plus public endpoint, EKS access entries with the cluster-admin policy for each admin principal, and a managed node group (2x t3.medium, AL2023) in the private subnets only. `bootstrap_cluster_creator_admin_permissions` is false on purpose: admin access is explicit, so it survives switching Terraform from the static keys to the OIDC role. SG rule: `allowed_ingress_cidrs` opens the NodePort range on the cluster security group, used by the backend to allow only `10.10.0.0/16`. Outputs: name, ARN, endpoint, CA data, security group ID, role ARNs. `fmt`, `validate` and `tflint` pass locally. Not applied yet.
- [x] 10. `envs/poc` root module wiring 2x network, peering, 2x eks, with outputs
  - **RESULT:** Root in `terraform/envs/poc`. Wires `network_gateway` (10.10.0.0/16, public 10.10.1-2.0/24, private 10.10.11-12.0/24), `network_backend` (10.20.0.0/16, same layout), `peering` (gateway as requester), and `eks_gateway` / `eks_backend` (roles `eks-damian-gateway-*` / `eks-damian-backend-*`). The backend cluster passes the gateway VPC CIDR as its only allowed ingress. AZs come from a data source (first two available). S3 backend with native locking (`use_lockfile`, Terraform >= 1.10), bucket injected at init so no account values live in code. `terraform.tfvars` grants cluster-admin to the CI role and the operator user. Outputs: VPC IDs, peering ID and status, cluster names and endpoints, backend security group ID, NAT egress IPs and ready-to-run kubeconfig commands. `fmt`, `validate` and `tflint` pass locally. No plan or apply yet, those run in CI (Stage 4).

> **Stage 3 summary:** The whole infrastructure is now expressed as three reusable modules (`network`, `peering`, `eks`) with typed, validated inputs and explicit outputs, composed by one root (`envs/poc`) that builds two isolated VPCs, a private peering link and two EKS clusters. Key decisions: one NAT per AZ, private route tables per AZ, EKS access entries with explicit admin principals (so the move from static keys to OIDC does not lock us out), roles named `eks-damian-*`, and S3-native state locking. Everything passes `fmt`, `validate` and `tflint` locally and nothing has been applied yet. Open risks to check at the first plan/apply: the Elastic IP quota (4 NATs), and whether the CI role policy covers every API the modules call.

### Stage 4: Pipeline and first apply
**Purpose:** Put the Terraform behind GitHub Actions: lint and validate on every push, plan on push, apply on main. The first successful apply proves both clusters and the VPC peering exist.

- [x] 11. `ci.yml`: fmt, validate, tflint on every push
  - **RESULT:** `.github/workflows/ci.yml` runs on every push and pull request with no AWS credentials: `terraform fmt -check -recursive`, then `terraform init -backend=false` + `validate` for each of the 4 Terraform directories (3 modules and `envs/poc`, auto-discovered with `find`, so new modules are covered without editing the workflow), then `tflint` per directory with the `recommended` preset from `.tflint.hcl`. Terraform pinned to 1.10.5 (the minimum for S3-native locking). Superseded runs on the same ref are cancelled. The same checks pass locally. The AWS tflint ruleset is not enabled because it downloads a plugin from GitHub at runtime; noted as a possible improvement.
- [x] 12. `deploy.yml`: plan on push, apply on main
  - **RESULT:** `.github/workflows/deploy.yml` runs on every push. The `plan` job assumes the AWS role through GitHub OIDC (no static keys), runs `init` (bucket injected from the `STATE_BUCKET` variable), `validate` and `plan -out=tfplan`, prints the plan in the job summary and uploads it as an artifact. The `apply` job runs only on `refs/heads/main`, downloads that exact plan artifact and applies it, so what is applied is what was planned. Concurrency never cancels a running deploy. Verified on branch `feature/deploy-pipeline`: OIDC login works and the plan reports 70 to add, 0 to change, 0 to destroy. The apply job is skipped on branches and gets its first real run when merged to main (activity 13).
  - **Limits hit (documented for the README):** (1) OIDC was first rejected (`AssumeRoleWithWebIdentity` not authorized) because this repository uses GitHub's *immutable subject* claim (`repo:owner@ownerId/name@repoId:...`), not the plain `repo:owner/name:...` the trust policy matched. (2) The IAM user may create roles but `iam:UpdateAssumeRolePolicy` is denied, so the trust policy could not be edited in place. Fix: bootstrap now trusts both subject formats and creates a new role, `sentinel-damian-gha-v2`. (3) The old `sentinel-damian-gha` role could not be removed (`iam:DeleteRolePolicy` denied) and remains as an unused leftover. In a real environment an admin would delete it, or the role would be managed in Terraform where a trust policy change is an in-place update.
- [ ] 13. First apply via GitHub Actions; both clusters ACTIVE and peering working
  - **RESULT:** pending

> **Stage 4 summary:** pending
## Day 2 – Workloads, validation, documentation


### Stage 5: Kubernetes workloads
**Purpose:** Define what runs on the clusters: the internal backend service behind an internal NLB, and the NGINX proxy behind a public NLB that forwards to the backend over the peering link. Deploy order is backend first, then gateway.

- [ ] 14. Backend manifests: Deployment ("Hello from backend") + internal NLB Service with `loadBalancerSourceRanges: 10.10.0.0/16`
  - **RESULT:** pending
- [ ] 15. Gateway manifests: NGINX Deployment + ConfigMap (backend NLB hostname via `envsubst`) + public NLB Service
  - **RESULT:** pending
- [ ] 16. Deploy jobs in order: backend, wait for NLB hostname, gateway, wait for public hostname
  - **RESULT:** pending

> **Stage 5 summary:** pending

### Stage 6: Validation and bonuses
**Purpose:** Prove the system works and is restricted as designed: end-to-end curl through the public NLB, manifest and Terraform checks in the pipeline, and evidence that only the gateway VPC can reach the backend.

- [ ] 17. End-to-end test: `curl` the public NLB with retries returns "Hello from backend"
  - **RESULT:** pending
- [ ] 18. Manifest validation (`kubectl apply --dry-run=server`) and tflint wired into the pipeline
  - **RESULT:** pending
- [ ] 19. Verify backend restriction (SG rule on backend nodes allows only 10.10.0.0/16) and capture evidence (CI log/screenshot)
  - **RESULT:** pending

> **Stage 6 summary:** pending

### Stage 7: Documentation and wrap-up
**Purpose:** Finish the deliverables: final architecture diagram, an honest README (how to run, networking, trade-offs, next steps), the destroy workflow and a clean final run before submitting.

- [ ] 20. Final architecture diagram saved to `docs/assets/architecture.png`
  - **RESULT:** pending
- [ ] 21. README: how to run, networking, proxy-to-backend flow, CI/CD overview, permission limits hit, trade-offs, next steps
  - **RESULT:** pending
- [ ] 22. Manual-only `destroy.yml`, final clean run from a fresh push, then submit
  - **RESULT:** pending

> **Stage 7 summary:** pending
