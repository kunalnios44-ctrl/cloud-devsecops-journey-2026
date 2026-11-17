# ==========================================
# VARIABLES FOR GLOBAL MULTI-REGION INFRASTRUCTURE
# ==========================================

variable "environment" {
  type        = string
  description = "Deployment environment name"
  default     = "production"
}

variable "primary_region" {
  type        = string
  description = "Primary cloud region (Europe - Stockholm)"
  default     = "eu-north-1"
}

variable "secondary_region" {
  type        = string
  description = "Secondary/DR cloud region (India - Mumbai)"
  default     = "ap-south-1"
}

variable "primary_vpc_cidr" {
  type        = string
  description = "CIDR block for Primary VPC (EU)"
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  type        = string
  description = "CIDR block for Secondary VPC (India)"
  default     = "10.1.0.0/16"
}
