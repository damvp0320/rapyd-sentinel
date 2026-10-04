# How to clone and run the project

This guide is for whoever reviews the project. **You do not need to change anything**: the AWS account, region, resource names, state bucket, deploy role and GitHub secrets are already set up. You only start the workflow and check the result.

Everything is created by GitHub Actions. Nobody runs `terraform apply` on a laptop.

## What you need

- Access to this GitHub repository with permission to run workflows (write access).
- Nothing else for the pipeline itself: it signs in to AWS with a role through GitHub OIDC, using the repository's existing configuration.
- Optional, only if you want to look at the clusters or run the checks locally: `git`, the `aws` CLI, `kubectl`, `terraform` (1.10 or newer) and `tflint`.

## 1. Clone

```bash
git clone https://github.com/damvp0320/rapyd-sentinel.git
cd rapyd-sentinel
```

Cloning is only needed to read the code or run the local checks in step 6. The pipeline runs in GitHub.

## 2. Run the pipeline

Choose one:

**From the GitHub website**

1. Open the repository's **Actions** tab.
2. Select the **deploy** workflow.
3. Click **Run workflow**, keep the branch `main`, and confirm.

**From the command line** (GitHub CLI, logged in with `gh auth login`)

```bash
gh workflow run deploy.yml --ref main
gh run watch
```

A push to `main` runs the same pipeline. Pushing to any other branch only runs the checks and a Terraform **plan**, it changes nothing in AWS.

## 3. What happens

The `deploy` workflow runs these jobs in order:

| Job | What it does |
|---|---|
| `plan` | Signs in to AWS with OIDC, runs `terraform init`, `validate` and `plan`, and shows the plan in the job summary |
| `apply` | Applies exactly that saved plan (two VPCs, VPC peering, two EKS clusters) |
| `deploy-backend` | Validates and deploys the backend to `eks-backend`, then waits for its internal load balancer |
| `deploy-gateway` | Fills in the backend address, validates and deploys the proxy to `eks-gateway`, then waits for the public load balancer |
| `e2e-test` | Calls the public load balancer until it returns `Hello from backend`, then checks that the backend is not exposed |

The separate `ci` workflow runs on every push as well: `terraform fmt`, `validate`, `tflint` and `kubeconform`.

**How long it takes**

- If the infrastructure already exists (it may, from the author's last run), Terraform reports no changes and the whole run takes a few minutes.
- To watch everything being created from nothing, run the **destroy** workflow first (step 5), then **deploy**. A full creation takes about 15 to 20 minutes, mostly the two EKS clusters.

## 4. Check the result

**In GitHub (nothing to install)**

Open the finished run. A green run means every step passed, including the end-to-end test. The job summaries show:

- the Terraform plan (`plan` job) and the outputs (`apply` job);
- the backend internal load balancer and the public gateway load balancer addresses;
- the `e2e-test` output: the request that returned `Hello from backend`, and six PASS lines for the exposure checks (backend load balancer internal, gateway load balancer internet-facing, no security group open to `0.0.0.0/0` in the backend VPC, backend allows only the gateway VPC `10.10.0.0/16`, no instance with a public IP, backend not reachable from the internet).

**Yourself, from a terminal** (needs AWS CLI access to the account)

```bash
aws eks update-kubeconfig --region eu-west-3 --name eks-gateway
HOST=$(kubectl -n sentinel get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$HOST/
```

Expected output:

```
Hello from backend
```

That answer comes from a pod in the backend cluster, reached through the gateway proxy over the VPC peering link.

## 5. Tear everything down

```bash
gh workflow run destroy.yml -f confirm=destroy
gh run watch
```

Or in the Actions tab: **destroy** → **Run workflow** → type `destroy`. It deletes the Kubernetes load balancers first (they would block the VPC deletion) and then runs `terraform destroy`. Run **deploy** again afterwards to recreate everything.

The state bucket and the deploy role are created once by the bootstrap and are not removed by destroy.

## 6. Optional: run the checks locally

No AWS credentials needed:

```bash
terraform fmt -check -recursive terraform
cd terraform/envs/poc
terraform init -backend=false
terraform validate
tflint --config ../../../.tflint.hcl
```

On macOS, install the tools with `brew install hashicorp/tap/terraform terraform-linters/tap/tflint`.

## Good to know

- **It runs in this repository.** The AWS deploy role only trusts this repository, so a fork cannot sign in to AWS with it. This is intentional. Running the project from a copy would require creating a new role and changing the names; that is outside this guide.
- **It needs the challenge AWS account.** The pipeline depends on that account and its role still existing. If the account has been closed or cleaned up, the `plan` job fails when signing in to AWS.
- **Cost while running:** two EKS control planes, four NAT Gateways and four small nodes. Destroy it when you are done.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `plan` fails at "Configure AWS credentials" | The AWS role or account is not available any more (see "Good to know"). |
| `apply` reports `AddressLimitExceeded` | The Elastic IP quota is too low for 4 NAT Gateways. Request an increase. |
| `Saved plan is stale` on `apply` | Do not re-run an old failed run. Start a new **deploy** run so a fresh plan is created. |
| `e2e-test` retries for several minutes | A new load balancer can take a few minutes to start answering. It retries for up to 10 minutes before failing. |
| "Run workflow" button missing | You need write access to the repository. |
