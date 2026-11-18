# ==========================================
# VARIABLES FOR GLOBAL MULTI-REGION INFRASTRUCTURE
# ==========================================

variable "environment" {
  description = "Environment name for tagging and identification"
  type        = string
  default     = "lab"
}

variable "primary_region" {
  description = "AWS Primary Region for Europe Operations"
  type        = string
  default     = "eu-north-1"
}

variable "secondary_region" {
  description = "AWS Secondary/DR Region for India Operations"
  type        = string
  default     = "ap-south-1"
}

variable "primary_vpc_cidr" {
  description = "CIDR block for Primary VPC (Europe)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for Secondary VPC (India)"
  type        = string
  default     = "10.1.0.0/16"
}
