# Rapyd Sentinel – Progress Checklist

Mark items with `[x]` as they are completed.

## Day 1 – Infrastructure working through CI


### Stage 1: Setup and permission discovery
**Purpose:** Find out what we are allowed to do before designing anything. Get the credentials, map the shared AWS account, and record every permission limit so the design and the README rest on facts.

- [x] 1. Request AWS credentials from maxh@rapyd.net and note the 72h deadline
- [x] 2. Install terraform and tflint (`brew install terraform tflint`)
- [x] 3. Run read-only permission probes (region, S3, OIDC provider, `eks-*` / `sentinel-*` roles, managed policy attachment) and record every denial


### Stage 2: Bootstrap
**Purpose:** Create the minimum foundations that Terraform and the pipeline need before any infrastructure exists: a remote state bucket, a deploy identity (OIDC role) and the GitHub secrets and variables, all created from CI.

- [x] 4. Create the S3 state bucket via a one-off workflow (not from the laptop)
- [x] 5. Create the GitHub OIDC provider and `sentinel-github-actions` role, or fall back to secrets and document the block
- [x] 6. Add GitHub repo secrets/variables (region, role ARN, state bucket)


### Stage 3: Terraform modules
**Purpose:** Write the reusable Terraform building blocks: `network`, `peering` and `eks` as separate modules with clear inputs and outputs, plus the `envs/poc` root that wires two VPCs, the peering link and two clusters together. Nothing is applied yet.

- [x] 7. `network` module: VPC, 2 public + 2 private subnets, IGW, 1 NAT per AZ, private route table per AZ, EKS subnet tags
- [x] 8. `peering` module: peering connection and cross-VPC routes in both private route tables
- [x] 9. `eks` module: cluster, `eks-*` roles, managed node group in private subnets, access entries, SG rules
- [x] 10. `envs/poc` root module wiring 2x network, peering, 2x eks, with outputs


### Stage 4: Pipeline and first apply
**Purpose:** Put the Terraform behind GitHub Actions: lint and validate on every push, plan on push, apply on main. The first successful apply proves both clusters and the VPC peering exist.

- [x] 11. `ci.yml`: fmt, validate, tflint on every push
- [x] 12. `deploy.yml`: plan on push, apply on main
- [x] 13. First apply via GitHub Actions; both clusters ACTIVE and peering working

## Day 2 – Workloads, validation, documentation


### Stage 5: Kubernetes workloads
**Purpose:** Define what runs on the clusters: the internal backend service behind an internal NLB, and the NGINX proxy behind a public NLB that forwards to the backend over the peering link. Deploy order is backend first, then gateway.

- [x] 14. Backend manifests: Deployment ("Hello from backend") + internal NLB Service with `loadBalancerSourceRanges: 10.10.0.0/16`
- [x] 15. Gateway manifests: NGINX Deployment + ConfigMap (backend NLB hostname via `envsubst`) + public NLB Service
- [x] 16. Deploy jobs in order: backend, wait for NLB hostname, gateway, wait for public hostname


### Stage 6: Validation and bonuses
**Purpose:** Prove the system works and is restricted as designed: end-to-end curl through the public NLB, manifest and Terraform checks in the pipeline, and evidence that only the gateway VPC can reach the backend.

- [x] 17. End-to-end test: `curl` the public NLB with retries returns "Hello from backend"
- [x] 18. Manifest validation (`kubectl apply --dry-run=server`) and tflint wired into the pipeline
- [x] 19. Verify backend restriction (SG rule on backend nodes allows only 10.10.0.0/16) and capture evidence (CI log/screenshot)


### Stage 7: Documentation and wrap-up
**Purpose:** Finish the deliverables: final architecture diagram, an honest README (how to run, networking, trade-offs, next steps), the destroy workflow and a clean final run before submitting.

- [x] 20. Final architecture diagram saved to `docs/assets/architecture.png`
- [ ] 21. README: how to run, networking, proxy-to-backend flow, CI/CD overview, permission limits hit, trade-offs, next steps
- [ ] 22. Manual-only `destroy.yml`, final clean run from a fresh push, then submit
