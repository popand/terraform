# Terraform Agent Chat UI

A React-based chat interface for interacting with the Terraform Infrastructure Agent powered by Amazon Bedrock.

## Features

- Real-time chat with the Bedrock Agent
- Markdown rendering for agent responses
- Dark theme with modern UI
- Example prompts for quick start
- API key authentication
- Responsive design

## Prerequisites

1. Deploy the infrastructure with chat UI enabled:
   ```bash
   terraform apply -var="enable_bedrock_agent=true" -var="enable_chat_ui=true"
   ```

2. Get the API endpoint and key:
   ```bash
   # Get API endpoint
   terraform output chat_ui_api_endpoint

   # Get API key from SSM
   aws ssm get-parameter --name "/terraform-chat/api-key" --with-decryption --query Parameter.Value --output text
   ```

## Local Development

1. Install dependencies:
   ```bash
   npm install
   ```

2. Create `.env` file:
   ```bash
   cp .env.example .env
   # Edit .env with your API endpoint and key
   ```

3. Start development server:
   ```bash
   npm run dev
   ```

4. Open http://localhost:5173

## Deployment

1. Build the app:
   ```bash
   npm run build
   ```

2. Deploy to S3:
   ```bash
   # Get bucket name
   BUCKET=$(terraform output -raw chat_ui_bucket)

   # Upload files
   aws s3 sync dist/ s3://$BUCKET --delete
   ```

3. Invalidate CloudFront cache:
   ```bash
   DIST_ID=$(terraform output -raw chat_ui_cloudfront_id)
   aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
   ```

4. Access the UI:
   ```bash
   terraform output chat_ui_url
   ```

## Configuration

The chat UI can be configured at runtime through the Settings modal:

- **API Endpoint**: The API Gateway URL for the chat backend
- **API Key**: Authentication key stored in AWS SSM

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│ CloudFront  │────▶│ API Gateway │────▶│   Lambda    │
│  (React)    │     │   + S3      │     │  (HTTP API) │     │  (Handler)  │
└─────────────┘     └─────────────┘     └─────────────┘     └──────┬──────┘
                                                                    │
                                                                    ▼
                                                            ┌─────────────┐
                                                            │   Bedrock   │
                                                            │    Agent    │
                                                            └─────────────┘
```

## Example Prompts

- "Read and analyze the Terraform files"
- "What resources does the FortiGate module create?"
- "Run terraform plan"
- "Generate documentation for this infrastructure"
- "Run connectivity tests"
