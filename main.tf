# ==========================================
# AWS MULTI-REGION NETWORK LAB
# Illustrative Terraform configuration; validation does not mean deployed or production-ready
# ==========================================

terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Modern Native S3 Locking (No DynamoDB needed)
  backend "s3" {
    bucket       = "REPLACE_WITH_EXISTING_TERRAFORM_STATE_BUCKET"
    key          = "global-infra/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  alias  = "europe"
  region = var.primary_region
}

provider "aws" {
  alias  = "india"
  region = var.secondary_region
}

# Discover available zones in each configured region
data "aws_availability_zones" "europe" {
  provider = aws.europe
  state    = "available"
  filter {
    name   = "zone-name"
    values = ["${var.primary_region}a", "${var.primary_region}b"]
  }
}

data "aws_availability_zones" "secondary" {
  provider = aws.india
  state    = "available"
  filter {
    name   = "zone-name"
    values = ["${var.secondary_region}a", "${var.secondary_region}b"]
  }
}

# ==========================================
# 1. EUROPE REGION (PRIMARY)
# ==========================================

resource "aws_vpc" "primary_vpc" {
  provider             = aws.europe
  cidr_block           = var.primary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "primary-vpc-eu", Environment = var.environment }
}

resource "aws_internet_gateway" "primary_igw" {
  provider = aws.europe
  vpc_id   = aws_vpc.primary_vpc.id
  tags     = { Name = "primary-igw-eu" }
}

# Multi-AZ Public Subnets (Zone A & Zone B)
resource "aws_subnet" "primary_public_1a" {
  provider                = aws.europe
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.europe.names[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "primary-public-eu-1a" }
}

resource "aws_subnet" "primary_public_1b" {
  provider                = aws.europe
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.europe.names[1]
  map_public_ip_on_launch = false
  tags                    = { Name = "primary-public-eu-1b" }
}

# Multi-AZ Private Subnets (Zone A & Zone B)
resource "aws_subnet" "primary_private_1a" {
  provider          = aws.europe
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.europe.names[0]
  tags              = { Name = "primary-private-eu-1a" }
}

resource "aws_subnet" "primary_private_1b" {
  provider          = aws.europe
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.europe.names[1]
  tags              = { Name = "primary-private-eu-1b" }
}

# Public Route Table & Associations
resource "aws_route_table" "primary_public_rt" {
  provider = aws.europe
  vpc_id   = aws_vpc.primary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_igw.id
  }
  tags = { Name = "primary-public-rt-eu" }
}

resource "aws_route_table_association" "primary_pub_assoc_1a" {
  provider       = aws.europe
  subnet_id      = aws_subnet.primary_public_1a.id
  route_table_id = aws_route_table.primary_public_rt.id
}

resource "aws_route_table_association" "primary_pub_assoc_1b" {
  provider       = aws.europe
  subnet_id      = aws_subnet.primary_public_1b.id
  route_table_id = aws_route_table.primary_public_rt.id
}

# Dedicated Private Route Table (Isolated Internal Routing)
resource "aws_route_table" "primary_private_rt" {
  provider = aws.europe
  vpc_id   = aws_vpc.primary_vpc.id
  tags     = { Name = "primary-private-rt-eu" }
}

resource "aws_route_table_association" "primary_priv_assoc_1a" {
  provider       = aws.europe
  subnet_id      = aws_subnet.primary_private_1a.id
  route_table_id = aws_route_table.primary_private_rt.id
}

resource "aws_route_table_association" "primary_priv_assoc_1b" {
  provider       = aws.europe
  subnet_id      = aws_subnet.primary_private_1b.id
  route_table_id = aws_route_table.primary_private_rt.id
}

# Example security group; review ingress and egress before deployment
#checkov:skip=CKV2_AWS_5: Standalone network lab template; no compute ENI is defined in this configuration.
resource "aws_security_group" "primary_sg" {
  provider    = aws.europe
  name        = "primary-example-sg"
  description = "Example HTTPS ingress policy for a separately managed workload"
  vpc_id      = aws_vpc.primary_vpc.id

  ingress {
    description = "Example inbound HTTPS access from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Controlled outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
  }

  tags = { Name = "primary-example-sg" }
}


# ==========================================
# 2. SECONDARY REGION (EXAMPLE NETWORK ONLY; NOT DISASTER RECOVERY)
# ==========================================

resource "aws_vpc" "secondary_vpc" {
  provider             = aws.india
  cidr_block           = var.secondary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "secondary-vpc-example", Environment = var.environment }
}

resource "aws_internet_gateway" "secondary_igw" {
  provider = aws.india
  vpc_id   = aws_vpc.secondary_vpc.id
  tags     = { Name = "secondary-igw-in" }
}

# Multi-AZ Public Subnets (Zone A & Zone B)
resource "aws_subnet" "secondary_public_1a" {
  provider                = aws.india
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = data.aws_availability_zones.secondary.names[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "secondary-public-in-1a" }
}

resource "aws_subnet" "secondary_public_1b" {
  provider                = aws.india
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = data.aws_availability_zones.secondary.names[1]
  map_public_ip_on_launch = false
  tags                    = { Name = "secondary-public-in-1b" }
}

# Multi-AZ Private Subnets (Zone A & Zone B)
resource "aws_subnet" "secondary_private_1a" {
  provider          = aws.india
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.10.0/24"
  availability_zone = data.aws_availability_zones.secondary.names[0]
  tags              = { Name = "secondary-private-in-1a" }
}

resource "aws_subnet" "secondary_private_1b" {
  provider          = aws.india
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = data.aws_availability_zones.secondary.names[1]
  tags              = { Name = "secondary-private-in-1b" }
}

# Public Route Table & Associations
resource "aws_route_table" "secondary_public_rt" {
  provider = aws.india
  vpc_id   = aws_vpc.secondary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary_igw.id
  }
  tags = { Name = "secondary-public-rt-in" }
}

resource "aws_route_table_association" "secondary_pub_assoc_1a" {
  provider       = aws.india
  subnet_id      = aws_subnet.secondary_public_1a.id
  route_table_id = aws_route_table.secondary_public_rt.id
}

resource "aws_route_table_association" "secondary_pub_assoc_1b" {
  provider       = aws.india
  subnet_id      = aws_subnet.secondary_public_1b.id
  route_table_id = aws_route_table.secondary_public_rt.id
}

# Dedicated Private Route Table
resource "aws_route_table" "secondary_private_rt" {
  provider = aws.india
  vpc_id   = aws_vpc.secondary_vpc.id
  tags     = { Name = "secondary-private-rt-in" }
}

resource "aws_route_table_association" "secondary_priv_assoc_1a" {
  provider       = aws.india
  subnet_id      = aws_subnet.secondary_private_1a.id
  route_table_id = aws_route_table.secondary_private_rt.id
}

resource "aws_route_table_association" "secondary_priv_assoc_1b" {
  provider       = aws.india
  subnet_id      = aws_subnet.secondary_private_1b.id
  route_table_id = aws_route_table.secondary_private_rt.id
}

# Example Security Group; review rules before deployment
#checkov:skip=CKV2_AWS_5: Standalone network lab template; no compute ENI is defined in this configuration.
resource "aws_security_group" "secondary_sg" {
  provider    = aws.india
  name        = "secondary-example-sg"
  description = "Example HTTPS ingress policy for a separately managed workload"
  vpc_id      = aws_vpc.secondary_vpc.id

  ingress {
    description = "Example inbound HTTPS access from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Controlled outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
  }

  tags = { Name = "secondary-example-sg" }
}


# VPC flow logging and default security-group lockdown.
resource "aws_default_security_group" "primary_default_lockdown" {
  provider = aws.europe
  vpc_id   = aws_vpc.primary_vpc.id
  ingress  = []
  egress   = []
}

resource "aws_default_security_group" "secondary_default_lockdown" {
  provider = aws.india
  vpc_id   = aws_vpc.secondary_vpc.id
  ingress  = []
  egress   = []
}

resource "aws_kms_key" "primary_flow_logs" {
  provider                = aws.europe
  description             = "Encrypt primary-region VPC flow logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_cloudwatch_log_group" "primary_vpc_flow_logs" {
  provider          = aws.europe
  name              = "/aws/vpc/primary-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.primary_flow_logs.arn
}

resource "aws_iam_role" "primary_vpc_flow_logs" {
  provider = aws.europe
  name     = "primary-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "primary_vpc_flow_logs" {
  provider = aws.europe
  name     = "primary-vpc-flow-logs-policy"
  role     = aws_iam_role.primary_vpc_flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.primary_vpc_flow_logs.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogStreams"]
        Resource = aws_cloudwatch_log_group.primary_vpc_flow_logs.arn
      }
    ]
  })
}

resource "aws_flow_log" "primary_vpc" {
  provider         = aws.europe
  vpc_id           = aws_vpc.primary_vpc.id
  traffic_type     = "ALL"
  log_destination  = aws_cloudwatch_log_group.primary_vpc_flow_logs.arn
  iam_role_arn     = aws_iam_role.primary_vpc_flow_logs.arn
  depends_on       = [aws_iam_role_policy.primary_vpc_flow_logs]
}

resource "aws_kms_key" "secondary_flow_logs" {
  provider                = aws.india
  description             = "Encrypt secondary-region VPC flow logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_cloudwatch_log_group" "secondary_vpc_flow_logs" {
  provider          = aws.india
  name              = "/aws/vpc/secondary-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.secondary_flow_logs.arn
}

resource "aws_iam_role" "secondary_vpc_flow_logs" {
  provider = aws.india
  name     = "secondary-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "secondary_vpc_flow_logs" {
  provider = aws.india
  name     = "secondary-vpc-flow-logs-policy"
  role     = aws_iam_role.secondary_vpc_flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.secondary_vpc_flow_logs.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogStreams"]
        Resource = aws_cloudwatch_log_group.secondary_vpc_flow_logs.arn
      }
    ]
  })
}

resource "aws_flow_log" "secondary_vpc" {
  provider         = aws.india
  vpc_id           = aws_vpc.secondary_vpc.id
  traffic_type     = "ALL"
  log_destination  = aws_cloudwatch_log_group.secondary_vpc_flow_logs.arn
  iam_role_arn     = aws_iam_role.secondary_vpc_flow_logs.arn
  depends_on       = [aws_iam_role_policy.secondary_vpc_flow_logs]
}
