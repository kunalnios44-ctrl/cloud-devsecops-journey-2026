# ==========================================
# OUTPUTS FOR GLOBAL MULTI-REGION INFRASTRUCTURE
# ==========================================

# --- EUROPE REGION (PRIMARY) OUTPUTS ---

output "primary_vpc_id" {
  description = "VPC ID for Primary Region (Europe)"
  value       = aws_vpc.primary_vpc.id
}

output "primary_public_subnets" {
  description = "Public Subnet IDs in Primary Region"
  value       = [aws_subnet.primary_public_1a.id, aws_subnet.primary_public_1b.id]
}

output "primary_private_subnets" {
  description = "Private Subnet IDs in Primary Region"
  value       = [aws_subnet.primary_private_1a.id, aws_subnet.primary_private_1b.id]
}

output "primary_security_group_id" {
  description = "Security Group ID in Primary Region"
  value       = aws_security_group.primary_sg.id
}


# --- INDIA REGION (DISASTER RECOVERY) OUTPUTS ---

output "secondary_vpc_id" {
  description = "VPC ID for Secondary/DR Region (India)"
  value       = aws_vpc.secondary_vpc.id
}

output "secondary_public_subnets" {
  description = "Public Subnet IDs in Secondary Region"
  value       = [aws_subnet.secondary_public_1a.id, aws_subnet.secondary_public_1b.id]
}

output "secondary_private_subnets" {
  description = "Private Subnet IDs in Secondary Region"
  value       = [aws_subnet.secondary_private_1a.id, aws_subnet.secondary_private_1b.id]
}

output "secondary_security_group_id" {
  description = "Security Group ID in Secondary Region"
  value       = aws_security_group.secondary_sg.id
}
