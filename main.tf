# ==========================================
# ULTIMATE MULTI-REGION GLOBAL INFRASTRUCTURE (V4.0)
# Production-Grade: Native S3 Locking, Multi-AZ, Private RTs & Security
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
    bucket       = "kunal-global-terraform-state-bucket"
    key          = "global-infra/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  alias  = "europe"
  region = "eu-north-1"
}

provider "aws" {
  alias  = "india"
  region = "ap-south-1"
}

# ==========================================
# 1. EUROPE REGION (EU-NORTH-1 - PRIMARY)
# ==========================================

resource "aws_vpc" "primary_vpc" {
  provider             = aws.europe
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "primary-vpc-eu" }
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
  availability_zone       = "eu-north-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "primary-public-eu-1a" }
}

resource "aws_subnet" "primary_public_1b" {
  provider                = aws.europe
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-north-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "primary-public-eu-1b" }
}

# Multi-AZ Private Subnets (Zone A & Zone B)
resource "aws_subnet" "primary_private_1a" {
  provider          = aws.europe
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "eu-north-1a"
  tags              = { Name = "primary-private-eu-1a" }
}

resource "aws_subnet" "primary_private_1b" {
  provider          = aws.europe
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "eu-north-1b"
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

# Strict Production Security Group
resource "aws_security_group" "primary_sg" {
  provider = aws.europe
  name     = "primary-production-sg"
  vpc_id   = aws_vpc.primary_vpc.id

  ingress {
    description = "Allow HTTPS from anywhere (ALB)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Controlled outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "primary-secure-sg" }
}


# ==========================================
# 2. INDIA REGION (AP-SOUTH-1 - DISASTER RECOVERY)
# ==========================================

resource "aws_vpc" "secondary_vpc" {
  provider             = aws.india
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "secondary-vpc-in" }
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
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "secondary-public-in-1a" }
}

resource "aws_subnet" "secondary_public_1b" {
  provider                = aws.india
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "secondary-public-in-1b" }
}

# Multi-AZ Private Subnets (Zone A & Zone B)
resource "aws_subnet" "secondary_private_1a" {
  provider          = aws.india
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.10.0/24"
  availability_zone = "ap-south-1a"
  tags              = { Name = "secondary-private-in-1a" }
}

resource "aws_subnet" "secondary_private_1b" {
  provider          = aws.india
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "ap-south-1b"
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

# Strict Production Security Group
resource "aws_security_group" "secondary_sg" {
  provider = aws.india
  name     = "secondary-production-sg"
  vpc_id   = aws_vpc.secondary_vpc.id

  ingress {
    description = "Allow HTTPS from anywhere (ALB)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Controlled outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "secondary-secure-sg" }
}
