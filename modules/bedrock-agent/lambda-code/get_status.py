"""
Lambda 5: Get Terraform Status
Gets status of Terraform operations and infrastructure state.
"""

import boto3
import json
import os

codebuild_client = boto3.client('codebuild')
s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Get status of Terraform deployment.

    Input: {
        "build_id": "optional-build-id",
        "check_type": "build_status|infrastructure_state|outputs|all"
    }
    Output: { "status": "...", "details": {...} }
    """

    # Handle Bedrock Agent event format
    if 'actionGroup' in event:
        params = {}
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']

        build_id = params.get('build_id')
        check_type = params.get('check_type', 'all')
    else:
        build_id = event.get('build_id')
        check_type = event.get('check_type', 'all')

    state_bucket = os.environ.get('STATE_BUCKET')
    codebuild_project = os.environ.get('CODEBUILD_PROJECT')

    result = {
        'check_type': check_type,
        'timestamp': __import__('datetime').datetime.now().isoformat()
    }

    try:
        if check_type in ['build_status', 'all'] and build_id:
            result['build'] = get_build_status(build_id)

        if check_type in ['build_status', 'all'] and not build_id and codebuild_project:
            result['recent_builds'] = get_recent_builds(codebuild_project)

        if check_type in ['infrastructure_state', 'all'] and state_bucket:
            result['infrastructure'] = get_infrastructure_state(state_bucket)

        if check_type in ['outputs', 'all'] and state_bucket:
            result['outputs'] = get_terraform_outputs(state_bucket)

        # Determine overall status
        if 'infrastructure' in result:
            result['status'] = result['infrastructure'].get('status', 'UNKNOWN')
        elif 'build' in result:
            result['status'] = result['build'].get('status', 'UNKNOWN')
        else:
            result['status'] = 'NO_DATA'

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to get status'
        }, 500)


def get_build_status(build_id):
    """Get status of a specific CodeBuild execution."""
    try:
        response = codebuild_client.batch_get_builds(ids=[build_id])

        if not response['builds']:
            return {'error': 'Build not found', 'build_id': build_id}

        build = response['builds'][0]

        return {
            'build_id': build_id,
            'status': build['buildStatus'],
            'phase': build.get('currentPhase', 'UNKNOWN'),
            'start_time': build['startTime'].isoformat() if build.get('startTime') else None,
            'end_time': build['endTime'].isoformat() if build.get('endTime') else None,
            'duration_seconds': (
                (build['endTime'] - build['startTime']).total_seconds()
                if build.get('endTime') and build.get('startTime') else None
            ),
            'logs_url': build.get('logs', {}).get('deepLink', ''),
            'phases': [
                {
                    'name': p.get('phaseType'),
                    'status': p.get('phaseStatus'),
                    'duration': p.get('durationInSeconds')
                }
                for p in build.get('phases', [])
            ]
        }
    except Exception as e:
        return {'error': str(e), 'build_id': build_id}


def get_recent_builds(project_name, limit=5):
    """Get recent builds for a CodeBuild project."""
    try:
        response = codebuild_client.list_builds_for_project(
            projectName=project_name,
            sortOrder='DESCENDING'
        )

        build_ids = response.get('ids', [])[:limit]

        if not build_ids:
            return {'message': 'No builds found', 'project': project_name}

        builds_response = codebuild_client.batch_get_builds(ids=build_ids)

        builds = []
        for build in builds_response.get('builds', []):
            # Extract operation from environment variables
            operation = 'unknown'
            for env_var in build.get('environment', {}).get('environmentVariables', []):
                if env_var.get('name') == 'TF_OPERATION':
                    operation = env_var.get('value', 'unknown')
                    break

            builds.append({
                'build_id': build['id'],
                'operation': operation,
                'status': build['buildStatus'],
                'start_time': build['startTime'].isoformat() if build.get('startTime') else None,
                'end_time': build['endTime'].isoformat() if build.get('endTime') else None
            })

        return {
            'project': project_name,
            'count': len(builds),
            'builds': builds
        }
    except Exception as e:
        return {'error': str(e), 'project': project_name}


def get_infrastructure_state(bucket):
    """Get current Terraform state summary."""
    try:
        response = s3_client.get_object(
            Bucket=bucket,
            Key='terraform/terraform.tfstate'
        )
        state = json.loads(response['Body'].read().decode('utf-8'))

        # Extract resource summary
        resources = []
        for resource in state.get('resources', []):
            instances = resource.get('instances', [])
            for instance in instances:
                attributes = instance.get('attributes', {})

                resource_info = {
                    'type': resource.get('type'),
                    'name': resource.get('name'),
                    'module': resource.get('module', 'root'),
                    'provider': resource.get('provider'),
                    'mode': resource.get('mode', 'managed')
                }

                # Add useful attributes based on resource type
                if 'id' in attributes:
                    resource_info['id'] = attributes['id']
                if 'arn' in attributes:
                    resource_info['arn'] = attributes['arn']
                if 'public_ip' in attributes:
                    resource_info['public_ip'] = attributes['public_ip']
                if 'private_ip' in attributes:
                    resource_info['private_ip'] = attributes['private_ip']

                resources.append(resource_info)

        return {
            'status': 'DEPLOYED',
            'terraform_version': state.get('terraform_version'),
            'serial': state.get('serial'),
            'lineage': state.get('lineage'),
            'resource_count': len(resources),
            'resources': resources
        }

    except s3_client.exceptions.NoSuchKey:
        return {
            'status': 'NOT_DEPLOYED',
            'message': 'No Terraform state found. Infrastructure may not be deployed yet.'
        }
    except Exception as e:
        return {
            'status': 'ERROR',
            'error': str(e)
        }


def get_terraform_outputs(bucket):
    """Get Terraform outputs from state."""
    try:
        response = s3_client.get_object(
            Bucket=bucket,
            Key='terraform/outputs.json'
        )
        outputs = json.loads(response['Body'].read().decode('utf-8'))

        # Format outputs for display
        formatted_outputs = {}
        for name, details in outputs.items():
            if isinstance(details, dict):
                formatted_outputs[name] = {
                    'value': details.get('value'),
                    'type': details.get('type', 'string'),
                    'sensitive': details.get('sensitive', False)
                }
            else:
                formatted_outputs[name] = {'value': details}

        return {
            'status': 'SUCCESS',
            'count': len(formatted_outputs),
            'outputs': formatted_outputs
        }

    except s3_client.exceptions.NoSuchKey:
        return {
            'status': 'NOT_AVAILABLE',
            'message': 'No outputs file found. Run terraform apply first.'
        }
    except Exception as e:
        return {
            'status': 'ERROR',
            'error': str(e)
        }


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
