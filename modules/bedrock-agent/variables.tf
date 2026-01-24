# -----------------------------------------------------------------------------
# Bedrock Agent Module - Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "terraform-docs"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "foundation_model" {
  description = "Bedrock foundation model to use for the agent"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "agent_idle_session_ttl" {
  description = "Idle session TTL in seconds"
  type        = number
  default     = 600
}

variable "lambda_timeout" {
  description = "Default timeout for Lambda functions (seconds)"
  type        = number
  default     = 60
}

variable "lambda_memory" {
  description = "Default memory for Lambda functions (MB)"
  type        = number
  default     = 256
}

variable "terraform_version" {
  description = "Terraform version to install in CodeBuild"
  type        = string
  default     = "1.6.0"
}

variable "enable_agent" {
  description = "Whether to create the Bedrock agent (set to false to deploy only supporting resources first)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "terraform-docs-agent"
    ManagedBy = "terraform"
    Phase     = "2"
  }
}

# Phase 1 outputs - passed from root module
variable "phase1_outputs" {
  description = "Outputs from Phase 1 infrastructure (FortiGate IPs, VPC IDs, etc.)"
  type = object({
    fortigate1_public_ip  = optional(string)
    fortigate2_public_ip  = optional(string)
    fortigate1_private_ip = optional(string)
    fortigate2_private_ip = optional(string)
    ubuntu1_private_ip    = optional(string)
    ubuntu2_private_ip    = optional(string)
    vpc1_id               = optional(string)
    vpc2_id               = optional(string)
  })
  default = {}
}
