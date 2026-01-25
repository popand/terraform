# -----------------------------------------------------------------------------
# Chat UI Module - Main Resources
# S3 static hosting + CloudFront + API Gateway + Lambda
# -----------------------------------------------------------------------------

locals {
  resource_prefix = var.project_name
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# S3 Bucket for Static Website
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "website" {
  bucket        = "${local.resource_prefix}-website-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(var.tags, {
    Name = "${local.resource_prefix}-website"
  })
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${local.resource_prefix}-oac"
  description                       = "OAC for ${local.resource_prefix} website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${local.resource_prefix} Chat UI"

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # API Gateway origin
  origin {
    domain_name = replace(aws_apigatewayv2_api.chat.api_endpoint, "https://", "")
    origin_id   = "APIGateway"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # API path behavior
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "APIGateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "x-api-key", "Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # SPA fallback for React Router
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# API Gateway (HTTP API)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "chat" {
  name          = "${local.resource_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "x-api-key", "Authorization"]
    max_age       = 3600
  }

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.chat.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "chat" {
  api_id                 = aws_apigatewayv2_api.chat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chat_handler.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.chat.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.chat.id}"
}

# API Key for simple authentication
resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "api_key" {
  name        = "/${local.resource_prefix}/api-key"
  description = "API key for chat UI"
  type        = "SecureString"
  value       = random_password.api_key.result

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda Function for Chat Handler
# -----------------------------------------------------------------------------
data "archive_file" "chat_handler" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/chat_handler.py"
  output_path = "${path.module}/lambda-code/chat_handler.zip"
}

resource "aws_lambda_function" "chat_handler" {
  filename         = data.archive_file.chat_handler.output_path
  function_name    = "${local.resource_prefix}-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "chat_handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 256
  source_code_hash = data.archive_file.chat_handler.output_base64sha256

  environment {
    variables = {
      AGENT_ID       = var.agent_id
      AGENT_ALIAS_ID = var.agent_alias_id
      API_KEY        = random_password.api_key.result
    }
  }

  tags = var.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.resource_prefix}-handler"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.resource_prefix}"
  retention_in_days = 14
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# Build and Deploy Chat UI
# -----------------------------------------------------------------------------
resource "null_resource" "build_and_deploy_ui" {
  # Rebuild when source files change
  triggers = {
    app_jsx_hash    = filemd5("${path.root}/chat-ui/src/App.jsx")
    main_jsx_hash   = filemd5("${path.root}/chat-ui/src/main.jsx")
    index_css_hash  = filemd5("${path.root}/chat-ui/src/index.css")
    package_hash    = filemd5("${path.root}/chat-ui/package.json")
    bucket_id       = aws_s3_bucket.website.id
    cloudfront_id   = aws_cloudfront_distribution.website.id
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/chat-ui"
    command     = <<-EOT
      npm install && npm run build && \
      aws s3 sync dist/ s3://${aws_s3_bucket.website.id} --delete && \
      aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths "/*"
    EOT
  }

  depends_on = [
    aws_s3_bucket.website,
    aws_s3_bucket_policy.website,
    aws_cloudfront_distribution.website
  ]
}
