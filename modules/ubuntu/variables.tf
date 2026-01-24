variable "name" {
  description = "Name for the Ubuntu instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the instance"
  type        = string
}

variable "private_ip" {
  description = "Private IP address for the instance"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "remote_subnet_cidr" {
  description = "CIDR block of remote subnet for security group rules"
  type        = string
}
