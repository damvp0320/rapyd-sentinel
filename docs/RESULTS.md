# Rapyd Sentinel – Results

Same structure as `PROGRESS.md`. Each completed activity records what actually happened. Pending activities stay `RESULT: pending`.

## Day 1 – Infrastructure working through CI

### Stage 1: Setup and permission discovery
- [x] 1. Request AWS credentials from maxh@rapyd.net and note the 72h deadline
  - **RESULT:** Credentials received (IAM user `damian.vegapolanco2@gmail.com`, account `721500739616`, region `eu-west-3`). They expire about 2 days after issue, so the deadline drives the schedule.
- [x] 2. Install terraform and tflint (`brew install terraform tflint`)
  - **RESULT:** Marked done locally. CI does not depend on the laptop: `ci.yml` installs its own Terraform 1.10.5 and tflint on the runner.
- [x] 3. Run read-only permission probes (region, S3, OIDC provider, `eks-*` / `sentinel-*` roles, managed policy attachment) and record every denial
  - **RESULT:** Account is shared with many other candidates (about 25 state buckets, hundreds of IAM roles). eu-west-3 is clean: no EKS clusters, only the default VPC `172.31.0.0/16`, no Elastic IPs in use, AZs a/b/c available. The GitHub OIDC provider already exists, so it is reused, not created. IAM role names are global and heavily used, so ours carry a `damian` suffix. One DENIED: `servicequotas:GetServiceQuota`, so the Elastic IP quota could not be read (risk for 4 NAT gateways; fallback is 1 NAT per VPC).

### Stage 2: Bootstrap
- [x] 4. Create the S3 state bucket via a one-off workflow (not from the laptop)
  - **RESULT:** PASS via the bootstrap workflow (run 37167733098): bucket `sentinel-tfstate-damian-721500739616` created with versioning, AES256 encryption and public access block. Done by CI, not from the laptop.
- [x] 5. Create the GitHub OIDC provider and `sentinel-github-actions` role, or fall back to secrets and document the block
  - **RESULT:** OIDC provider already existed, so it was reused. Role `sentinel-damian-gha` created, trusted only by `repo:damvp0320/rapyd-sentinel:*`, with an inline policy scoped to `eks-damian-*` / `sentinel-damian-*` roles. Also confirmed that creating an `eks-*` role and attaching the managed `AmazonEKSClusterPolicy` is allowed (probe role created then deleted). No permission blocks hit.
- [x] 6. Add GitHub repo secrets/variables (region, role ARN, state bucket)
  - **RESULT:** Repo secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and variables `AWS_REGION`, `STATE_BUCKET`, `AWS_ROLE_ARN` set. Static keys are used for bootstrap; the deploy workflow will switch to OIDC (`AWS_ROLE_ARN`).

### Stage 3: Terraform modules
- [ ] 7. `network` module: VPC, 2 public + 2 private subnets, IGW, 1 NAT, route tables, EKS subnet tags
  - **RESULT:** pending
- [ ] 8. `peering` module: peering connection and cross-VPC routes in both private route tables
  - **RESULT:** pending
- [ ] 9. `eks` module: cluster, `eks-*` roles, managed node group in private subnets, access entries, SG rules
  - **RESULT:** pending
- [ ] 10. `envs/poc` root module wiring 2x network, peering, 2x eks, with outputs
  - **RESULT:** pending

### Stage 4: Pipeline and first apply
- [ ] 11. `ci.yml`: fmt, validate, tflint on every push
  - **RESULT:** pending
- [ ] 12. `deploy.yml`: plan on push, apply on main
  - **RESULT:** pending
- [ ] 13. First apply via GitHub Actions; both clusters ACTIVE and peering working
  - **RESULT:** pending

## Day 2 – Workloads, validation, documentation

### Stage 5: Kubernetes workloads
- [ ] 14. Backend manifests: Deployment ("Hello from backend") + internal NLB Service with `loadBalancerSourceRanges: 10.10.0.0/16`
  - **RESULT:** pending
- [ ] 15. Gateway manifests: NGINX Deployment + ConfigMap (backend NLB hostname via `envsubst`) + public NLB Service
  - **RESULT:** pending
- [ ] 16. Deploy jobs in order: backend, wait for NLB hostname, gateway, wait for public hostname
  - **RESULT:** pending

### Stage 6: Validation and bonuses
- [ ] 17. End-to-end test: `curl` the public NLB with retries returns "Hello from backend"
  - **RESULT:** pending
- [ ] 18. Manifest validation (`kubectl apply --dry-run=server`) and tflint wired into the pipeline
  - **RESULT:** pending
- [ ] 19. Verify backend restriction (SG rule on backend nodes allows only 10.10.0.0/16) and capture evidence (CI log/screenshot)
  - **RESULT:** pending

### Stage 7: Documentation and wrap-up
- [ ] 20. Final architecture diagram saved to `docs/assets/architecture.png`
  - **RESULT:** pending
- [ ] 21. README: how to run, networking, proxy-to-backend flow, CI/CD overview, permission limits hit, trade-offs, next steps
  - **RESULT:** pending
- [ ] 22. Manual-only `destroy.yml`, final clean run from a fresh push, then submit
  - **RESULT:** pending
