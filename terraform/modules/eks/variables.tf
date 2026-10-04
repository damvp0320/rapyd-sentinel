variable "cluster_name" {
  description = "Name of the EKS cluster (e.g. eks-gateway)."
  type        = string
}

variable "role_name_prefix" {
  description = "Prefix of the IAM roles created for this cluster. Must start with eks- to satisfy the account's IAM restrictions (e.g. eks-damian-gateway)."
  type        = string

  validation {
    condition     = startswith(var.role_name_prefix, "eks-")
    error_message = "role_name_prefix must start with \"eks-\"."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane."
  type        = string
  default     = "1.35"
}

variable "private_subnet_ids" {
  description = "Private subnets (different AZs) for the control plane ENIs and the worker nodes."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnets in different AZs are required."
  }
}

variable "endpoint_public_access" {
  description = "Whether the Kubernetes API endpoint is reachable from the internet. Needed so GitHub-hosted runners can run kubectl; the endpoint stays IAM-authenticated."
  type        = bool
  default     = true
}

variable "admin_principal_arns" {
  description = "IAM role/user ARNs given cluster-admin through EKS access entries (e.g. the CI role and a human operator), keyed by a short static name."
  type        = map(string)
  default     = {}
}

variable "instance_types" {
  description = "EC2 instance types of the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the worker nodes on node_port_range (NodePorts behind the load balancer). Empty for the gateway; the gateway VPC CIDR for the backend."
  type        = list(string)
  default     = []
}

variable "node_port_range" {
  description = "Kubernetes NodePort range opened for allowed_ingress_cidrs."
  type = object({
    from = number
    to   = number
  })
  default = {
    from = 30000
    to   = 32767
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
