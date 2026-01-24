variable "name" {
  description = "Name prefix for FortiGate resources"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for FortiGate"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy FortiGate into"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for FortiGate public interface"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for FortiGate private interface"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block of public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block of private subnet"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block allowed for management access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "remote_private_subnet_cidr" {
  description = "CIDR block of the remote private subnet (for VPN)"
  type        = string
}

variable "admin_password" {
  description = "Admin password for FortiGate"
  type        = string
  sensitive   = true
}

variable "vpn_psk" {
  description = "Pre-shared key for IPSec VPN"
  type        = string
  sensitive   = true
}

variable "vpn_peer_ip" {
  description = "Public IP of the VPN peer FortiGate"
  type        = string
}

variable "vpn_name" {
  description = "Name for the VPN tunnel"
  type        = string
}

variable "eip_allocation_id" {
  description = "Allocation ID of the Elastic IP to associate"
  type        = string
}

variable "eip_public_ip" {
  description = "Public IP of the Elastic IP (for outputs)"
  type        = string
}
