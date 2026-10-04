# How to clone and run the project

This guide takes you from a fresh clone to a working deployment in your own AWS account. The infrastructure is created **only by GitHub Actions**. You never run `terraform apply` on your machine.

Expect about 15 to 20 minutes for the first deployment, and a running cost of roughly the following while it is up: 2 EKS control planes (about $0.10/hour each), 4 NAT Gateways (about $0.045/hour each plus data) and 4 `t3.medium` nodes. Destroy it when you are done (see the last step).

## 1. Prerequisites

**Accounts and access**

- An AWS account and an IAM user (or role) with access keys that can create: an S3 bucket, IAM roles named `eks-*` and `sentinel-*` (with AWS managed policies attached), VPCs and related networking, EKS clusters, and load balancers.
- A GitHub account where you can create a repository with Actions enabled.
- The GitHub OIDC provider (`token.actions.githubusercontent.com`) must already exist in the AWS account. The bootstrap script only looks it up, it does not create it. If your account does not have it yet, create it once:

  ```bash
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com
  ```

**Tools on your machine**

| Tool | Needed for |
|---|---|
| `git` | cloning |
| [`gh`](https://cli.github.com/) (GitHub CLI), logged in with `gh auth login` | creating the repo, secrets and variables, running workflows |
| `aws` CLI | optional, to inspect the result |
| `kubectl` | optional, to inspect the clusters |
| `terraform` 1.10 or newer and `tflint` | optional, to run the checks locally |

On macOS, Terraform is not in Homebrew core any more:

```bash
brew install hashicorp/tap/terraform
brew install terraform-linters/tap/tflint
```

## 2. Clone and create your own repository

The pipeline runs in the repository you push to, so work in your own copy:

```bash
git clone https://github.com/damvp0320/rapyd-sentinel.git
cd rapyd-sentinel
gh repo create rapyd-sentinel --private --source=. --remote=mine --push
```

(The original repository is private, so you need access to it, or a copy of the code, to clone.)

## 3. Adapt the account-specific names

Several names are global or tied to one account. Change these before the first run:

| What | Where | Why |
|---|---|---|
| `damian` in the IAM role names (`eks-damian-gateway`, `eks-damian-backend`) | `role_name_prefix` in [terraform/envs/poc/main.tf](../terraform/envs/poc/main.tf) | IAM role names are global in the account. Keep the `eks-` prefix. |
| `damian` in the deploy role and state bucket (`sentinel-damian-gha-v2`, `sentinel-tfstate-damian-<account>`) | [scripts/bootstrap.sh](../scripts/bootstrap.sh) (`ROLE_NAME`, `STATE_BUCKET`) | Same reason. Keep the `sentinel-` prefix. |
| `eks-damian-*` and `sentinel-damian-*` role patterns | [scripts/policies/gha-permissions.json](../scripts/policies/gha-permissions.json) | The deploy role may only manage roles that match these patterns. They must match the names above. |
| Account ID and user in the admin ARNs | [terraform/envs/poc/terraform.tfvars](../terraform/envs/poc/terraform.tfvars) | These principals get cluster-admin on both clusters. Use your CI role ARN and your own IAM user. |
| Region `eu-west-3` | `region` in [terraform/envs/poc/variables.tf](../terraform/envs/poc/variables.tf) and the `backend "s3"` block in [terraform/envs/poc/versions.tf](../terraform/envs/poc/versions.tf) | Change both together if you use another region. |

The gateway's NGINX config hardcodes the VPC DNS resolver `10.10.0.2` (the gateway VPC base address plus 2) in [k8s/gateway/configmap.yaml.tpl](../k8s/gateway/configmap.yaml.tpl). Change it only if you change `gateway_vpc_cidr`.

Commit the changes to `main` of your repository.

## 4. Configure GitHub

The bootstrap workflow needs AWS access keys. Everything after it uses OIDC, with no long-lived keys.

```bash
gh secret set AWS_ACCESS_KEY_ID
gh secret set AWS_SECRET_ACCESS_KEY
gh variable set AWS_REGION --body "eu-west-3"
```

`gh secret set` prompts for the value, so the key does not end up in your shell history.

## 5. Run the bootstrap (once)

The bootstrap workflow creates the Terraform state bucket and the deploy role that the pipeline assumes through OIDC. It also prints PASS or DENIED for each permission it tests.

```bash
gh workflow run bootstrap.yml
gh run watch
```

At the end of the log it prints two values. Save them as repository variables:

```bash
gh variable set STATE_BUCKET --body "<value of STATE_BUCKET>"
gh variable set AWS_ROLE_ARN --body "<value of ROLE_ARN>"
```

If a step shows `DENIED`, your AWS user lacks that permission. [FINDINGS.md](FINDINGS.md) lists the limits we hit and the workarounds.

## 6. Deploy

Pushing to a branch only runs checks and a Terraform **plan**. Pushing or merging to `main` runs the whole pipeline: plan, apply, deploy the backend, deploy the gateway, and the end-to-end test.

```bash
git push mine main
gh run watch
```

Documentation-only changes (`docs/**`, `*.md`) do not trigger a deployment.

When the run is green, the job summary shows the public load balancer hostname and the results of the checks.

## 7. Verify it works

Get the public address of the gateway and call it:

```bash
aws eks update-kubeconfig --region eu-west-3 --name eks-gateway
HOST=$(kubectl -n sentinel get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$HOST/
```

Expected output:

```
Hello from backend
```

That response comes from a pod in the backend cluster, reached through the gateway. The pipeline performs this same request and the exposure checks automatically (the `e2e-test` job).

You can also look at the pieces:

```bash
kubectl -n sentinel get deploy,pods,svc                 # gateway cluster
aws eks update-kubeconfig --region eu-west-3 --name eks-backend
kubectl -n sentinel get deploy,pods,svc                 # backend cluster
```

## 8. Optional: run the checks locally

These need no AWS credentials:

```bash
terraform fmt -check -recursive terraform
cd terraform/envs/poc && terraform init -backend=false && terraform validate
tflint --config ../../../.tflint.hcl
```

The same checks run in GitHub on every push (`ci.yml`).

## 9. Tear everything down

```bash
gh workflow run destroy.yml -f confirm=destroy
gh run watch
```

The workflow first deletes the Kubernetes load balancers (otherwise they block the VPC deletion), then runs `terraform destroy`.

It does **not** remove what the bootstrap created: the state bucket and the deploy role. Delete those by hand when you no longer need them.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The role trust policy does not match your repository's OIDC subject. The bootstrap trusts both the plain and the immutable subject formats for the repository it runs in. If the trust policy is wrong and your user cannot edit it (`iam:UpdateAssumeRolePolicy`), create a new role name in `bootstrap.sh`. |
| `AddressLimitExceeded` during apply | The account's Elastic IP quota is too low for 4 NAT Gateways. Request an increase, or reduce to one NAT Gateway per VPC in the `network` module. |
| Node group fails with `missing permissions for 'iam:GetRole'` | The deploy role must be allowed `iam:GetRole` on `arn:aws:iam::*:role/aws-service-role/*`. This is already in [gha-permissions.json](../scripts/policies/gha-permissions.json). Re-run the bootstrap to refresh the role policy. |
| `Saved plan is stale` | Never re-run an old failed run. Push a new commit so a fresh plan is created. |
| Role name already exists | IAM role names are global. Change the `damian` segment (step 3). |
