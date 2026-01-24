# -----------------------------------------------------------------------------
# Bedrock Agent Module - Outputs
# -----------------------------------------------------------------------------

# S3 Buckets
output "terraform_bucket_name" {
  description = "Name of the S3 bucket for Terraform files"
  value       = aws_s3_bucket.terraform_files.id
}

output "terraform_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform files"
  value       = aws_s3_bucket.terraform_files.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for generated documentation and state"
  value       = aws_s3_bucket.output_docs.id
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for generated documentation"
  value       = aws_s3_bucket.output_docs.arn
}

# Bedrock Agent
output "agent_id" {
  description = "ID of the Bedrock Agent"
  value       = var.enable_agent ? aws_bedrockagent_agent.terraform_docs[0].id : null
}

output "agent_arn" {
  description = "ARN of the Bedrock Agent"
  value       = var.enable_agent ? aws_bedrockagent_agent.terraform_docs[0].agent_arn : null
}

output "agent_alias_id" {
  description = "ID of the Bedrock Agent production alias"
  value       = var.enable_agent ? aws_bedrockagent_agent_alias.production[0].agent_alias_id : null
}

output "agent_alias_arn" {
  description = "ARN of the Bedrock Agent production alias"
  value       = var.enable_agent ? aws_bedrockagent_agent_alias.production[0].agent_alias_arn : null
}

# Lambda Functions
output "lambda_function_arns" {
  description = "ARNs of all Lambda functions"
  value = {
    read_files    = aws_lambda_function.read_files.arn
    analyze       = aws_lambda_function.analyze.arn
    generate      = aws_lambda_function.generate.arn
    terraform_ops = aws_lambda_function.terraform_ops.arn
    get_status    = aws_lambda_function.get_status.arn
    modify_code   = aws_lambda_function.modify_code.arn
    run_tests     = aws_lambda_function.run_tests.arn
  }
}

output "lambda_function_names" {
  description = "Names of all Lambda functions"
  value = {
    read_files    = aws_lambda_function.read_files.function_name
    analyze       = aws_lambda_function.analyze.function_name
    generate      = aws_lambda_function.generate.function_name
    terraform_ops = aws_lambda_function.terraform_ops.function_name
    get_status    = aws_lambda_function.get_status.function_name
    modify_code   = aws_lambda_function.modify_code.function_name
    run_tests     = aws_lambda_function.run_tests.function_name
  }
}

# CodeBuild
output "codebuild_project_name" {
  description = "Name of the CodeBuild project for Terraform execution"
  value       = aws_codebuild_project.terraform_executor.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.terraform_executor.arn
}

# IAM Roles
output "bedrock_agent_role_arn" {
  description = "ARN of the Bedrock Agent IAM role"
  value       = aws_iam_role.bedrock_agent.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = aws_iam_role.codebuild.arn
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the Bedrock Agent"
  value = var.enable_agent ? <<-EOT
    ## Terraform Documentation Agent

    ### Invoke the Agent

    Using AWS CLI:
    ```bash
    aws bedrock-agent-runtime invoke-agent \
      --agent-id ${aws_bedrockagent_agent.terraform_docs[0].id} \
      --agent-alias-id ${aws_bedrockagent_agent_alias.production[0].agent_alias_id} \
      --session-id my-session \
      --input-text "Read and analyze the Terraform files"
    ```

    ### Upload Terraform Files

    ```bash
    aws s3 sync ./terraform s3://${aws_s3_bucket.terraform_files.id}/terraform/ \
      --exclude ".terraform/*" \
      --exclude "*.tfstate*" \
      --exclude "*.pem"
    ```

    ### Example Prompts

    - "Read all Terraform files and explain what infrastructure they create"
    - "What resources does the FortiGate module create?"
    - "Run terraform plan to preview changes"
    - "Generate documentation for this infrastructure"
    - "Run connectivity tests on the deployed infrastructure"
  EOT
  : "Bedrock Agent not enabled. Set enable_agent = true to create the agent."
}
