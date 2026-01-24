# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------
output "vpc1_id" {
  description = "VPC 1 ID"
  value       = module.vpc1.vpc_id
}

output "vpc2_id" {
  description = "VPC 2 ID"
  value       = module.vpc2.vpc_id
}

# -----------------------------------------------------------------------------
# FortiGate Outputs
# -----------------------------------------------------------------------------
output "fortigate1_public_ip" {
  description = "FortiGate 1 public IP address"
  value       = module.fortigate1.public_ip
}

output "fortigate1_private_ip" {
  description = "FortiGate 1 private interface IP"
  value       = module.fortigate1.private_ip
}

output "fortigate1_management_url" {
  description = "FortiGate 1 management URL"
  value       = module.fortigate1.management_url
}

output "fortigate2_public_ip" {
  description = "FortiGate 2 public IP address"
  value       = module.fortigate2.public_ip
}

output "fortigate2_private_ip" {
  description = "FortiGate 2 private interface IP"
  value       = module.fortigate2.private_ip
}

output "fortigate2_management_url" {
  description = "FortiGate 2 management URL"
  value       = module.fortigate2.management_url
}

# -----------------------------------------------------------------------------
# Ubuntu Outputs
# -----------------------------------------------------------------------------
output "ubuntu1_private_ip" {
  description = "Ubuntu VM 1 private IP address"
  value       = module.ubuntu1.private_ip
}

output "ubuntu2_private_ip" {
  description = "Ubuntu VM 2 private IP address"
  value       = module.ubuntu2.private_ip
}

# -----------------------------------------------------------------------------
# Connection Information
# -----------------------------------------------------------------------------
output "connectivity_test_command" {
  description = "Command to test connectivity from Ubuntu 1 to Ubuntu 2"
  value       = "ping ${module.ubuntu2.private_ip}"
}

output "ssh_to_fortigate1" {
  description = "SSH command to connect to FortiGate 1"
  value       = module.fortigate1.ssh_command
}

output "ssh_to_fortigate2" {
  description = "SSH command to connect to FortiGate 2"
  value       = module.fortigate2.ssh_command
}

# -----------------------------------------------------------------------------
# Credentials (for reference)
# -----------------------------------------------------------------------------
output "fortigate_admin_user" {
  description = "FortiGate admin username"
  value       = "admin"
}

# -----------------------------------------------------------------------------
# Phase 2: Bedrock Agent Outputs
# -----------------------------------------------------------------------------
output "bedrock_agent_id" {
  description = "Bedrock Agent ID"
  value       = var.enable_bedrock_agent ? module.bedrock_agent[0].agent_id : null
}

output "bedrock_agent_alias_id" {
  description = "Bedrock Agent production alias ID"
  value       = var.enable_bedrock_agent ? module.bedrock_agent[0].agent_alias_id : null
}

output "bedrock_terraform_bucket" {
  description = "S3 bucket for Terraform files (used by Bedrock Agent)"
  value       = var.enable_bedrock_agent ? module.bedrock_agent[0].terraform_bucket_name : null
}

output "bedrock_agent_usage" {
  description = "Instructions for using the Bedrock Agent"
  value       = var.enable_bedrock_agent ? module.bedrock_agent[0].usage_instructions : "Bedrock Agent not enabled. Set enable_bedrock_agent = true"
}
