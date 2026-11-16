output "vpc_id" {
  description = "Zero-Trust Enterprise VPC ID"
  value       = aws_vpc.enterprise_vpc.id
}

output "private_subnet_ids" {
  description = "List of isolated private subnet IDs"
  value       = [aws_subnet.private_subnet_az1.id, aws_subnet.private_subnet_az2.id]
}

output "workload_security_group_id" {
  description = "Zero-Trust Workload Security Group ID"
  value       = aws_security_group.workload_zero_trust_sg.id
}
