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
- [ ] 8. `peering` module: peering connection and cross-VPC routes in both private route tables
  - **RESULT:** pending
- [ ] 9. `eks` module: cluster, `eks-*` roles, managed node group in private subnets, access entries, SG rules
  - **RESULT:** pending
- [ ] 10. `envs/poc` root module wiring 2x network, peering, 2x eks, with outputs
  - **RESULT:** pending

> **Stage 3 summary:** pending

### Stage 4: Pipeline and first apply
**Purpose:** Put the Terraform behind GitHub Actions: lint and validate on every push, plan on push, apply on main. The first successful apply proves both clusters and the VPC peering exist.

- [ ] 11. `ci.yml`: fmt, validate, tflint on every push
  - **RESULT:** pending
- [ ] 12. `deploy.yml`: plan on push, apply on main
  - **RESULT:** pending
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
