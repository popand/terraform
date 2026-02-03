# -----------------------------------------------------------------------------
# Bedrock Agent Module - Lambda Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Lambda 1: Read Terraform Files
# -----------------------------------------------------------------------------

data "archive_file" "read_files" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/read_files.py"
  output_path = "${path.module}/lambda-code/read_files.zip"
}

resource "aws_lambda_function" "read_files" {
  filename         = data.archive_file.read_files.output_path
  function_name    = local.lambda_functions.read_files
  role             = aws_iam_role.lambda.arn
  handler          = "read_files.lambda_handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  source_code_hash = data.archive_file.read_files.output_base64sha256

  environment {
    variables = {
      TERRAFORM_BUCKET = aws_s3_bucket.terraform_files.id
      OUTPUT_BUCKET    = aws_s3_bucket.output_docs.id
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 2: Analyze Terraform Module
# -----------------------------------------------------------------------------

data "archive_file" "analyze" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/analyze.py"
  output_path = "${path.module}/lambda-code/analyze.zip"
}

resource "aws_lambda_function" "analyze" {
  filename         = data.archive_file.analyze.output_path
  function_name    = local.lambda_functions.analyze
  role             = aws_iam_role.lambda.arn
  handler          = "analyze.lambda_handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  source_code_hash = data.archive_file.analyze.output_base64sha256

  environment {
    variables = {
      TERRAFORM_BUCKET = aws_s3_bucket.terraform_files.id
      OUTPUT_BUCKET    = aws_s3_bucket.output_docs.id
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 3: Generate Documentation
# -----------------------------------------------------------------------------

data "archive_file" "generate" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/generate.py"
  output_path = "${path.module}/lambda-code/generate.zip"
}

resource "aws_lambda_function" "generate" {
  filename         = data.archive_file.generate.output_path
  function_name    = local.lambda_functions.generate
  role             = aws_iam_role.lambda.arn
  handler          = "generate.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30   # Keep under API Gateway limit
  memory_size      = 512  # Increased for processing
  source_code_hash = data.archive_file.generate.output_base64sha256

  environment {
    variables = {
      TERRAFORM_BUCKET = aws_s3_bucket.terraform_files.id
      OUTPUT_BUCKET    = aws_s3_bucket.output_docs.id
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 4: Terraform Operations
# -----------------------------------------------------------------------------

data "archive_file" "terraform_ops" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/terraform_ops.py"
  output_path = "${path.module}/lambda-code/terraform_ops.zip"
}

resource "aws_lambda_function" "terraform_ops" {
  filename         = data.archive_file.terraform_ops.output_path
  function_name    = local.lambda_functions.terraform_ops
  role             = aws_iam_role.lambda.arn
  handler          = "terraform_ops.lambda_handler"
  runtime          = "python3.11"
  timeout          = 120 # Longer timeout for CodeBuild operations
  memory_size      = var.lambda_memory
  source_code_hash = data.archive_file.terraform_ops.output_base64sha256

  environment {
    variables = {
      CODEBUILD_PROJECT = aws_codebuild_project.terraform_executor.name
      TERRAFORM_BUCKET  = aws_s3_bucket.terraform_files.id
      STATE_BUCKET      = aws_s3_bucket.output_docs.id
      TERRAFORM_VERSION = var.terraform_version
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 5: Get Terraform Status
# -----------------------------------------------------------------------------

data "archive_file" "get_status" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/get_status.py"
  output_path = "${path.module}/lambda-code/get_status.zip"
}

resource "aws_lambda_function" "get_status" {
  filename         = data.archive_file.get_status.output_path
  function_name    = local.lambda_functions.get_status
  role             = aws_iam_role.lambda.arn
  handler          = "get_status.lambda_handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  source_code_hash = data.archive_file.get_status.output_base64sha256

  environment {
    variables = {
      STATE_BUCKET      = aws_s3_bucket.output_docs.id
      CODEBUILD_PROJECT = aws_codebuild_project.terraform_executor.name
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 6: Modify Terraform Code
# -----------------------------------------------------------------------------

data "archive_file" "modify_code" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/modify_code.py"
  output_path = "${path.module}/lambda-code/modify_code.zip"
}

resource "aws_lambda_function" "modify_code" {
  filename         = data.archive_file.modify_code.output_path
  function_name    = local.lambda_functions.modify_code
  role             = aws_iam_role.lambda.arn
  handler          = "modify_code.lambda_handler"
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 512 # More memory for code processing
  source_code_hash = data.archive_file.modify_code.output_base64sha256

  environment {
    variables = {
      TERRAFORM_BUCKET = aws_s3_bucket.terraform_files.id
      BACKUP_PREFIX    = "backups/"
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 7: Run Infrastructure Tests
# -----------------------------------------------------------------------------

data "archive_file" "run_tests" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/run_tests.py"
  output_path = "${path.module}/lambda-code/run_tests.zip"
}

resource "aws_lambda_function" "run_tests" {
  filename         = data.archive_file.run_tests.output_path
  function_name    = local.lambda_functions.run_tests
  role             = aws_iam_role.lambda.arn
  handler          = "run_tests.lambda_handler"
  runtime          = "python3.11"
  timeout          = 300 # 5 minutes for comprehensive tests
  memory_size      = 512
  source_code_hash = data.archive_file.run_tests.output_base64sha256

  environment {
    variables = {
      STATE_BUCKET = aws_s3_bucket.output_docs.id
      # Phase 1 infrastructure IPs (if available)
      FORTIGATE1_IP = try(var.phase1_outputs.fortigate1_public_ip, "")
      FORTIGATE2_IP = try(var.phase1_outputs.fortigate2_public_ip, "")
      UBUNTU1_IP    = try(var.phase1_outputs.ubuntu1_private_ip, "")
      UBUNTU2_IP    = try(var.phase1_outputs.ubuntu2_private_ip, "")
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 8: Generate Architecture Diagram
# -----------------------------------------------------------------------------

data "archive_file" "generate_diagram" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/generate_diagram.py"
  output_path = "${path.module}/lambda-code/generate_diagram.zip"
}

resource "aws_lambda_function" "generate_diagram" {
  filename         = data.archive_file.generate_diagram.output_path
  function_name    = local.lambda_functions.generate_diagram
  role             = aws_iam_role.lambda.arn
  handler          = "generate_diagram.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30   # Keep under API Gateway limit
  memory_size      = 512  # Increased for diagram generation
  source_code_hash = data.archive_file.generate_diagram.output_base64sha256

  environment {
    variables = {
      TERRAFORM_BUCKET = aws_s3_bucket.terraform_files.id
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda 9: Get Deployed Resources
# -----------------------------------------------------------------------------

data "archive_file" "get_deployed_resources" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/get_deployed_resources.py"
  output_path = "${path.module}/lambda-code/get_deployed_resources.zip"
}

resource "aws_lambda_function" "get_deployed_resources" {
  filename         = data.archive_file.get_deployed_resources.output_path
  function_name    = local.lambda_functions.get_deployed_resources
  role             = aws_iam_role.lambda.arn
  handler          = "get_deployed_resources.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256
  source_code_hash = data.archive_file.get_deployed_resources.output_base64sha256

  environment {
    variables = {
      STATE_BUCKET = aws_s3_bucket.output_docs.id
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups (with retention)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "get_deployed_resources" {
  name              = "/aws/lambda/${local.lambda_functions.get_deployed_resources}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "generate_diagram" {
  name              = "/aws/lambda/${local.lambda_functions.generate_diagram}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "read_files" {
  name              = "/aws/lambda/${local.lambda_functions.read_files}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "analyze" {
  name              = "/aws/lambda/${local.lambda_functions.analyze}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "generate" {
  name              = "/aws/lambda/${local.lambda_functions.generate}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "terraform_ops" {
  name              = "/aws/lambda/${local.lambda_functions.terraform_ops}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "get_status" {
  name              = "/aws/lambda/${local.lambda_functions.get_status}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "modify_code" {
  name              = "/aws/lambda/${local.lambda_functions.modify_code}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "run_tests" {
  name              = "/aws/lambda/${local.lambda_functions.run_tests}"
  retention_in_days = 14
  tags              = var.tags
}
