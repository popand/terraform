# -----------------------------------------------------------------------------
# Bedrock Agent Module - Main Configuration
# -----------------------------------------------------------------------------
# This module creates an Amazon Bedrock Agent that can:
# 1. Analyze Terraform templates and generate documentation
# 2. Answer questions about infrastructure code
# 3. Execute Terraform operations (plan, apply, destroy)
# 4. Check deployment status
# 5. Modify Terraform code based on suggestions
# 6. Run infrastructure tests
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.name
  resource_prefix = var.project_name

  # S3 bucket names
  terraform_bucket = "${local.resource_prefix}-agent-${local.account_id}"
  output_bucket    = "${local.resource_prefix}-output-${local.account_id}"

  # Lambda function names
  lambda_functions = {
    read_files             = "${local.resource_prefix}-read-files"
    analyze                = "${local.resource_prefix}-analyze"
    generate               = "${local.resource_prefix}-generate"
    generate_diagram       = "${local.resource_prefix}-diagram"
    get_deployed_resources = "${local.resource_prefix}-deployed"
    terraform_ops          = "${local.resource_prefix}-operations"
    get_status             = "${local.resource_prefix}-status"
    modify_code            = "${local.resource_prefix}-modify-code"
    run_tests              = "${local.resource_prefix}-run-tests"
  }
}

# -----------------------------------------------------------------------------
# S3 Buckets
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_files" {
  bucket        = local.terraform_bucket
  force_destroy = true

  tags = merge(var.tags, {
    Name    = local.terraform_bucket
    Purpose = "Terraform source files for Bedrock Agent"
  })
}

resource "aws_s3_bucket_versioning" "terraform_files" {
  bucket = aws_s3_bucket.terraform_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_files" {
  bucket = aws_s3_bucket.terraform_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_files" {
  bucket = aws_s3_bucket.terraform_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "output_docs" {
  bucket        = local.output_bucket
  force_destroy = true

  tags = merge(var.tags, {
    Name    = local.output_bucket
    Purpose = "Generated documentation and Terraform state"
  })
}

resource "aws_s3_bucket_versioning" "output_docs" {
  bucket = aws_s3_bucket.output_docs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output_docs" {
  bucket = aws_s3_bucket.output_docs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "output_docs" {
  bucket = aws_s3_bucket.output_docs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload OpenAPI schema to S3
resource "aws_s3_object" "openapi_schema" {
  bucket       = aws_s3_bucket.terraform_files.id
  key          = "schemas/openapi-schema.yaml"
  source       = "${path.module}/openapi-schema.yaml"
  content_type = "text/yaml"
  etag         = filemd5("${path.module}/openapi-schema.yaml")

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Bedrock Agent
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent" "terraform_docs" {
  count = var.enable_agent ? 1 : 0

  agent_name                  = "${local.resource_prefix}-agent"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent.arn
  foundation_model            = var.foundation_model
  idle_session_ttl_in_seconds = var.agent_idle_session_ttl
  description                 = "AI Agent for Terraform documentation, operations, and infrastructure management"

  instruction = <<-EOT
    You are an expert Terraform and AWS infrastructure assistant.

    ## CRITICAL OUTPUT RULES:

    When a function returns data, you MUST display the FULL content to the user:
    - For getDeployedResources: Show the complete "summary" field from the response. Include ALL instance names, IPs, and states.
    - For generateDocumentation: Show the complete "documentation" field.
    - For generateArchitectureDiagram: Show the complete "diagram" field (Mermaid code).

    NEVER summarize or abbreviate the function output. Display it verbatim.

    ## FUNCTION USAGE RULES:

    1. **"Generate documentation"** -> Call generateDocumentation ONLY.
    2. **"Show deployed resources"** or **"what is deployed"** -> Call getDeployedResources ONLY.
    3. **"Show architecture"** or **"diagram"** -> Call generateArchitectureDiagram ONLY.

    Do NOT call readTerraformFiles before these functions - they read files internally.

    ## Available Actions:

    ### getDeployedResources
    Use for: "show deployed", "what's running", "list resources", "show IPs"
    - Queries live AWS data directly
    - Returns summary with: Instance names, public IPs, private IPs, states, VPC details
    - ALWAYS display the full "summary" field to the user

    ### generateDocumentation
    Use for: "generate docs", "documentation", "summarize infrastructure"
    - Returns markdown documentation
    - ALWAYS display the full "documentation" field to the user

    ### generateArchitectureDiagram
    Use for: "show architecture", "diagram", "visualize"
    - Returns Mermaid diagram code
    - ALWAYS display the full "diagram" field to the user

    ### Other Actions:
    - readTerraformFiles: ONLY when user asks to "read the code" or "show me the files"
    - analyzeTerraformModule: Extract resources, variables, outputs
    - executeTerraformOperation: Run plan/apply/destroy (requires confirmation)
    - getTerraformStatus: Check build status
    - modifyTerraformCode: Update Terraform files
    - runInfrastructureTests: Validate deployed infrastructure

    ## Safety Rules:
    - NEVER auto-approve apply or destroy without explicit user confirmation
    - Warn about destructive operations
  EOT

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Bedrock Agent Action Group
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent_action_group" "terraform_actions" {
  count = var.enable_agent ? 1 : 0

  agent_id                   = aws_bedrockagent_agent.terraform_docs[0].id
  agent_version              = "DRAFT"
  action_group_name          = "TerraformOperations"
  description                = "Actions for reading, analyzing, and managing Terraform infrastructure"
  skip_resource_in_use_check = true
  prepare_agent              = true

  action_group_executor {
    lambda = aws_lambda_function.read_files.arn
  }

  api_schema {
    payload = file("${path.module}/openapi-schema.yaml")
  }
}

# Prepare the agent after action group is created
resource "aws_bedrockagent_agent_alias" "production" {
  count = var.enable_agent ? 1 : 0

  agent_id         = aws_bedrockagent_agent.terraform_docs[0].id
  agent_alias_name = "production"
  description      = "Production alias for Terraform documentation agent - ${var.foundation_model}"

  tags = var.tags

  lifecycle {
    replace_triggered_by = [
      aws_bedrockagent_agent.terraform_docs[0].foundation_model,
      aws_bedrockagent_agent.terraform_docs[0].instruction
    ]
  }
}
