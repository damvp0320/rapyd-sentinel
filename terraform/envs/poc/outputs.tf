output "gateway_vpc_id" {
  description = "ID of vpc-gateway."
  value       = module.network_gateway.vpc_id
}

output "backend_vpc_id" {
  description = "ID of vpc-backend."
  value       = module.network_backend.vpc_id
}

output "peering_connection_id" {
  description = "ID of the VPC peering connection."
  value       = module.peering.peering_connection_id
}

output "peering_status" {
  description = "Status of the VPC peering connection (expected: active)."
  value       = module.peering.peering_status
}

output "gateway_cluster_name" {
  description = "Name of the gateway EKS cluster."
  value       = module.eks_gateway.cluster_name
}

output "backend_cluster_name" {
  description = "Name of the backend EKS cluster."
  value       = module.eks_backend.cluster_name
}

output "gateway_cluster_endpoint" {
  description = "Kubernetes API endpoint of eks-gateway."
  value       = module.eks_gateway.cluster_endpoint
}

output "backend_cluster_endpoint" {
  description = "Kubernetes API endpoint of eks-backend."
  value       = module.eks_backend.cluster_endpoint
}

output "backend_cluster_security_group_id" {
  description = "Security group of the backend nodes (inspected when verifying the cross-VPC restriction)."
  value       = module.eks_backend.cluster_security_group_id
}

output "nat_public_ips" {
  description = "Egress IPs of the NAT Gateways per VPC."
  value = {
    gateway = module.network_gateway.nat_public_ips
    backend = module.network_backend.nat_public_ips
  }
}

output "kubeconfig_commands" {
  description = "Commands to configure kubectl for each cluster."
  value = {
    gateway = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_gateway.cluster_name}"
    backend = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_backend.cluster_name}"
  }
}
