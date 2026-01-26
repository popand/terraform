"""
Lambda Router for Bedrock Agent Action Group
Routes requests to appropriate Lambda functions based on apiPath.
"""

import boto3
import json
import os

s3_client = boto3.client('s3')
lambda_client = boto3.client('lambda')


def lambda_handler(event, context):
    """
    Routes Bedrock Agent requests to the appropriate Lambda function.
    Also handles direct read-files requests.
    """

    # Check if this is a Bedrock Agent request that needs routing
    if 'actionGroup' in event:
        api_path = event.get('apiPath', '')

        # Route to appropriate Lambda based on apiPath
        if api_path == '/generate-docs':
            return invoke_lambda('terraform-docs-generate', event)
        elif api_path == '/generate-diagram':
            return invoke_lambda('terraform-docs-diagram', event)
        elif api_path == '/get-deployed-resources':
            return invoke_lambda('terraform-docs-deployed', event)
        elif api_path == '/analyze':
            return invoke_lambda('terraform-docs-analyze', event)
        elif api_path == '/terraform-operation':
            return invoke_lambda('terraform-docs-operations', event)
        elif api_path == '/get-status':
            return invoke_lambda('terraform-docs-status', event)
        elif api_path == '/modify-code':
            return invoke_lambda('terraform-docs-modify-code', event)
        elif api_path == '/run-tests':
            return invoke_lambda('terraform-docs-run-tests', event)
        elif api_path == '/read-files':
            # Handle read-files locally
            return handle_read_files(event)
        else:
            return format_response(event, {
                'error': f'Unknown apiPath: {api_path}',
                'message': 'Supported paths: /read-files, /analyze, /generate-docs, /generate-diagram, /get-deployed-resources, /terraform-operation, /get-status, /modify-code, /run-tests'
            }, 400)

    # Direct invocation - handle read-files
    return handle_read_files(event)


def invoke_lambda(function_name, event):
    """Invoke another Lambda function and return its response."""
    try:
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps(event)
        )

        payload = json.loads(response['Payload'].read().decode('utf-8'))
        return payload

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': f'Failed to invoke {function_name}'
        }, 500)


def handle_read_files(event):
    """
    Reads Terraform files from S3 bucket.
    """

    # Handle Bedrock Agent event format
    if 'actionGroup' in event:
        params = {}
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']

        bucket = params.get('bucket', os.environ.get('TERRAFORM_BUCKET'))
        prefix = params.get('prefix', 'terraform/')
    else:
        bucket = event.get('bucket', os.environ.get('TERRAFORM_BUCKET'))
        prefix = event.get('prefix', 'terraform/')

    if not bucket:
        return format_response(event, {
            'error': 'No bucket specified',
            'message': 'Please provide a bucket name or set TERRAFORM_BUCKET environment variable'
        }, 400)

    files = []
    total_size = 0
    max_total_size = 1024 * 1024  # 1MB limit

    try:
        paginator = s3_client.get_paginator('list_objects_v2')

        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get('Contents', []):
                key = obj['Key']

                if key.endswith('.tf') or key.endswith('.tpl') or key.endswith('.tfvars'):
                    if total_size >= max_total_size:
                        continue

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
