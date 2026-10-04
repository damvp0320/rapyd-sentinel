variable "name" {
  description = "Name of the VPC and prefix for its resources (e.g. vpc-gateway)."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "azs" {
  description = "Availability Zones to spread subnets over. One public subnet, one private subnet and one NAT Gateway are created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two Availability Zones are required."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs of the public subnets (NAT Gateways and internet-facing load balancers), one per AZ, same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must have one entry per AZ."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs of the private subnets (EKS nodes, internal load balancers), one per AZ, same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must have one entry per AZ."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster that will run in this VPC. Used for the kubernetes.io/cluster subnet tag so load balancers can be placed."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
