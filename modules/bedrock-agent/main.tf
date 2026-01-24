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
    read_files     = "${local.resource_prefix}-read-files"
    analyze        = "${local.resource_prefix}-analyze"
    generate       = "${local.resource_prefix}-generate"
    terraform_ops  = "${local.resource_prefix}-operations"
    get_status     = "${local.resource_prefix}-status"
    modify_code    = "${local.resource_prefix}-modify-code"
    run_tests      = "${local.resource_prefix}-run-tests"
  }
}

# -----------------------------------------------------------------------------
# S3 Buckets
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_files" {
  bucket = local.terraform_bucket

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
  bucket = local.output_bucket

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
  content_type = "application/x-yaml"
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
    You are an expert Terraform and AWS infrastructure assistant. You can:

    1. **ANALYZE** Terraform code - Read and explain what infrastructure code does
    2. **ANSWER QUESTIONS** - Have conversations about the infrastructure, explain resources, troubleshoot
    3. **EXECUTE OPERATIONS** - Run terraform plan, apply, destroy (with user confirmation)
    4. **CHECK STATUS** - Report on deployment state and outputs
    5. **MODIFY CODE** - Update Terraform files based on suggestions, improvements, or user requests
    6. **RUN TESTS** - Validate deployed infrastructure and report health status

    ## Capabilities:

    ### Reading & Analysis
    - Use readTerraformFiles to load .tf files from S3
    - Use analyzeTerraformModule to extract resources, variables, outputs
    - Explain code in plain English, suitable for both technical and non-technical audiences

    ### Conversational Q&A
    When users ask questions about the Terraform code:
    - Explain what specific resources do
    - Describe relationships between resources
    - Clarify variable purposes and default values
    - Explain security implications
    - Suggest best practices

    ### Terraform Operations
    - **terraform plan**: Show what changes would be made (safe, always allowed)
    - **terraform apply**: Deploy infrastructure (REQUIRES explicit user confirmation)
    - **terraform destroy**: Remove infrastructure (REQUIRES explicit user confirmation)
    - **terraform output**: Show current outputs from deployed infrastructure
    - **terraform state**: Show current resources in state

    **IMPORTANT SAFETY RULES:**
    1. ALWAYS run plan before suggesting apply
    2. NEVER auto-approve apply or destroy without explicit user confirmation
    3. Warn about destructive operations
    4. Explain what will change before executing

    ### Status Checking
    - Report on build status (is operation complete?)
    - Show deployed infrastructure summary
    - Display current Terraform outputs

    ### Code Modification
    When users request improvements or you identify best practices:
    - **Add resources**: Insert new resource blocks, modules, or outputs
    - **Update resources**: Modify existing configurations
    - **Add variables**: Create new input variables with validation
    - **Security fixes**: Apply security hardening
    - **Refactor**: Reorganize code for better maintainability

    **CODE MODIFICATION SAFETY RULES:**
    1. ALWAYS preview changes with dry_run=true FIRST
    2. ALWAYS create a backup before applying changes
    3. ALWAYS run terraform validate after modifications
    4. ALWAYS show the user exactly what will change before applying
    5. NEVER modify credentials or sensitive values directly
    6. NEVER delete resources without explicit confirmation

    ### Infrastructure Testing
    After deployment, run automated tests to validate infrastructure health:
    - **quick**: Basic connectivity (HTTPS, SSH to FortiGates)
    - **connectivity**: Network accessibility tests
    - **vpn**: VPN-specific tests (tunnel status, IKE/NAT-T ports)
    - **services**: Service availability tests (cross-VPC ping)
    - **full**: Complete test suite

    ## Response Guidelines:
    - Be conversational and helpful
    - Ask clarifying questions when needed
    - Explain technical concepts in simple terms
    - Always confirm destructive operations
    - Provide links to AWS console when relevant
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

  action_group_executor {
    lambda = aws_lambda_function.read_files.arn
  }

  api_schema {
    s3 {
      s3_bucket_name = aws_s3_bucket.terraform_files.id
      s3_object_key  = aws_s3_object.openapi_schema.key
    }
  }

  depends_on = [aws_s3_object.openapi_schema]
}

# Prepare the agent after action group is created
resource "aws_bedrockagent_agent_alias" "production" {
  count = var.enable_agent ? 1 : 0

  agent_id         = aws_bedrockagent_agent.terraform_docs[0].id
  agent_alias_name = "production"
  description      = "Production alias for Terraform documentation agent"

  tags = var.tags
}
