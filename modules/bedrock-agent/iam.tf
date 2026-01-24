# -----------------------------------------------------------------------------
# Bedrock Agent Module - IAM Roles and Policies
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Bedrock Agent IAM Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "bedrock_agent" {
  name = "${local.resource_prefix}-bedrock-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "bedrock_agent" {
  name = "${local.resource_prefix}-bedrock-agent-policy"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${local.region}::foundation-model/*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_files.arn,
          "${aws_s3_bucket.terraform_files.arn}/*"
        ]
      },
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.read_files.arn,
          aws_lambda_function.analyze.arn,
          aws_lambda_function.generate.arn,
          aws_lambda_function.terraform_ops.arn,
          aws_lambda_function.get_status.arn,
          aws_lambda_function.modify_code.arn,
          aws_lambda_function.run_tests.arn
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Execution IAM Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name = "${local.resource_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# Basic Lambda execution policy (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom Lambda permissions
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${local.resource_prefix}-lambda-custom-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:CopyObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_files.arn,
          "${aws_s3_bucket.terraform_files.arn}/*",
          aws_s3_bucket.output_docs.arn,
          "${aws_s3_bucket.output_docs.arn}/*"
        ]
      },
      {
        Sid    = "CodeBuildAccess"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds",
          "codebuild:StopBuild"
        ]
        Resource = aws_codebuild_project.terraform_executor.arn
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeRouteTables",
          "ec2:DescribeVpnConnections"
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${local.region}::foundation-model/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CodeBuild IAM Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "codebuild" {
  name = "${local.resource_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${local.resource_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${local.resource_prefix}-*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${local.resource_prefix}-*:*"
        ]
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_files.arn,
          "${aws_s3_bucket.terraform_files.arn}/*",
          aws_s3_bucket.output_docs.arn,
          "${aws_s3_bucket.output_docs.arn}/*"
        ]
      },
      {
        Sid    = "TerraformEC2"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      },
      {
        Sid    = "TerraformVPC"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAddresses",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformIAM"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetInstanceProfile",
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformS3State"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/terraform-*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Permissions for Bedrock Agent
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "bedrock_read_files" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_files.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}

resource "aws_lambda_permission" "bedrock_analyze" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analyze.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}

resource "aws_lambda_permission" "bedrock_generate" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}

resource "aws_lambda_permission" "bedrock_terraform_ops" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terraform_ops.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}

resource "aws_lambda_permission" "bedrock_get_status" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_status.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}

resource "aws_lambda_permission" "bedrock_modify_code" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.modify_code.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}

resource "aws_lambda_permission" "bedrock_run_tests" {
  count = var.enable_agent ? 1 : 0

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.run_tests.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.terraform_docs[0].agent_arn
}
