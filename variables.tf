# -----------------------------------------------------------------------------
# General Variables
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block allowed to access FortiGate management"
  type        = string
  default     = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# VPC 1 Variables
# -----------------------------------------------------------------------------
variable "vpc1_cidr" {
  description = "CIDR block for VPC 1"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc1_public_subnet_cidr" {
  description = "CIDR block for VPC 1 public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "vpc1_private_subnet_cidr" {
  description = "CIDR block for VPC 1 private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# -----------------------------------------------------------------------------
# VPC 2 Variables
# -----------------------------------------------------------------------------
variable "vpc2_cidr" {
  description = "CIDR block for VPC 2"
  type        = string
  default     = "10.100.0.0/16"
}

variable "vpc2_public_subnet_cidr" {
  description = "CIDR block for VPC 2 public subnet"
  type        = string
  default     = "10.100.0.0/24"
}

variable "vpc2_private_subnet_cidr" {
  description = "CIDR block for VPC 2 private subnet"
  type        = string
  default     = "10.100.1.0/24"
}

# -----------------------------------------------------------------------------
# FortiGate Variables
# -----------------------------------------------------------------------------
variable "fortigate_instance_type" {
  description = "Instance type for FortiGate VMs"
  type        = string
  default     = "t3.small"
}

variable "fortigate_admin_password" {
  description = "Admin password for FortiGate instances"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Ubuntu Variables
# -----------------------------------------------------------------------------
variable "ubuntu_instance_type" {
  description = "Instance type for Ubuntu VMs"
  type        = string
  default     = "t3.micro"
}

# -----------------------------------------------------------------------------
# VPN Variables
# -----------------------------------------------------------------------------
variable "vpn_psk" {
  description = "Pre-shared key for IPSec VPN tunnel"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Phase 2: Bedrock Agent Variables
# -----------------------------------------------------------------------------
variable "enable_bedrock_agent" {
  description = "Whether to deploy the Bedrock AI Agent (Phase 2)"
  type        = bool
  default     = false
}
