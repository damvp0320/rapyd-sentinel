# Rapyd Sentinel

Rapyd Sentinel is an imaginary threat intelligence platform. This repository is a **proof of concept (PoC)** of its infrastructure, built for the Rapyd DevOps technical challenge "Sentinel Split Architecture".

The platform is split into two isolated domains:

- **Gateway layer (public):** hosts the internet-facing proxy that receives client traffic.
- **Backend layer (private):** runs the internal service and is never exposed to the internet.

Each domain has its own network and its own Kubernetes cluster, and the two talk to each other privately.

## Contents

- [Architecture](#architecture)
- [What gets built](#what-gets-built)
- [Tech stack](#tech-stack)
- [Repository layout](#repository-layout)
- [How to clone and run the project](#how-to-clone-and-run-the-project)
- [How networking is configured between VPCs and clusters](#how-networking-is-configured-between-vpcs-and-clusters)
- [How the proxy reaches the backend](#how-the-proxy-reaches-the-backend)
- [CI/CD pipeline overview](#cicd-pipeline-overview)
- [Trade-offs and limitations](#trade-offs-and-limitations)
- [What I would improve or add next](#what-i-would-improve-or-add-next)
- [Project documents](#project-documents)

## Architecture

![Rapyd Sentinel architecture](docs/assets/architecture.png)

## What gets built

Everything runs in AWS region **eu-west-3 (Paris)** and is created by Terraform through GitHub Actions.

| Layer | Network | Kubernetes cluster | Workload |
|---|---|---|---|
| Gateway | `vpc-gateway` (10.10.0.0/16) | `eks-gateway` | NGINX reverse proxy behind a public Network Load Balancer |
| Backend | `vpc-backend` (10.20.0.0/16) | `eks-backend` | Simple web service that answers `Hello from backend`, behind an internal Network Load Balancer |

Both VPCs have two public and two private subnets across two Availability Zones, an Internet Gateway, and one NAT Gateway per AZ. The worker nodes (2 x `t3.medium` per cluster) live only in private subnets and have no public IP addresses. The two VPCs are connected with VPC peering.

## Tech stack

- **AWS:** VPC, EKS (managed node groups), NAT and Internet Gateways, Network Load Balancers, VPC peering, IAM, S3
- **Terraform:** reusable modules for networking, peering and EKS, composed by one environment
- **Kubernetes:** plain manifests for the backend and the gateway
- **GitHub Actions:** validation, plan, apply, workload deployment and tests, authenticated to AWS with OIDC

## Repository layout

```
.github/workflows/    CI and deployment pipelines (ci, deploy, bootstrap, destroy)
terraform/
  modules/
    network/          VPC, subnets, route tables, NAT and Internet Gateways
    peering/          VPC peering connection and cross-VPC routes
    eks/              EKS cluster, node group, IAM roles, access entries
  envs/poc/           The environment that wires the modules together
k8s/
  backend/            Backend manifests
  gateway/            Gateway manifests (templates filled in at deploy time)
scripts/              Bootstrap, manifest rendering and exposure checks
docs/                 Project log: progress, results and findings
```

Each Terraform module has typed, validated inputs and explicit outputs (`variables.tf`, `outputs.tf`). `envs/poc` is the only place where the modules are connected: the network module outputs (VPC IDs, subnet IDs, private route table IDs) feed the peering and EKS modules.

## How to clone and run the project

This section is for whoever reviews the project. **You do not need to change anything**: the AWS account, region, resource names, Terraform state bucket, deploy role and GitHub secrets are already set up. You only start the workflow and check the result. Everything is created by GitHub Actions; nobody runs `terraform apply` on a laptop.

### 1. Clone

```bash
git clone https://github.com/damvp0320/rapyd-sentinel.git
cd rapyd-sentinel
```

Cloning is only needed to read the code or run the optional local checks (step 5). The pipeline runs in GitHub, in this repository, and needs write access to the repository to start workflows.

### 2. Run the pipeline

**From the GitHub website:** open the **Actions** tab, select the **deploy** workflow, click **Run workflow**, keep the branch `main` and confirm.

**From the command line** (GitHub CLI, logged in with `gh auth login`):

```bash
gh workflow run deploy.yml --ref main
gh run watch
```

A push to `main` runs the same pipeline. A push to any other branch only runs the checks and a Terraform **plan**; it changes nothing in AWS.

### 3. Check the result

A green `deploy` run means every step passed, including the end-to-end test. The job summaries show the Terraform plan and outputs, the addresses of both load balancers, the request that returned `Hello from backend`, and six PASS lines of exposure checks.

If the infrastructure already exists (it may, from the author's last run), Terraform reports `No changes` and the whole run takes a few minutes; this is the expected result of a repeat run. To watch everything being created from nothing, run the **destroy** workflow first (step 4) and then **deploy** again. A full creation takes about 15 to 20 minutes, mostly the two EKS clusters.

To call the system yourself (needs AWS CLI access to the account and `kubectl`):

```bash
aws eks update-kubeconfig --region eu-west-3 --name eks-gateway
HOST=$(kubectl -n sentinel get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$HOST/
```

Expected output:

```
Hello from backend
```

### 4. Tear everything down

```bash
gh workflow run destroy.yml -f confirm=destroy
gh run watch
```

Or in the Actions tab: **destroy** > **Run workflow** > type `destroy`. It deletes the Kubernetes load balancers first (they would block the VPC deletion) and then runs `terraform destroy`. The state bucket and the deploy role are created once by the bootstrap and are not removed. While running, the environment costs roughly two EKS control planes, four NAT Gateways and four small nodes, so destroy it when you are done.

### 5. Optional: run the checks locally

No AWS credentials needed. On macOS: `brew install hashicorp/tap/terraform terraform-linters/tap/tflint`.

```bash
terraform fmt -check -recursive terraform
cd terraform/envs/poc
terraform init -backend=false
terraform validate
tflint --config ../../../.tflint.hcl
```

### Good to know

- **It runs in this repository.** The AWS deploy role only trusts this repository, so a fork cannot sign in to AWS with it. This is intentional.
- **It needs the challenge AWS account.** If the account or its role has been closed or cleaned up, the `plan` job fails when signing in to AWS.
- **A stale plan is not an error to fix.** If `apply` says `Saved plan is stale`, start a new **deploy** run instead of re-running the old one.
- **The end-to-end test retries for up to 10 minutes** because a new load balancer can take a few minutes to start answering.

## How networking is configured between VPCs and clusters

### The two VPCs

| | `vpc-gateway` | `vpc-backend` |
|---|---|---|
| CIDR | 10.10.0.0/16 | 10.20.0.0/16 |
| Public subnets (NAT Gateways, internet-facing load balancer) | 10.10.1.0/24 (AZ-a), 10.10.2.0/24 (AZ-b) | 10.20.1.0/24 (AZ-a), 10.20.2.0/24 (AZ-b) |
| Private subnets (worker nodes, internal load balancer) | 10.10.11.0/24 (AZ-a), 10.10.12.0/24 (AZ-b) | 10.20.11.0/24 (AZ-a), 10.20.12.0/24 (AZ-b) |
| Availability Zones | eu-west-3a, eu-west-3b | eu-west-3a, eu-west-3b |

The CIDRs do not overlap, which is a requirement for peering. There are no public EC2 instances: the only things in the public subnets are NAT Gateways and, in the gateway VPC, the public load balancer.

### Internet Gateways and NAT Gateways

- **Internet Gateway (one per VPC):** the door between the VPC and the internet. In `vpc-gateway` it also carries inbound client traffic to the public load balancer. In `vpc-backend` it exists only so the NAT Gateways can reach the internet; nothing inbound is allowed and the private subnets have no route to it.
- **NAT Gateway (one per AZ in each VPC, four in total):** lets the private worker nodes start connections to the internet (pulling container images, calling AWS APIs) without being reachable from it. Each private subnet routes through the NAT Gateway in its own AZ, so losing one AZ does not cut outbound access of the other.

### Route tables

| Route table | Destination | Target |
|---|---|---|
| `vpc-gateway-public`, `vpc-backend-public` | 0.0.0.0/0 | the VPC's Internet Gateway |
| `vpc-gateway-private-eu-west-3a` / `-3b` | 0.0.0.0/0 | NAT Gateway in the same AZ |
| | 10.20.0.0/16 | VPC peering connection |
| `vpc-backend-private-eu-west-3a` / `-3b` | 0.0.0.0/0 | NAT Gateway in the same AZ |
| | 10.10.0.0/16 | VPC peering connection |

### VPC peering

`vpc-gateway-to-vpc-backend` is a single peering connection (same account, same region, auto-accepted) between the two VPCs. The `peering` module adds a route to every private route table on both sides, so a pod in either private subnet can reach the other VPC. Public route tables are deliberately not touched. Traffic over the peering link stays on the AWS private network.

### Kubernetes clusters

- `eks-gateway` runs in `vpc-gateway` and `eks-backend` in `vpc-backend`, each with a managed node group (2 x `t3.medium`, Amazon Linux 2023) in the two private subnets.
- The subnets carry the `kubernetes.io/role/elb` (public) and `kubernetes.io/role/internal-elb` (private) tags, so Kubernetes places internet-facing load balancers in public subnets and internal ones in private subnets.
- Cluster access uses EKS access entries (no `aws-auth` ConfigMap). Admin rights are granted explicitly to the CI role and one operator.

### Security groups

Each cluster uses the cluster security group that EKS creates and attaches to its nodes.

- **Backend nodes:** inbound only from the gateway VPC (`10.10.0.0/16`) on the NodePort range, plus load balancer health checks from the backend's own private subnets. Nothing is open to `0.0.0.0/0`. The restriction is enforced twice: an explicit Terraform rule, and Kubernetes `loadBalancerSourceRanges: 10.10.0.0/16` on the backend Service.
- **Gateway nodes:** only the public load balancer's port is open to the internet, which is the intended public entry point.

The pipeline checks this on every run (see [CI/CD](#cicd-pipeline-overview)).

## How the proxy reaches the backend

The path of one request, numbered as in the diagram:

1. **Client to the public load balancer.** The client calls the public Network Load Balancer (internet-facing, in the gateway VPC's public subnets) over the Internet Gateway.
2. **Load balancer to an NGINX pod.** The load balancer forwards to one of the two NGINX proxy pods in `eks-gateway`.
3. **NGINX to the backend over the peering link.** NGINX forwards the request to the DNS name of the backend's **internal** Network Load Balancer. NGINX resolves it through the VPC resolver (`10.10.0.2`) at request time, and the name resolves to private addresses in `10.20.11.x` / `10.20.12.x`. The gateway private route tables send `10.20.0.0/16` to the peering connection, so the request crosses to `vpc-backend` without touching the internet.
4. **Internal load balancer to a backend pod.** The internal load balancer, which exists only in the backend's private subnets, forwards to one of the two backend pods, which answer `Hello from backend`. The answer returns along the same path.

**How the gateway learns the backend address.** The internal load balancer's DNS name only exists after the backend is deployed. The pipeline deploys the backend first, waits until its Service has a hostname, and passes it to the gateway job. `scripts/render-gateway.sh` fills it into the gateway templates (`*.yaml.tpl`) with `envsubst` before they are applied. The hostname is also written as a pod annotation, so a changed address restarts the gateway pods automatically.

**Why plain Kubernetes Services.** A `LoadBalancer` Service with the NLB annotations creates both load balancers through EKS's built-in support, using only the cluster IAM role. No extra controller or IAM roles were needed, which suited the restricted permissions of this account.

## CI/CD pipeline overview

Four GitHub Actions workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci` | every push and pull request | `terraform fmt -check`, `terraform validate` for every module and the environment, `tflint` (recommended preset), `kubeconform` on the Kubernetes manifests. No AWS access. |
| `deploy` | every push (docs-only changes ignored) and manual run | The full pipeline below. Apply and deployment run only on `main`. |
| `bootstrap` | manual, one time | Creates the Terraform state bucket and the deploy role, and prints PASS/DENIED for each permission it tests. |
| `destroy` | manual, requires typing `destroy` | Deletes the Kubernetes load balancers, then runs `terraform destroy`. |

**The `deploy` workflow, in order:**

1. `plan`: signs in to AWS with OIDC, runs `init`, `validate` and `plan`, shows the plan in the job summary and uploads it as an artifact.
2. `apply`: applies exactly that saved plan (main only).
3. `deploy-backend`: server-side dry run of the manifests against the real cluster, apply, wait for the rollout, wait for the internal load balancer hostname.
4. `deploy-gateway`: render the templates with the backend hostname, dry run, apply, wait for the rollout and the public load balancer hostname.
5. `e2e-test`: calls the public load balancer until it returns `Hello from backend`, then runs `scripts/verify-exposure.sh`, which fails the pipeline if the backend is ever reachable from the internet. It asserts that the backend load balancer is internal, the gateway one is internet-facing, no backend security group allows `0.0.0.0/0`, the backend only allows `10.10.0.0/16`, no instance has a public IP, and the backend does not answer from outside the VPC.

**Design choices**

- **Keyless AWS access.** The jobs assume a role through GitHub OIDC; no long-lived AWS keys are used by the pipeline. The deploy role is scoped to this repository and can only manage `eks-damian-*` and `sentinel-damian-*` IAM roles.
- **Plan then apply the same plan.** What was reviewed is what is applied.
- **A running deploy is never cancelled** (stopping an apply halfway can leave infrastructure half built).
- **State** is in an S3 bucket (versioned, encrypted) with S3-native locking.

## Trade-offs and limitations

This section has three parts: the design **trade-offs** I chose on purpose, the **limitations** that come from the time limit, and the **permission limits** of the challenge account. The detailed log is in [docs/FINDINGS.md](docs/FINDINGS.md).

### Trade-offs (deliberate design choices)

| Choice | Why | What it costs |
|---|---|---|
| Kubernetes API endpoint is public and private | GitHub-hosted runners are outside the VPC and need it to run `kubectl`. It is IAM-authenticated. | Weaker than a private endpoint with self-hosted runners. |
| One NAT Gateway per AZ (four in total) | Losing an AZ does not cut outbound access of the other. | Higher cost than one NAT Gateway per VPC. |
| In-tree Kubernetes load balancer support instead of the AWS Load Balancer Controller | Works with the cluster IAM role only, no extra controller or IAM roles. Fits the restricted permissions. | Older and with fewer features (for example no ALB, no target type `ip`). |
| VPC peering between the two VPCs | The simplest private link for exactly two VPCs. | Does not scale to many VPCs (no transitive routing). |
| Bootstrap as a shell script, not Terraform | Avoids the chicken-and-egg of storing the bootstrap's own state, and doubles as a permission probe. | Not declarative. |
| Plain manifests with `envsubst` templates instead of Helm or Kustomize | Few moving parts and easy to read for a small project. | Less flexible for several environments. |
| Apply on every push to `main`, with no manual approval step | Fast feedback for a proof of concept. | No human gate before changing infrastructure. |
| Explicit EKS admin access entries | The identity that runs Terraform is not the only admin, so switching from static keys to OIDC does not lock anyone out. | Admin principals must be listed in `terraform.tfvars`. |

### Limitations due to the time limit

Things that were left out or kept minimal because of the time available:

- **HTTP only.** No TLS between the client and the gateway, or between the gateway and the backend.
- **No NetworkPolicy, service mesh or observability.** Isolation relies on the VPC, routes and security groups; there are no dashboards, centralised logs or alerts.
- **Minimal application.** The backend and the proxy are stock NGINX images with default security settings (running as root), two fixed replicas each, no autoscaling and no pod disruption budgets.
- **Single environment.** One `poc` environment and one Terraform state; no staging or production.
- **Static AWS keys remain as repository secrets.** Only the one-time bootstrap workflow uses them; the deploy pipeline uses OIDC. Moving the bootstrap to OIDC as well was not done.
- **Limited linting and testing.** The AWS-specific tflint rules are not enabled (they download a plugin at run time), and `kubeconform` validates against the Kubernetes 1.31 schemas while the clusters run 1.35; the server-side dry run covers the real API. There are no unit tests or policy checks, only the end-to-end test and the exposure checks.
- **Simplified diagram.** No resource IDs, load balancers drawn as single icons, no legend.

### Permission limits of the challenge account (documented, not bypassed)

| Limit | Effect and what a real environment would do |
|---|---|
| `servicequotas:GetServiceQuota` is denied | The Elastic IP quota could not be checked before creating four NAT Gateways. A real environment would grant read access and raise quotas up front. |
| `iam:UpdateAssumeRolePolicy` is denied | A mistake in the deploy role's trust policy could not be fixed in place, so a new role (`sentinel-damian-gha-v2`) was created. The role would normally be managed in Terraform. |
| `iam:DeleteRolePolicy` is denied | The superseded role could not be removed and remains unused. An administrator would delete it. |
| The account is shared and IAM role names are global | All names carry a `damian` segment to avoid collisions. Normally there is one account per environment. |
| The repository uses GitHub's immutable OIDC subject claim | The first OIDC sign-in failed; the trust policy now accepts both subject formats for this repository only. |

## What I would improve or add next

- **TLS everywhere:** an ACM certificate and a TLS listener on the public load balancer, and encryption between gateway and backend.
- **NetworkPolicy:** default-deny in both clusters, allowing only gateway to backend on the application port.
- **Service mesh / mTLS:** for identity and encrypted traffic between services.
- **Observability:** metrics and dashboards (Prometheus and Grafana or CloudWatch Container Insights), centralised logs, VPC Flow Logs and alerting on the load balancers and nodes.
- **AWS Load Balancer Controller** with IAM roles for service accounts, to get ALBs, WAF integration and target type `ip`.
- **Private Kubernetes API** with self-hosted runners inside the VPC, and no static AWS keys anywhere (bootstrap through OIDC as well).
- **Deployment gating:** a protected `production` environment with manual approval before `apply`, and pull-request plans posted as comments.
- **Hardening:** non-root, read-only containers, Pod Security Standards, pinned and scanned images, a WAF in front of the gateway.
- **Scaling and cost:** horizontal pod autoscaling and Karpenter, spot nodes for non-critical workloads, and a single NAT Gateway in non-production environments.
- **Bootstrap and structure:** manage the state bucket and deploy role in a separate Terraform stack, add `staging`/`prod` environments, and move to Transit Gateway or PrivateLink if more VPCs are added.
- **Testing:** Terraform tests (`terraform test`), policy checks (for example Checkov or OPA) and smoke tests after each deployment.

## Project documents

- [docs/PROGRESS.md](docs/PROGRESS.md): the checklist of stages and activities.
- [docs/RESULTS.md](docs/RESULTS.md): what happened in each activity, with a summary per stage.
- [docs/FINDINGS.md](docs/FINDINGS.md): permission limits, surprises and design decisions found along the way.
