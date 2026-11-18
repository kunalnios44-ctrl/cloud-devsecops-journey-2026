terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "Primary AWS deployment region"
  default     = "eu-north-1"
}

provider "aws" {
  region = var.aws_region
}

# Dynamic Availability Zones Discovery
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-name"
    values = ["${var.aws_region}a", "${var.aws_region}b"]
  }
}

# 1. Zero-Trust Enterprise VPC
resource "aws_vpc" "enterprise_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "zero-trust-enterprise-vpc"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# 2. Multi-AZ Isolated Private Subnets
resource "aws_subnet" "private_subnet_az1" {
  vpc_id                  = aws_vpc.enterprise_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "isolated-private-subnet-az1"
    Tier = "Zero-Trust-Private"
  }
}

resource "aws_subnet" "private_subnet_az2" {
  vpc_id                  = aws_vpc.enterprise_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "isolated-private-subnet-az2"
    Tier = "Zero-Trust-Private"
  }
}

# 3. Private Route Table & Associations (Isolated Routing)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.enterprise_vpc.id

  tags = {
    Name = "zero-trust-private-rt"
  }
}

resource "aws_route_table_association" "private_az1_assoc" {
  subnet_id      = aws_subnet.private_subnet_az1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_az2_assoc" {
  subnet_id      = aws_subnet.private_subnet_az2.id
  route_table_id = aws_route_table.private_rt.id
}

# 4. Private AWS S3 Gateway VPC Endpoint (Secure Cloud Storage Access)
resource "aws_vpc_endpoint" "s3_private_endpoint" {
  vpc_id            = aws_vpc.enterprise_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]

  tags = {
    Name = "zero-trust-s3-endpoint"
  }
}

# 5. Default Security Group Lockdown
resource "aws_default_security_group" "default_lockdown" {
  vpc_id  = aws_vpc.enterprise_vpc.id
  ingress = []
  egress  = []

  tags = {
    Name = "zero-trust-default-lockdown"
  }
}

# 6. Strict Zero-Trust Workload Security Group (Restricted Egress Only)
resource "aws_security_group" "workload_zero_trust_sg" {
  name        = "zero-trust-workload-sg"
  description = "Blocks all inbound; restricts HTTPS outbound strictly to VPC CIDR and AWS S3 Endpoint"
  vpc_id      = aws_vpc.enterprise_vpc.id

  egress {
    description     = "Allow HTTPS strictly to Private AWS S3 Gateway Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_private_endpoint.prefix_list_id]
  }

  egress {
    description = "Allow internal VPC HTTPS communication"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.enterprise_vpc.cidr_block]
  }

  tags = {
    Name        = "zero-trust-workload-sg"
    Compliance  = "CIS-Hardened"
    Environment = "Production"
  }
}

# 7. Security Monitoring: VPC Flow Logs to CloudWatch
resource "aws_kms_key" "vpc_flow_logs" {
  description             = "Encrypt zero-trust VPC flow logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name              = "/aws/vpc/zero-trust-enterprise-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.vpc_flow_logs.arn
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "zero-trust-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "zero-trust-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_log_group.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogStreams"]
        Resource = aws_cloudwatch_log_group.vpc_flow_log_group.arn
      }
    ]
  })
}

resource "aws_flow_log" "enterprise_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log_group.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.enterprise_vpc.id

  depends_on = [
    aws_iam_role_policy.vpc_flow_log_policy
  ]

  tags = {
    Name = "zero-trust-vpc-flow-logs"
  }
}
