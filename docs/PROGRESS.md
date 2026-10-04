# Rapyd Sentinel – Progress Checklist

Mark items with `[x]` as they are completed.

## Day 1 – Infrastructure working through CI

### Stage 1: Setup and permission discovery
- [x] 1. Request AWS credentials from maxh@rapyd.net and note the 72h deadline
- [x] 2. Install terraform and tflint (`brew install terraform tflint`)
- [ ] 3. Run read-only permission probes (region, S3, OIDC provider, `eks-*` / `sentinel-*` roles, managed policy attachment) and record every denial

### Stage 2: Bootstrap
- [ ] 4. Create the S3 state bucket via a one-off workflow (not from the laptop)
- [ ] 5. Create the GitHub OIDC provider and `sentinel-github-actions` role, or fall back to secrets and document the block
- [ ] 6. Add GitHub repo secrets/variables (region, role ARN, state bucket)

### Stage 3: Terraform modules
- [ ] 7. `network` module: VPC, 2 public + 2 private subnets, IGW, 1 NAT, route tables, EKS subnet tags
- [ ] 8. `peering` module: peering connection and cross-VPC routes in both private route tables
- [ ] 9. `eks` module: cluster, `eks-*` roles, managed node group in private subnets, access entries, SG rules
- [ ] 10. `envs/poc` root module wiring 2x network, peering, 2x eks, with outputs

### Stage 4: Pipeline and first apply
- [ ] 11. `ci.yml`: fmt, validate, tflint on every push
- [ ] 12. `deploy.yml`: plan on push, apply on main
- [ ] 13. First apply via GitHub Actions; both clusters ACTIVE and peering working

## Day 2 – Workloads, validation, documentation

### Stage 5: Kubernetes workloads
- [ ] 14. Backend manifests: Deployment ("Hello from backend") + internal NLB Service with `loadBalancerSourceRanges: 10.10.0.0/16`
- [ ] 15. Gateway manifests: NGINX Deployment + ConfigMap (backend NLB hostname via `envsubst`) + public NLB Service
- [ ] 16. Deploy jobs in order: backend, wait for NLB hostname, gateway, wait for public hostname

### Stage 6: Validation and bonuses
- [ ] 17. End-to-end test: `curl` the public NLB with retries returns "Hello from backend"
- [ ] 18. Manifest validation (`kubectl apply --dry-run=server`) and tflint wired into the pipeline
- [ ] 19. Verify backend restriction (SG rule on backend nodes allows only 10.10.0.0/16) and capture evidence (CI log/screenshot)

### Stage 7: Documentation and wrap-up
- [ ] 20. Final architecture diagram saved to `docs/images/architecture.png`
- [ ] 21. README: how to run, networking, proxy-to-backend flow, CI/CD overview, permission limits hit, trade-offs, next steps
- [ ] 22. Manual-only `destroy.yml`, final clean run from a fresh push, then submit
