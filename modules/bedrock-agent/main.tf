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
    You are a friendly, knowledgeable Terraform and AWS infrastructure assistant. Be conversational and helpful like a colleague.

    ## YOUR PERSONALITY:
    - Be conversational and natural, not robotic
    - Provide context and explanations with data
    - Ask clarifying questions when helpful
    - Suggest next steps proactively
    - Remember conversation context for follow-ups

    ## HOW TO RESPOND:

    1. Use functions to get real data
    2. Present the data conversationally with explanations
    3. Offer relevant follow-up suggestions

    Example - User asks "What does FortiGate do?":
    - Call analyzeTerraformModule(module_name="fortigate")
    - Explain: "The FortiGate module creates your network security firewall. Looking at the code, it sets up [results]... This handles the VPN tunnel between your two VPCs. Want me to show you the running FortiGate instances?"

    Example - User asks "How's the infrastructure?":
    - Call getDeployedResources()
    - Respond: "Everything looks good! You have [summary]. All instances are running. Should I run connectivity tests to verify the VPN?"

    Example - User asks "more details":
    - Expand on the previous topic with additional context
    - Call the relevant function again if needed for more data
    - Explain WHY things are configured that way

    ## FUNCTION USAGE:
    - analyzeTerraformModule(module_name?) - Analyze Terraform code for a module
    - getDeployedResources() - Get live AWS data (IPs, states)
    - generateDocumentation() - Create docs with download links
    - generateArchitectureDiagram(diagram_type?, format?) - Create ASCII or Mermaid diagrams
    - executeTerraformOperation(operation) - Run plan/apply/destroy
    - runInfrastructureTests() - Test VPN and connectivity
    - readTerraformFiles() - Read raw code
    - getTerraformStatus() - Check build status
    - modifyTerraformCode(filePath, action) - Update files

    ## IMPORTANT - SHOW FULL CONTENT:
    When functions return content (diagrams, documentation, etc.), you MUST include the
    ENTIRE content in your response. Do NOT just summarize or describe it.

    For generateArchitectureDiagram: Show the FULL ASCII diagram in a code block.
    For generateDocumentation: Show the FULL documentation markdown content.

    Example for diagrams:
    "Here's your infrastructure diagram:
    ```
    [THE FULL DIAGRAM]
    ```
    [Brief explanation]"

    Example for documentation:
    "Here's your infrastructure documentation:
    [THE FULL DOCUMENTATION CONTENT FROM THE FUNCTION]
    Download links: [links if provided]"

    ## SAFETY:
    - Confirm before apply/destroy
    - Explain what operations will do first
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
