variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-3"
}

variable "gateway_vpc_cidr" {
  description = "CIDR block of vpc-gateway."
  type        = string
  default     = "10.10.0.0/16"
}

variable "backend_vpc_cidr" {
  description = "CIDR block of vpc-backend."
  type        = string
  default     = "10.20.0.0/16"
}

variable "admin_principal_arns" {
  description = "IAM role/user ARNs given cluster-admin on both clusters (the CI role and a human operator), keyed by a short static name."
  type        = map(string)
  default     = {}
}

variable "kubernetes_version" {
  description = "Kubernetes version of both clusters."
  type        = string
  default     = "1.35"
}

variable "tags" {
  description = "Tags applied to every resource through the provider default_tags."
  type        = map(string)
  default = {
    Project   = "rapyd-sentinel"
    ManagedBy = "terraform"
  }
}
