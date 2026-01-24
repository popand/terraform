"""
Lambda 4: Terraform Operations
Triggers Terraform operations via CodeBuild.
"""

import boto3
import json
import os
import uuid

codebuild_client = boto3.client('codebuild')


def lambda_handler(event, context):
    """
    Triggers Terraform operations via CodeBuild.

    Input: {
        "operation": "plan|apply|destroy|output|state|validate",
        "auto_approve": false,
        "variables": {"key": "value"}
    }
    Output: { "build_id": "...", "status": "IN_PROGRESS", "log_url": "..." }
    """

    # Handle Bedrock Agent event format
    if 'actionGroup' in event:
        params = {}
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']

        operation = params.get('operation', 'plan')
        auto_approve = str(params.get('auto_approve', 'false')).lower() == 'true'
        variables = params.get('variables', {})
        if isinstance(variables, str):
            try:
                variables = json.loads(variables)
            except:
                variables = {}
    else:
        operation = event.get('operation', 'plan')
        auto_approve = event.get('auto_approve', False)
        variables = event.get('variables', {})

    # Get environment variables
    codebuild_project = os.environ.get('CODEBUILD_PROJECT', 'terraform-docs-executor')
    terraform_bucket = os.environ.get('TERRAFORM_BUCKET')
    state_bucket = os.environ.get('STATE_BUCKET')
    terraform_version = os.environ.get('TERRAFORM_VERSION', '1.6.0')

    # Validate operation
    valid_operations = ['plan', 'apply', 'destroy', 'output', 'state', 'validate']
    if operation not in valid_operations:
        return format_response(event, {
            'error': f'Invalid operation: {operation}',
            'valid_operations': valid_operations,
            'message': f'Please use one of: {", ".join(valid_operations)}'
        }, 400)

    # Security check for destructive operations
    if operation in ['apply', 'destroy'] and not auto_approve:
        return format_response(event, {
            'error': f'Safety check failed',
            'operation': operation,
            'message': f'The "{operation}" operation requires explicit confirmation. '
                      f'Please set auto_approve=true to proceed. '
                      f'WARNING: This will modify your infrastructure!',
            'required_parameter': 'auto_approve=true'
        }, 400)

    # Build environment variables for CodeBuild
    env_vars = [
        {'name': 'TF_OPERATION', 'value': operation, 'type': 'PLAINTEXT'},
        {'name': 'TF_AUTO_APPROVE', 'value': str(auto_approve).lower(), 'type': 'PLAINTEXT'},
        {'name': 'TERRAFORM_BUCKET', 'value': terraform_bucket or '', 'type': 'PLAINTEXT'},
        {'name': 'STATE_BUCKET', 'value': state_bucket or '', 'type': 'PLAINTEXT'},
        {'name': 'TERRAFORM_VERSION', 'value': terraform_version, 'type': 'PLAINTEXT'},
    ]

    # Add Terraform variables
    for key, value in variables.items():
        env_vars.append({
            'name': f'TF_VAR_{key}',
            'value': str(value),
            'type': 'PLAINTEXT'
        })

    # Generate execution ID
    execution_id = f'tf-{operation}-{uuid.uuid4().hex[:8]}'

    try:
        # Start CodeBuild project
        response = codebuild_client.start_build(
            projectName=codebuild_project,
            environmentVariablesOverride=env_vars
        )

        build = response['build']
        build_id = build['id']

        # Get log stream info
        logs = build.get('logs', {})
        log_group = logs.get('groupName', f'/aws/codebuild/{codebuild_project}')

        # Build console URL
        region = os.environ.get('AWS_REGION', 'us-east-2')
        console_url = (
            f'https://{region}.console.aws.amazon.com/codesuite/codebuild/'
            f'{build["arn"].split(":")[4]}/projects/{codebuild_project}/'
            f'build/{build_id.replace(":", "%3A")}'
        )

        result = {
            'execution_id': execution_id,
            'build_id': build_id,
            'operation': operation,
            'status': 'IN_PROGRESS',
            'build_status': build['buildStatus'],
            'message': f'Terraform {operation} operation started',
            'console_url': console_url,
            'log_group': log_group,
            'started_at': build['startTime'].isoformat() if build.get('startTime') else None
        }

        # Add warning for destructive operations
        if operation in ['apply', 'destroy']:
            result['warning'] = (
                f'This {operation} operation will modify your infrastructure. '
                f'Monitor the build logs for progress.'
            )

        return format_response(event, result, 200)

    except codebuild_client.exceptions.ResourceNotFoundException:
        return format_response(event, {
            'error': f'CodeBuild project not found: {codebuild_project}',
            'message': 'Please ensure the CodeBuild project exists'
        }, 404)
    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'operation': operation,
            'message': 'Failed to start Terraform operation'
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
