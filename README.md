# Rapyd Sentinel

Rapyd Sentinel is an imaginary threat intelligence platform. This repository is a **proof of concept (PoC)** of its infrastructure, built for the Rapyd DevOps technical challenge "Sentinel Split Architecture".

The platform is split into two isolated domains:

- **Gateway layer (public):** hosts the internet-facing proxy that receives client traffic.
- **Backend layer (private):** runs the internal service and is never exposed to the internet.

Each domain has its own network and its own Kubernetes cluster, and the two talk to each other privately.

## Architecture

![Rapyd Sentinel architecture](docs/assets/architecture.png)

## What gets built

Everything runs in AWS region **eu-west-3 (Paris)** and is created by Terraform through GitHub Actions.

| Layer | Network | Kubernetes cluster | Workload |
|---|---|---|---|
| Gateway | `vpc-gateway` (10.10.0.0/16) | `eks-gateway` | NGINX reverse proxy behind a public Network Load Balancer |
| Backend | `vpc-backend` (10.20.0.0/16) | `eks-backend` | Simple web service that answers `Hello from backend`, behind an internal Network Load Balancer |

Both VPCs have two public and two private subnets across two Availability Zones, an Internet Gateway, and one NAT Gateway per AZ. The worker nodes live only in private subnets and have no public IP addresses. The two VPCs are connected with VPC peering.

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

## Project documents

- [docs/HOW-TO-RUN.md](docs/HOW-TO-RUN.md): how to clone the repository and run the project in your own AWS account.
- [docs/PROGRESS.md](docs/PROGRESS.md): the checklist of stages and activities.
- [docs/RESULTS.md](docs/RESULTS.md): what happened in each activity, with a summary per stage.
- [docs/FINDINGS.md](docs/FINDINGS.md): permission limits, surprises and design decisions found along the way.
