# -----------------------------------------------------------------------------
# Chat UI Module - Outputs
# -----------------------------------------------------------------------------

output "website_bucket_name" {
  description = "S3 bucket name for website files"
  value       = aws_s3_bucket.website.id
}

output "website_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.website.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "website_url" {
  description = "Full URL of the chat UI"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_apigatewayv2_api.chat.api_endpoint}/prod/chat"
}

output "api_key" {
  description = "API key for authentication"
  value       = random_password.api_key.result
  sensitive   = true
}

output "api_key_ssm_parameter" {
  description = "SSM Parameter name storing the API key"
  value       = aws_ssm_parameter.api_key.name
}

output "lambda_function_name" {
  description = "Name of the chat handler Lambda function"
  value       = aws_lambda_function.chat_handler.function_name
}

output "deployment_instructions" {
  description = "Instructions for deploying the chat UI"
  value = <<-EOT
    ## Chat UI Deployment

    ### 1. Build the React app
    cd chat-ui
    npm install
    npm run build

    ### 2. Deploy to S3
    aws s3 sync dist/ s3://${aws_s3_bucket.website.id} --delete

    ### 3. Invalidate CloudFront cache
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths "/*"

    ### 4. Access the UI
    URL: https://${aws_cloudfront_distribution.website.domain_name}

    ### 5. Configure the UI
    API Endpoint: ${aws_apigatewayv2_api.chat.api_endpoint}/prod/chat
    API Key: (retrieve from SSM: aws ssm get-parameter --name "${aws_ssm_parameter.api_key.name}" --with-decryption --query Parameter.Value --output text)
  EOT
}
