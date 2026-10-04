output "peering_connection_id" {
  description = "ID of the VPC peering connection."
  value       = aws_vpc_peering_connection.this.id
}

output "peering_status" {
  description = "Status of the peering connection (expected: active)."
  value       = aws_vpc_peering_connection.this.accept_status
}
