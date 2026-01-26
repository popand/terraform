"""
Lambda: Get Deployed Resources
Retrieves details about currently deployed infrastructure from Terraform state and live AWS.
Returns resource information suitable for display in chat.
"""

import boto3
import json
import os

s3_client = boto3.client('s3')
ec2_client = boto3.client('ec2')


def lambda_handler(event, context):
    """
    Gets deployed infrastructure details from Terraform state and live AWS.
    Returns formatted resource information.
    """

    state_bucket = os.environ.get('STATE_BUCKET')

    if not state_bucket:
        return format_response(event, {
            'error': 'Missing environment variable',
            'message': 'STATE_BUCKET must be configured'
        }, 500)

    # Get resource type filter from parameters
    resource_filter = None
    if 'actionGroup' in event:
        params = {}
        if 'parameters' in event:
            for param in event.get('parameters', []):
                params[param['name']] = param['value']
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']
        resource_filter = params.get('resource_type')
    else:
        resource_filter = event.get('resource_type')

    try:
        # Get resources from Terraform state
        state_resources = get_state_resources(state_bucket)

        if not state_resources:
            return format_response(event, {
                'status': 'not_deployed',
                'message': 'No Terraform state found. Infrastructure may not be deployed yet.',
                'resources': []
            }, 200)

        # Enrich with live AWS data
        enriched_resources = enrich_with_live_data(state_resources)

        # Filter if requested
        if resource_filter:
            enriched_resources = [r for r in enriched_resources
                                  if resource_filter.lower() in r.get('type', '').lower()]

        # Group resources by type for better display
        grouped = group_resources(enriched_resources)

        # Create summary
        summary = create_summary(enriched_resources)

        result = {
            'status': 'deployed',
            'summary': summary,
            'resource_count': len(enriched_resources),
            'resources_by_type': grouped,
            'resources': enriched_resources,
            'message': f'Found {len(enriched_resources)} deployed resources.'
        }

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to get deployed resources'
        }, 500)


def get_state_resources(bucket):
    """Read resources from Terraform state file."""
    try:
        response = s3_client.get_object(
            Bucket=bucket,
            Key='terraform/terraform.tfstate'
        )
        state = json.loads(response['Body'].read().decode('utf-8'))

        resources = []
        for resource in state.get('resources', []):
            resource_type = resource.get('type', '')
            resource_name = resource.get('name', '')
            module = resource.get('module', 'root')

            for instance in resource.get('instances', []):
                attrs = instance.get('attributes', {})

                resource_info = {
                    'type': resource_type,
                    'name': resource_name,
                    'module': module,
                    'id': attrs.get('id', ''),
                    'arn': attrs.get('arn', ''),
                    'attributes': {}
                }

                # Extract key attributes based on resource type
                if resource_type == 'aws_instance':
                    resource_info['attributes'] = {
                        'instance_id': attrs.get('id'),
                        'instance_type': attrs.get('instance_type'),
                        'public_ip': attrs.get('public_ip'),
                        'private_ip': attrs.get('private_ip'),
                        'availability_zone': attrs.get('availability_zone'),
                        'state': attrs.get('instance_state'),
                        'ami': attrs.get('ami'),
                        'tags': attrs.get('tags', {})
                    }
                elif resource_type == 'aws_vpc':
                    resource_info['attributes'] = {
                        'vpc_id': attrs.get('id'),
                        'cidr_block': attrs.get('cidr_block'),
                        'state': attrs.get('state'),
                        'tags': attrs.get('tags', {})
                    }
                elif resource_type == 'aws_subnet':
                    resource_info['attributes'] = {
                        'subnet_id': attrs.get('id'),
                        'vpc_id': attrs.get('vpc_id'),
                        'cidr_block': attrs.get('cidr_block'),
                        'availability_zone': attrs.get('availability_zone'),
                        'tags': attrs.get('tags', {})
                    }
                elif resource_type == 'aws_security_group':
                    resource_info['attributes'] = {
                        'sg_id': attrs.get('id'),
                        'vpc_id': attrs.get('vpc_id'),
                        'name': attrs.get('name'),
                        'description': attrs.get('description'),
                        'ingress_rules': len(attrs.get('ingress', [])),
                        'egress_rules': len(attrs.get('egress', []))
                    }
                elif resource_type == 'aws_internet_gateway':
                    resource_info['attributes'] = {
                        'igw_id': attrs.get('id'),
                        'vpc_id': attrs.get('vpc_id'),
                        'tags': attrs.get('tags', {})
                    }
                elif resource_type == 'aws_eip':
                    resource_info['attributes'] = {
                        'allocation_id': attrs.get('id'),
                        'public_ip': attrs.get('public_ip'),
                        'private_ip': attrs.get('private_ip'),
                        'instance_id': attrs.get('instance')
                    }
                elif resource_type == 'aws_route_table':
                    resource_info['attributes'] = {
                        'route_table_id': attrs.get('id'),
                        'vpc_id': attrs.get('vpc_id'),
                        'routes': len(attrs.get('route', []))
                    }
                elif resource_type == 'aws_network_interface':
                    resource_info['attributes'] = {
                        'eni_id': attrs.get('id'),
                        'subnet_id': attrs.get('subnet_id'),
                        'private_ip': attrs.get('private_ip'),
                        'private_ips': attrs.get('private_ips', [])
                    }
                else:
                    # Generic extraction for other types
                    resource_info['attributes'] = {
                        k: v for k, v in attrs.items()
                        if k in ['id', 'arn', 'name', 'tags', 'state', 'status']
                    }

                resources.append(resource_info)

        return resources

    except s3_client.exceptions.NoSuchKey:
        return None
    except Exception as e:
        raise Exception(f"Failed to read state: {str(e)}")


def enrich_with_live_data(resources):
    """Enrich state data with live AWS information."""
    enriched = []

    # Collect EC2 instance IDs for batch lookup
    instance_ids = [
        r['attributes'].get('instance_id')
        for r in resources
        if r['type'] == 'aws_instance' and r['attributes'].get('instance_id')
    ]

    # Get live instance data
    live_instances = {}
    if instance_ids:
        try:
            response = ec2_client.describe_instances(InstanceIds=instance_ids)
            for reservation in response.get('Reservations', []):
                for instance in reservation.get('Instances', []):
                    live_instances[instance['InstanceId']] = {
                        'state': instance['State']['Name'],
                        'public_ip': instance.get('PublicIpAddress'),
                        'private_ip': instance.get('PrivateIpAddress'),
                        'launch_time': instance.get('LaunchTime', '').isoformat() if instance.get('LaunchTime') else None
                    }
        except Exception:
            pass  # Continue with state data if live lookup fails

    for resource in resources:
        enriched_resource = resource.copy()

        # Update EC2 instances with live data
        if resource['type'] == 'aws_instance':
            instance_id = resource['attributes'].get('instance_id')
            if instance_id in live_instances:
                enriched_resource['live_status'] = live_instances[instance_id]['state']
                enriched_resource['attributes']['current_public_ip'] = live_instances[instance_id]['public_ip']
                enriched_resource['attributes']['current_private_ip'] = live_instances[instance_id]['private_ip']
                enriched_resource['attributes']['launch_time'] = live_instances[instance_id]['launch_time']

        enriched.append(enriched_resource)

    return enriched


def group_resources(resources):
    """Group resources by type for organized display."""
    grouped = {}
    for resource in resources:
        resource_type = resource['type']
        if resource_type not in grouped:
            grouped[resource_type] = []
        grouped[resource_type].append({
            'name': resource['name'],
            'module': resource['module'],
            'id': resource['id'],
            'key_info': get_key_info(resource)
        })
    return grouped


def get_key_info(resource):
    """Extract the most important info for each resource type."""
    attrs = resource.get('attributes', {})
    resource_type = resource['type']

    if resource_type == 'aws_instance':
        status = resource.get('live_status', attrs.get('state', 'unknown'))
        return f"{attrs.get('instance_type', '')} | {attrs.get('public_ip') or attrs.get('private_ip', 'no IP')} | {status}"
    elif resource_type == 'aws_vpc':
        return f"{attrs.get('cidr_block', '')} | {attrs.get('state', '')}"
    elif resource_type == 'aws_subnet':
        return f"{attrs.get('cidr_block', '')} | {attrs.get('availability_zone', '')}"
    elif resource_type == 'aws_security_group':
        return f"{attrs.get('name', '')} | {attrs.get('ingress_rules', 0)} ingress, {attrs.get('egress_rules', 0)} egress"
    elif resource_type == 'aws_eip':
        return f"{attrs.get('public_ip', '')} -> {attrs.get('instance_id', 'unattached')}"
    else:
        return resource['id']


def create_summary(resources):
    """Create a human-readable summary of deployed resources."""
    type_counts = {}
    for r in resources:
        t = r['type'].replace('aws_', '')
        type_counts[t] = type_counts.get(t, 0) + 1

    # Find key resources
    instances = [r for r in resources if r['type'] == 'aws_instance']
    vpcs = [r for r in resources if r['type'] == 'aws_vpc']
    eips = [r for r in resources if r['type'] == 'aws_eip']

    summary_parts = []

    if vpcs:
        vpc_cidrs = [v['attributes'].get('cidr_block', '') for v in vpcs]
        summary_parts.append(f"**VPCs**: {len(vpcs)} ({', '.join(vpc_cidrs)})")

    if instances:
        running = sum(1 for i in instances if i.get('live_status') == 'running')
        summary_parts.append(f"**Instances**: {len(instances)} ({running} running)")

        # List instances with IPs
        instance_details = []
        for inst in instances:
            name = inst['attributes'].get('tags', {}).get('Name', inst['name'])
            ip = inst['attributes'].get('public_ip') or inst['attributes'].get('private_ip', 'no IP')
            instance_details.append(f"  - {name}: {ip}")
        if instance_details:
            summary_parts.append("**Instance Details**:\n" + "\n".join(instance_details))

    if eips:
        eip_list = [e['attributes'].get('public_ip', '') for e in eips]
        summary_parts.append(f"**Elastic IPs**: {', '.join(eip_list)}")

    # Resource type breakdown
    type_summary = ", ".join([f"{count} {t}" for t, count in sorted(type_counts.items())])
    summary_parts.append(f"**All Resources**: {type_summary}")

    return "\n".join(summary_parts)


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
