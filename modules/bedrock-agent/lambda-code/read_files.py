"""
Lambda 1: Read Terraform Files
Reads .tf and .tpl files from S3 bucket for the Bedrock Agent.
"""

import boto3
import json
import os

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Reads Terraform files from S3 bucket.

    Input: { "bucket": "bucket-name", "prefix": "terraform/" }
    Output: { "files": [{"name": "main.tf", "content": "..."}, ...] }
    """

    # Handle Bedrock Agent event format
    if 'actionGroup' in event:
        # Extract parameters from Bedrock Agent request
        params = {}
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']

        bucket = params.get('bucket', os.environ.get('TERRAFORM_BUCKET'))
        prefix = params.get('prefix', 'terraform/')
    else:
        # Direct invocation
        bucket = event.get('bucket', os.environ.get('TERRAFORM_BUCKET'))
        prefix = event.get('prefix', 'terraform/')

    if not bucket:
        return format_response(event, {
            'error': 'No bucket specified',
            'message': 'Please provide a bucket name or set TERRAFORM_BUCKET environment variable'
        }, 400)

    files = []
    total_size = 0
    max_total_size = 1024 * 1024  # 1MB limit to avoid Lambda memory issues

    try:
        # List all .tf and .tpl files
        paginator = s3_client.get_paginator('list_objects_v2')

        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get('Contents', []):
                key = obj['Key']

                # Only process Terraform files
                if key.endswith('.tf') or key.endswith('.tpl') or key.endswith('.tfvars'):
                    # Skip if we've exceeded size limit
                    if total_size >= max_total_size:
                        continue

                    # Read file content
                    response = s3_client.get_object(Bucket=bucket, Key=key)
                    content = response['Body'].read().decode('utf-8')

                    total_size += len(content)

                    files.append({
                        'name': key.replace(prefix, ''),
                        'path': key,
                        'content': content,
                        'size': len(content)
                    })

        result = {
            'files': files,
            'count': len(files),
            'total_size_bytes': total_size,
            'bucket': bucket,
            'prefix': prefix
        }

        return format_response(event, result, 200)

    except s3_client.exceptions.NoSuchBucket:
        return format_response(event, {
            'error': f'Bucket not found: {bucket}',
            'message': 'Please check the bucket name and try again'
        }, 404)
    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to read Terraform files'
        }, 500)


def format_response(event, body, status_code):
    """Format response for Bedrock Agent or direct invocation."""

    if 'actionGroup' in event:
        # Bedrock Agent response format
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
        # Direct invocation response
        return {
            'statusCode': status_code,
            'body': json.dumps(body)
        }
