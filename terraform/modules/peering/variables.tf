variable "name" {
  description = "Name of the peering connection (e.g. vpc-gateway-to-vpc-backend)."
  type        = string
}

variable "requester_vpc_id" {
  description = "ID of the VPC that requests the peering (gateway)."
  type        = string
}

variable "requester_cidr_block" {
  description = "CIDR block of the requester VPC. Routed from the accepter's private route tables."
  type        = string
}

variable "requester_route_table_ids" {
  description = "Private route tables of the requester VPC. Each receives a route to the accepter CIDR."
  type        = list(string)
}

variable "accepter_vpc_id" {
  description = "ID of the VPC that accepts the peering (backend). Must be in the same account and region."
  type        = string
}

variable "accepter_cidr_block" {
  description = "CIDR block of the accepter VPC. Routed from the requester's private route tables."
  type        = string
}

variable "accepter_route_table_ids" {
  description = "Private route tables of the accepter VPC. Each receives a route to the requester CIDR."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
