"""
Lambda 3: Generate Documentation
Saves generated documentation to S3.
"""

import boto3
import json
import os
from datetime import datetime

s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Saves generated documentation to S3.

    Input: { "content": "markdown...", "filename": "output.md" }
    Output: { "s3_uri": "s3://bucket/docs/output.md" }
    """

    # Handle Bedrock Agent event format
    if 'actionGroup' in event:
        params = {}
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']

        content = params.get('content', '')
        filename = params.get('filename')
        doc_type = params.get('type', 'documentation')
    else:
        content = event.get('content', '')
        filename = event.get('filename')
        doc_type = event.get('type', 'documentation')

    bucket = os.environ.get('OUTPUT_BUCKET')

    if not bucket:
        return format_response(event, {
            'error': 'OUTPUT_BUCKET environment variable not set',
            'message': 'Please configure the Lambda function with OUTPUT_BUCKET'
        }, 500)

    if not content:
        return format_response(event, {
            'error': 'No content provided',
            'message': 'Please provide documentation content to save'
        }, 400)

    # Generate filename if not provided
    if not filename:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'terraform-docs-{timestamp}.md'

    # Ensure .md extension
    if not filename.endswith('.md'):
        filename = f'{filename}.md'

    # Determine S3 key based on document type
    key_prefix = {
        'documentation': 'docs/',
        'analysis': 'analysis/',
        'report': 'reports/',
        'plan': 'plans/'
    }.get(doc_type, 'docs/')

    key = f'{key_prefix}{filename}'

    try:
        # Add metadata header to documentation
        header = f"""---
Generated: {datetime.now().isoformat()}
Type: {doc_type}
Generator: Terraform Documentation Agent
---

"""
        full_content = header + content

        # Save to S3
        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=full_content.encode('utf-8'),
            ContentType='text/markdown',
            Metadata={
                'generated-by': 'bedrock-agent',
                'doc-type': doc_type,
                'timestamp': datetime.now().isoformat()
            }
        )

        # Generate presigned URL for download (valid for 1 hour)
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket, 'Key': key},
            ExpiresIn=3600
        )

        result = {
            's3_uri': f's3://{bucket}/{key}',
            'filename': filename,
            'size_bytes': len(full_content),
            'doc_type': doc_type,
            'download_url': presigned_url,
            'message': f'Documentation saved successfully to {key}'
        }

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to save documentation'
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
