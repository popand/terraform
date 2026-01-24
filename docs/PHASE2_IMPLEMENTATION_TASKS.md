# Phase 2: Bedrock Agent Implementation - Task List

This document provides a step-by-step task list for implementing the Amazon Bedrock AI Agent. Each task is atomic, verifiable, and includes dependencies.

**Reference Document**: See [PHASE2_BEDROCK_AGENT.md](PHASE2_BEDROCK_AGENT.md) for detailed code and configurations.

---

## Prerequisites Checklist

Before starting, ensure the following are complete:

- [ ] AWS CLI configured with appropriate credentials
- [ ] AWS Account ID available (run `aws sts get-caller-identity`)
- [ ] Phase 1 Terraform infrastructure files exist in `/terraform` directory
- [ ] IAM permissions to create: S3 buckets, Lambda functions, IAM roles, Bedrock agents, CodeBuild projects
- [ ] Bedrock model access enabled for Claude (Anthropic) models in your region

---

## Phase 2.1: S3 Infrastructure Setup

### Task 2.1.1: Create Terraform Files S3 Bucket
**Dependency**: None
**Estimated Commands**: 2

```bash
# Get AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-2"

# Create bucket for Terraform files
aws s3 mb s3://terraform-docs-agent-${AWS_ACCOUNT_ID} --region ${AWS_REGION}
```

**Verification**:
```bash
aws s3 ls | grep terraform-docs-agent
```

### Task 2.1.2: Create Output/Docs S3 Bucket
**Dependency**: None
**Estimated Commands**: 1

```bash
# Create bucket for generated documentation and state
aws s3 mb s3://terraform-docs-output-${AWS_ACCOUNT_ID} --region ${AWS_REGION}
```

**Verification**:
```bash
aws s3 ls | grep terraform-docs-output
```

### Task 2.1.3: Upload Terraform Files to S3
**Dependency**: Task 2.1.1
**Estimated Commands**: 1

```bash
# Upload Terraform files (excluding sensitive/temp files)
aws s3 sync /path/to/terraform s3://terraform-docs-agent-${AWS_ACCOUNT_ID}/terraform/ \
  --exclude "*.terraform/*" \
  --exclude "*.tfstate*" \
  --exclude "*.pem" \
  --exclude ".git/*"
```

**Verification**:
```bash
aws s3 ls s3://terraform-docs-agent-${AWS_ACCOUNT_ID}/terraform/ --recursive
```

---

## Phase 2.2: IAM Roles and Policies

### Task 2.2.1: Create Bedrock Agent IAM Role
**Dependency**: None
**Estimated Commands**: 2

1. Create trust policy file `bedrock-trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

2. Create the role:
```bash
aws iam create-role \
  --role-name TerraformDocsBedrockAgentRole \
  --assume-role-policy-document file://bedrock-trust-policy.json
```

**Verification**:
```bash
aws iam get-role --role-name TerraformDocsBedrockAgentRole
```

### Task 2.2.2: Create Bedrock Agent Permissions Policy
**Dependency**: Task 2.2.1
**Estimated Commands**: 1

1. Create permissions policy file `bedrock-permissions-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-docs-agent-*",
        "arn:aws:s3:::terraform-docs-agent-*/*",
        "arn:aws:s3:::terraform-docs-output-*",
        "arn:aws:s3:::terraform-docs-output-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "arn:aws:lambda:*:*:function:terraform-docs-*"
    }
  ]
}
```

2. Attach the policy:
```bash
aws iam put-role-policy \
  --role-name TerraformDocsBedrockAgentRole \
  --policy-name TerraformDocsAgentPermissions \
  --policy-document file://bedrock-permissions-policy.json
```

**Verification**:
```bash
aws iam get-role-policy --role-name TerraformDocsBedrockAgentRole --policy-name TerraformDocsAgentPermissions
```

### Task 2.2.3: Create Lambda Execution Role
**Dependency**: None
**Estimated Commands**: 2

1. Create trust policy file `lambda-trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

2. Create the role:
```bash
aws iam create-role \
  --role-name TerraformDocsLambdaRole \
  --assume-role-policy-document file://lambda-trust-policy.json
```

### Task 2.2.4: Attach Lambda Permissions
**Dependency**: Task 2.2.3
**Estimated Commands**: 2

```bash
# Attach basic Lambda execution
aws iam attach-role-policy \
  --role-name TerraformDocsLambdaRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create custom policy for S3, CodeBuild, EC2 access
```

1. Create `lambda-permissions-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-docs-*",
        "arn:aws:s3:::terraform-docs-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:StartBuild",
        "codebuild:BatchGetBuilds"
      ],
      "Resource": "arn:aws:codebuild:*:*:project/terraform-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeNetworkInterfaces"
      ],
      "Resource": "*"
    }
  ]
}
```

2. Attach policy:
```bash
aws iam put-role-policy \
  --role-name TerraformDocsLambdaRole \
  --policy-name TerraformDocsLambdaPermissions \
  --policy-document file://lambda-permissions-policy.json
```

**Verification**:
```bash
aws iam list-attached-role-policies --role-name TerraformDocsLambdaRole
aws iam list-role-policies --role-name TerraformDocsLambdaRole
```

---

## Phase 2.3: Lambda Functions

### Task 2.3.1: Create Lambda 1 - Read Terraform Files
**Dependency**: Task 2.2.4
**Estimated Commands**: 3

1. Create directory and code file:
```bash
mkdir -p lambda/read-files
```

2. Create `lambda/read-files/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 1)

3. Package and deploy:
```bash
cd lambda/read-files
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-read-files \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment Variables="{TERRAFORM_BUCKET=terraform-docs-agent-${AWS_ACCOUNT_ID}}"
```

**Verification**:
```bash
aws lambda invoke --function-name terraform-docs-read-files \
  --payload '{"bucket":"terraform-docs-agent-'${AWS_ACCOUNT_ID}'","prefix":"terraform/"}' \
  response.json && cat response.json
```

### Task 2.3.2: Create Lambda 2 - Analyze Terraform Module
**Dependency**: Task 2.2.4
**Estimated Commands**: 3

1. Create directory and code file:
```bash
mkdir -p lambda/analyze
```

2. Create `lambda/analyze/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 2)

3. Deploy:
```bash
cd lambda/analyze
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-analyze \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256
```

**Verification**:
```bash
aws lambda invoke --function-name terraform-docs-analyze \
  --payload '{"content":"resource \"aws_instance\" \"test\" {}","filename":"test.tf"}' \
  response.json && cat response.json
```

### Task 2.3.3: Create Lambda 3 - Generate Documentation
**Dependency**: Task 2.2.4
**Estimated Commands**: 3

1. Create `lambda/generate-docs/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 3)

2. Deploy:
```bash
cd lambda/generate-docs
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-generate \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment Variables="{OUTPUT_BUCKET=terraform-docs-output-${AWS_ACCOUNT_ID}}"
```

**Verification**:
```bash
aws lambda invoke --function-name terraform-docs-generate \
  --payload '{"content":"# Test Doc","filename":"test.md"}' \
  response.json && cat response.json
```

### Task 2.3.4: Create Lambda 4 - Terraform Operations
**Dependency**: Task 2.2.4, Task 2.4.1 (CodeBuild)
**Estimated Commands**: 3

1. Create `lambda/terraform-ops/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 4)

2. Deploy:
```bash
cd lambda/terraform-ops
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-operations \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 60 \
  --memory-size 256 \
  --environment Variables="{CODEBUILD_PROJECT=terraform-executor}"
```

### Task 2.3.5: Create Lambda 5 - Get Terraform Status
**Dependency**: Task 2.2.4
**Estimated Commands**: 3

1. Create `lambda/get-status/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 5)

2. Deploy:
```bash
cd lambda/get-status
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-status \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256
```

### Task 2.3.6: Create Lambda 6 - Modify Terraform Code
**Dependency**: Task 2.2.4
**Estimated Commands**: 3

1. Create `lambda/modify-code/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 6)

2. Deploy:
```bash
cd lambda/modify-code
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-modify-code \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 60 \
  --memory-size 512 \
  --environment Variables="{TERRAFORM_BUCKET=terraform-docs-agent-${AWS_ACCOUNT_ID}}"
```

### Task 2.3.7: Create Lambda 7 - Run Infrastructure Tests
**Dependency**: Task 2.2.4
**Estimated Commands**: 3

1. Create `lambda/run-tests/lambda_function.py` (see PHASE2_BEDROCK_AGENT.md Lambda 7)

2. Deploy:
```bash
cd lambda/run-tests
zip function.zip lambda_function.py

aws lambda create-function \
  --function-name terraform-docs-run-tests \
  --runtime python3.11 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsLambdaRole \
  --zip-file fileb://function.zip \
  --timeout 120 \
  --memory-size 512
```

---

## Phase 2.4: CodeBuild for Terraform Execution

### Task 2.4.1: Create CodeBuild IAM Role
**Dependency**: None
**Estimated Commands**: 3

1. Create `codebuild-trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

2. Create role:
```bash
aws iam create-role \
  --role-name TerraformCodeBuildRole \
  --assume-role-policy-document file://codebuild-trust-policy.json
```

3. Attach comprehensive permissions for Terraform (see PHASE2_BEDROCK_AGENT.md for full policy)

### Task 2.4.2: Create CodeBuild Project
**Dependency**: Task 2.4.1
**Estimated Commands**: 1

```bash
aws codebuild create-project \
  --name terraform-executor \
  --source type=S3,location=terraform-docs-agent-${AWS_ACCOUNT_ID}/terraform/ \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=false \
  --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformCodeBuildRole
```

**Verification**:
```bash
aws codebuild batch-get-projects --names terraform-executor
```

---

## Phase 2.5: Bedrock Agent Setup

### Task 2.5.1: Create Bedrock Agent
**Dependency**: Task 2.2.2
**Estimated Commands**: 1

```bash
aws bedrock-agent create-agent \
  --agent-name terraform-docs-agent \
  --agent-resource-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/TerraformDocsBedrockAgentRole \
  --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
  --instruction "You are an expert Terraform and AWS infrastructure analyst..." \
  --idle-session-ttl-in-seconds 600
```

Save the returned `agentId` for subsequent tasks.

**Verification**:
```bash
aws bedrock-agent list-agents
```

### Task 2.5.2: Create OpenAPI Schema File
**Dependency**: None
**Estimated Commands**: 1

Create `openapi-schema.yaml` with all 7 action group endpoints (see PHASE2_BEDROCK_AGENT.md for complete schema):
- `/read-files`
- `/analyze`
- `/generate-docs`
- `/terraform-operation`
- `/get-status`
- `/modify-code`
- `/run-tests`

### Task 2.5.3: Upload OpenAPI Schema to S3
**Dependency**: Task 2.5.2, Task 2.1.1
**Estimated Commands**: 1

```bash
aws s3 cp openapi-schema.yaml s3://terraform-docs-agent-${AWS_ACCOUNT_ID}/schemas/openapi-schema.yaml
```

### Task 2.5.4: Create Action Group
**Dependency**: Task 2.5.1, Task 2.5.3, Task 2.3.1-2.3.7
**Estimated Commands**: 1

```bash
aws bedrock-agent create-agent-action-group \
  --agent-id <AGENT_ID> \
  --agent-version DRAFT \
  --action-group-name terraform-operations \
  --action-group-executor lambda={"lambdaArn":"arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:terraform-docs-read-files"} \
  --api-schema s3={"s3BucketName":"terraform-docs-agent-${AWS_ACCOUNT_ID}","s3ObjectKey":"schemas/openapi-schema.yaml"}
```

Note: You may need to create multiple action groups, one per Lambda function.

### Task 2.5.5: Grant Bedrock Permission to Invoke Lambdas
**Dependency**: Task 2.3.1-2.3.7
**Estimated Commands**: 7

For each Lambda function:
```bash
aws lambda add-permission \
  --function-name terraform-docs-read-files \
  --statement-id AllowBedrockInvoke \
  --action lambda:InvokeFunction \
  --principal bedrock.amazonaws.com \
  --source-arn arn:aws:bedrock:${AWS_REGION}:${AWS_ACCOUNT_ID}:agent/<AGENT_ID>
```

Repeat for: `terraform-docs-analyze`, `terraform-docs-generate`, `terraform-docs-operations`, `terraform-docs-status`, `terraform-docs-modify-code`, `terraform-docs-run-tests`

### Task 2.5.6: Prepare Agent Version
**Dependency**: Task 2.5.4
**Estimated Commands**: 1

```bash
aws bedrock-agent prepare-agent --agent-id <AGENT_ID>
```

Wait for preparation to complete.

### Task 2.5.7: Create Agent Alias
**Dependency**: Task 2.5.6
**Estimated Commands**: 1

```bash
aws bedrock-agent create-agent-alias \
  --agent-id <AGENT_ID> \
  --agent-alias-name production
```

Save the returned `agentAliasId`.

---

## Phase 2.6: Testing and Validation

### Task 2.6.1: Test File Reading
**Dependency**: Task 2.5.7
**Estimated Commands**: 1

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-session-1 \
  --input-text "Read all Terraform files from the terraform folder"
```

**Expected Result**: Agent lists all .tf files from S3

### Task 2.6.2: Test Documentation Generation
**Dependency**: Task 2.6.1
**Estimated Commands**: 1

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-session-2 \
  --input-text "Generate documentation for the Terraform infrastructure"
```

**Expected Result**: Agent generates comprehensive markdown documentation

### Task 2.6.3: Test Conversational Q&A
**Dependency**: Task 2.6.1
**Estimated Commands**: 1

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-session-3 \
  --input-text "What resources does the FortiGate module create?"
```

**Expected Result**: Agent explains FortiGate module resources

### Task 2.6.4: Test Terraform Plan (Dry Run)
**Dependency**: Task 2.6.1
**Estimated Commands**: 1

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-session-4 \
  --input-text "Run terraform plan to show what changes would be made"
```

**Expected Result**: Agent triggers CodeBuild and returns plan output

### Task 2.6.5: Test Code Modification (Dry Run)
**Dependency**: Task 2.6.1
**Estimated Commands**: 1

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-session-5 \
  --input-text "Preview adding a description tag to the VPC module in dry run mode"
```

**Expected Result**: Agent shows proposed changes without modifying files

### Task 2.6.6: Test Infrastructure Testing
**Dependency**: Task 2.6.1
**Estimated Commands**: 1

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <AGENT_ID> \
  --agent-alias-id <ALIAS_ID> \
  --session-id test-session-6 \
  --input-text "Run connectivity tests on the deployed infrastructure"
```

**Expected Result**: Agent runs tests and reports results

---

## Phase 2.7: Optional Enhancements

### Task 2.7.1: Add Bedrock Knowledge Base (Optional)
**Dependency**: Phase 2.5 complete
**Description**: Index Terraform provider documentation for RAG

### Task 2.7.2: Create Web UI with API Gateway (Optional)
**Dependency**: Phase 2.5 complete
**Description**: Create a web interface for interacting with the agent

### Task 2.7.3: Add CloudWatch Alarms (Optional)
**Dependency**: Phase 2.5 complete
**Description**: Monitor Lambda errors and agent invocations

---

## Summary Task Count

| Phase | Tasks | Description |
|-------|-------|-------------|
| 2.1 | 3 | S3 Infrastructure Setup |
| 2.2 | 4 | IAM Roles and Policies |
| 2.3 | 7 | Lambda Functions |
| 2.4 | 2 | CodeBuild Setup |
| 2.5 | 7 | Bedrock Agent Setup |
| 2.6 | 6 | Testing and Validation |
| 2.7 | 3 | Optional Enhancements |
| **Total** | **32** | **Core Tasks (29) + Optional (3)** |

---

## Quick Reference: Environment Variables

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-2"
export TERRAFORM_BUCKET="terraform-docs-agent-${AWS_ACCOUNT_ID}"
export OUTPUT_BUCKET="terraform-docs-output-${AWS_ACCOUNT_ID}"
```

---

## Troubleshooting

### Common Issues:

1. **Lambda timeout**: Increase timeout for Terraform operations (recommend 120s+)
2. **Permission denied**: Ensure all IAM policies are correctly attached
3. **Agent not responding**: Check that agent is in "PREPARED" state
4. **CodeBuild failures**: Review buildspec.yml and check CloudWatch logs

### Useful Debug Commands:

```bash
# Check agent status
aws bedrock-agent get-agent --agent-id <AGENT_ID>

# Check Lambda logs
aws logs tail /aws/lambda/terraform-docs-read-files --follow

# Check CodeBuild logs
aws logs tail /aws/codebuild/terraform-executor --follow
```
