# -----------------------------------------------------------------------------
# Chat UI Module - Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "terraform-chat"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "agent_id" {
  description = "Bedrock Agent ID to invoke"
  type        = string
}

variable "agent_alias_id" {
  description = "Bedrock Agent Alias ID"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
