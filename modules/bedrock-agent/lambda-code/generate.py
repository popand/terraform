"""
Lambda 3: Generate Documentation
Reads Terraform files and generates concise markdown documentation inline.
Uses Bedrock Claude to create a summary suitable for chat display.
"""

import boto3
import json
import os

s3_client = boto3.client('s3')
bedrock_runtime = boto3.client('bedrock-runtime')


def lambda_handler(event, context):
    """
    Generates concise markdown documentation for Terraform infrastructure.
    Returns documentation directly in the response for display in chat.
    """

    terraform_bucket = os.environ.get('TERRAFORM_BUCKET')

    if not terraform_bucket:
        return format_response(event, {
            'error': 'Missing environment variable',
            'message': 'TERRAFORM_BUCKET must be configured'
        }, 500)

    try:
        # Read Terraform files from S3
        terraform_content = read_terraform_files(terraform_bucket)

        if not terraform_content:
            return format_response(event, {
                'error': 'No Terraform files found',
                'message': f'No .tf files found in s3://{terraform_bucket}/terraform/'
            }, 404)

        # Generate concise documentation using Bedrock
        documentation = generate_concise_docs(terraform_content)

        result = {
            'status': 'success',
            'documentation': documentation,
            'message': 'Documentation generated successfully'
        }

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to generate documentation'
        }, 500)


def read_terraform_files(bucket):
    """Read all .tf files from S3 bucket and return summary."""

    content_parts = []
    prefix = 'terraform/'
    file_list = []

    try:
        paginator = s3_client.get_paginator('list_objects_v2')

        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get('Contents', []):
                key = obj['Key']
                if key.endswith('.tf') and not key.endswith('.tfstate'):
                    try:
                        response = s3_client.get_object(Bucket=bucket, Key=key)
                        file_content = response['Body'].read().decode('utf-8')
                        display_name = key.replace(prefix, '')
                        file_list.append(display_name)
                        # Only include first 500 chars per file to keep prompt small
                        truncated = file_content[:500] + ('...' if len(file_content) > 500 else '')
                        content_parts.append(f"### {display_name}\n```hcl\n{truncated}\n```")
                    except Exception:
                        pass

        return '\n'.join(content_parts) if content_parts else None

    except Exception:
        return None


def generate_concise_docs(terraform_content):
    """Use Bedrock to generate concise documentation suitable for chat."""

    prompt = f"""Analyze this Terraform configuration and create a CONCISE markdown summary.
Keep it under 1500 characters. Focus on the most important aspects.

Include these sections (keep each brief):
1. **Overview** - 2-3 sentences about what this infrastructure does
2. **Key Components** - Bullet list of main resources (VPCs, instances, firewalls)
3. **Network Design** - Brief description of network architecture
4. **Security** - Key security features (firewalls, security groups)
5. **Outputs** - What values/endpoints are exposed

Use markdown formatting. Be concise and informative.

Terraform Configuration:
{terraform_content}

Generate the concise documentation:"""

    try:
        response = bedrock_runtime.invoke_model(
            modelId='us.anthropic.claude-sonnet-4-20250514-v1:0',
            contentType='application/json',
            accept='application/json',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1000,  # Keep response small
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            })
        )

        response_body = json.loads(response['body'].read())
        return response_body['content'][0]['text']

    except Exception as e:
        # Fallback to basic documentation
        return generate_basic_docs(terraform_content)


def generate_basic_docs(terraform_content):
    """Generate basic documentation without Bedrock (fallback)."""

    return """# Infrastructure Summary

## Overview
This Terraform configuration defines AWS infrastructure including VPCs, compute instances, and network components.

## Key Components
- VPC networks with public/private subnets
- EC2 instances for compute workloads
- Security groups for access control
- Network routing and gateways

## Notes
Run `terraform output` to see deployed resource details.

*Generated automatically - use analyze for detailed breakdown*
"""


def format_response(event, body, status_code):
    """Format response for Bedrock Agent or direct invocation."""

    if 'actionGroup' in event:
        return {
            'messageVersion': '1.0',
            'response': {
                'actionGroup': event.get('actionGroup'),
                'apiPath': event.get('apiPath'),
                'httpMethod': event.get('httpMethod'),
                'httpStatusCode': status_code,
                'responseBody': {
                    'application/json': {
                        'body': json.dumps(body)
                    }
                }
            }
        }
    else:
        return {
            'statusCode': status_code,
            'body': json.dumps(body)
        }
