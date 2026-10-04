data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ---------------------------------------------------------------------------
# Networking: two isolated VPCs
# ---------------------------------------------------------------------------
module "network_gateway" {
  source = "../../modules/network"

  name                 = "vpc-gateway"
  cidr_block           = var.gateway_vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]
  cluster_name         = "eks-gateway"
}

module "network_backend" {
  source = "../../modules/network"

  name                 = "vpc-backend"
  cidr_block           = var.backend_vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]
  cluster_name         = "eks-backend"
}

# ---------------------------------------------------------------------------
# Private connectivity between the VPCs
# ---------------------------------------------------------------------------
module "peering" {
  source = "../../modules/peering"

  name = "vpc-gateway-to-vpc-backend"

  requester_vpc_id          = module.network_gateway.vpc_id
  requester_cidr_block      = module.network_gateway.vpc_cidr_block
  requester_route_table_ids = module.network_gateway.private_route_table_ids

  accepter_vpc_id          = module.network_backend.vpc_id
  accepter_cidr_block      = module.network_backend.vpc_cidr_block
  accepter_route_table_ids = module.network_backend.private_route_table_ids
}

# ---------------------------------------------------------------------------
# Kubernetes clusters, one per VPC
# ---------------------------------------------------------------------------
module "eks_gateway" {
  source = "../../modules/eks"

  cluster_name         = "eks-gateway"
  role_name_prefix     = "eks-damian-gateway"
  kubernetes_version   = var.kubernetes_version
  private_subnet_ids   = module.network_gateway.private_subnet_ids
  admin_principal_arns = var.admin_principal_arns
}

module "eks_backend" {
  source = "../../modules/eks"

  cluster_name         = "eks-backend"
  role_name_prefix     = "eks-damian-backend"
  kubernetes_version   = var.kubernetes_version
  private_subnet_ids   = module.network_backend.private_subnet_ids
  admin_principal_arns = var.admin_principal_arns

  # Only the gateway VPC may reach the backend nodes (NodePorts behind the internal NLB).
  allowed_ingress_cidrs = [module.network_gateway.vpc_cidr_block]
}
