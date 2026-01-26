"""
Lambda: Get Deployed Resources
Retrieves details about currently deployed infrastructure directly from AWS.
Returns resource information suitable for display in chat.
"""

import boto3
import json
import os

ec2_client = boto3.client('ec2')


def lambda_handler(event, context):
    """
    Gets deployed infrastructure details directly from AWS.
    Returns formatted resource information.
    """

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
        # Query AWS directly for resources
        resources = []

        # Get VPCs
        vpcs = get_vpcs()
        resources.extend(vpcs)

        # Get EC2 instances
        instances = get_instances()
        resources.extend(instances)

        # Get subnets
        subnets = get_subnets()
        resources.extend(subnets)

        # Get security groups
        security_groups = get_security_groups()
        resources.extend(security_groups)

        # Get elastic IPs
        eips = get_elastic_ips()
        resources.extend(eips)

        # Get internet gateways
        igws = get_internet_gateways()
        resources.extend(igws)

        if not resources:
            return format_response(event, {
                'status': 'not_deployed',
                'message': 'No infrastructure resources found in AWS.',
                'resources': []
            }, 200)

        # Filter if requested
        if resource_filter:
            resources = [r for r in resources
                         if resource_filter.lower() in r.get('type', '').lower()]

        # Group resources by type for better display
        grouped = group_resources(resources)

        # Create summary
        summary = create_summary(resources)

        result = {
            'status': 'deployed',
            'summary': summary,
            'resource_count': len(resources),
            'resources_by_type': grouped,
            'resources': resources,
            'message': f'Found {len(resources)} deployed resources.'
        }

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to get deployed resources'
        }, 500)


def get_vpcs():
    """Get VPCs with FortiGate or Demo tags."""
    resources = []
    try:
        response = ec2_client.describe_vpcs(
            Filters=[
                {'Name': 'tag:Project', 'Values': ['FortiGate-VPN-Demo', 'fortigate-demo', '*fortigate*', '*demo*']}
            ]
        )

        # If no project tag, get all non-default VPCs
        if not response.get('Vpcs'):
            response = ec2_client.describe_vpcs(
                Filters=[{'Name': 'isDefault', 'Values': ['false']}]
            )

        for vpc in response.get('Vpcs', []):
            name = get_tag_value(vpc.get('Tags', []), 'Name') or vpc['VpcId']
            resources.append({
                'type': 'vpc',
                'id': vpc['VpcId'],
                'name': name,
                'attributes': {
                    'cidr_block': vpc.get('CidrBlock'),
                    'state': vpc.get('State'),
                    'is_default': vpc.get('IsDefault', False)
                }
            })
    except Exception as e:
        pass
    return resources


def get_instances():
    """Get EC2 instances."""
    resources = []
    try:
        response = ec2_client.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'pending']}
            ]
        )

        for reservation in response.get('Reservations', []):
            for instance in reservation.get('Instances', []):
                name = get_tag_value(instance.get('Tags', []), 'Name') or instance['InstanceId']
                instance_type = instance.get('InstanceType', '')

                # Determine if it's a FortiGate or Ubuntu
                role = 'unknown'
                if 'fortigate' in name.lower() or 'fortios' in instance_type.lower():
                    role = 'FortiGate Firewall'
                elif 'ubuntu' in name.lower():
                    role = 'Ubuntu Server'

                resources.append({
                    'type': 'instance',
                    'id': instance['InstanceId'],
                    'name': name,
                    'role': role,
                    'attributes': {
                        'instance_type': instance_type,
                        'state': instance['State']['Name'],
                        'public_ip': instance.get('PublicIpAddress', 'None'),
                        'private_ip': instance.get('PrivateIpAddress'),
                        'availability_zone': instance['Placement']['AvailabilityZone'],
                        'vpc_id': instance.get('VpcId'),
                        'subnet_id': instance.get('SubnetId'),
                        'launch_time': instance.get('LaunchTime', '').isoformat() if instance.get('LaunchTime') else None
                    }
                })
    except Exception as e:
        pass
    return resources


def get_subnets():
    """Get subnets from non-default VPCs."""
    resources = []
    try:
        # First get non-default VPCs
        vpc_response = ec2_client.describe_vpcs(
            Filters=[{'Name': 'isDefault', 'Values': ['false']}]
        )
        vpc_ids = [vpc['VpcId'] for vpc in vpc_response.get('Vpcs', [])]

        if vpc_ids:
            response = ec2_client.describe_subnets(
                Filters=[{'Name': 'vpc-id', 'Values': vpc_ids}]
            )

            for subnet in response.get('Subnets', []):
                name = get_tag_value(subnet.get('Tags', []), 'Name') or subnet['SubnetId']
                resources.append({
                    'type': 'subnet',
                    'id': subnet['SubnetId'],
                    'name': name,
                    'attributes': {
                        'cidr_block': subnet.get('CidrBlock'),
                        'availability_zone': subnet.get('AvailabilityZone'),
                        'vpc_id': subnet.get('VpcId'),
                        'available_ips': subnet.get('AvailableIpAddressCount')
                    }
                })
    except Exception as e:
        pass
    return resources


def get_security_groups():
    """Get security groups from non-default VPCs."""
    resources = []
    try:
        # First get non-default VPCs
        vpc_response = ec2_client.describe_vpcs(
            Filters=[{'Name': 'isDefault', 'Values': ['false']}]
        )
        vpc_ids = [vpc['VpcId'] for vpc in vpc_response.get('Vpcs', [])]

        if vpc_ids:
            response = ec2_client.describe_security_groups(
                Filters=[{'Name': 'vpc-id', 'Values': vpc_ids}]
            )

            for sg in response.get('SecurityGroups', []):
                if sg.get('GroupName') == 'default':
                    continue
                resources.append({
                    'type': 'security_group',
                    'id': sg['GroupId'],
                    'name': sg.get('GroupName'),
                    'attributes': {
                        'description': sg.get('Description'),
                        'vpc_id': sg.get('VpcId'),
                        'ingress_rules': len(sg.get('IpPermissions', [])),
                        'egress_rules': len(sg.get('IpPermissionsEgress', []))
                    }
                })
    except Exception as e:
        pass
    return resources


def get_elastic_ips():
    """Get Elastic IPs."""
    resources = []
    try:
        response = ec2_client.describe_addresses()

        for eip in response.get('Addresses', []):
            name = get_tag_value(eip.get('Tags', []), 'Name') or eip.get('PublicIp')
            resources.append({
                'type': 'elastic_ip',
                'id': eip.get('AllocationId'),
                'name': name,
                'attributes': {
                    'public_ip': eip.get('PublicIp'),
                    'private_ip': eip.get('PrivateIpAddress'),
                    'instance_id': eip.get('InstanceId', 'unattached'),
                    'network_interface': eip.get('NetworkInterfaceId')
                }
            })
    except Exception as e:
        pass
    return resources


def get_internet_gateways():
    """Get Internet Gateways."""
    resources = []
    try:
        response = ec2_client.describe_internet_gateways(
            Filters=[{'Name': 'attachment.state', 'Values': ['available']}]
        )

        for igw in response.get('InternetGateways', []):
            name = get_tag_value(igw.get('Tags', []), 'Name') or igw['InternetGatewayId']
            vpc_id = None
            for attachment in igw.get('Attachments', []):
                vpc_id = attachment.get('VpcId')
                break

            # Skip default VPC gateways
            if vpc_id:
                vpc_response = ec2_client.describe_vpcs(VpcIds=[vpc_id])
                if vpc_response.get('Vpcs') and vpc_response['Vpcs'][0].get('IsDefault'):
                    continue

            resources.append({
                'type': 'internet_gateway',
                'id': igw['InternetGatewayId'],
                'name': name,
                'attributes': {
                    'vpc_id': vpc_id
                }
            })
    except Exception as e:
        pass
    return resources


def get_tag_value(tags, key):
    """Extract tag value by key."""
    for tag in tags:
        if tag.get('Key') == key:
            return tag.get('Value')
    return None


def group_resources(resources):
    """Group resources by type for organized display."""
    grouped = {}
    for resource in resources:
        resource_type = resource['type']
        if resource_type not in grouped:
            grouped[resource_type] = []
        grouped[resource_type].append({
            'name': resource['name'],
            'id': resource['id'],
            'key_info': get_key_info(resource)
        })
    return grouped


def get_key_info(resource):
    """Extract the most important info for each resource type."""
    attrs = resource.get('attributes', {})
    resource_type = resource['type']

    if resource_type == 'instance':
        role = resource.get('role', '')
        public_ip = attrs.get('public_ip', 'None')
        private_ip = attrs.get('private_ip', '')
        state = attrs.get('state', 'unknown')
        return f"{role} | Public: {public_ip} | Private: {private_ip} | {state}"
    elif resource_type == 'vpc':
        return f"{attrs.get('cidr_block', '')} | {attrs.get('state', '')}"
    elif resource_type == 'subnet':
        return f"{attrs.get('cidr_block', '')} | {attrs.get('availability_zone', '')}"
    elif resource_type == 'security_group':
        return f"{attrs.get('ingress_rules', 0)} ingress, {attrs.get('egress_rules', 0)} egress"
    elif resource_type == 'elastic_ip':
        return f"{attrs.get('public_ip', '')} -> {attrs.get('instance_id', 'unattached')}"
    elif resource_type == 'internet_gateway':
        return f"Attached to {attrs.get('vpc_id', 'none')}"
    else:
        return resource['id']


def create_summary(resources):
    """Create a human-readable summary of deployed resources."""
    type_counts = {}
    for r in resources:
        t = r['type']
        type_counts[t] = type_counts.get(t, 0) + 1

    # Find key resources
    instances = [r for r in resources if r['type'] == 'instance']
    vpcs = [r for r in resources if r['type'] == 'vpc']
    eips = [r for r in resources if r['type'] == 'elastic_ip']

    summary_parts = []

    if vpcs:
        vpc_info = [f"{v['name']} ({v['attributes'].get('cidr_block', '')})" for v in vpcs]
        summary_parts.append(f"**VPCs ({len(vpcs)})**: {', '.join(vpc_info)}")

    if instances:
        running = sum(1 for i in instances if i['attributes'].get('state') == 'running')
        summary_parts.append(f"**Instances ({len(instances)})**: {running} running")

        # List instances with details
        instance_details = []
        for inst in sorted(instances, key=lambda x: x['name']):
            name = inst['name']
            role = inst.get('role', '')
            public_ip = inst['attributes'].get('public_ip', 'None')
            private_ip = inst['attributes'].get('private_ip', '')
            state = inst['attributes'].get('state', 'unknown')
            instance_details.append(f"  - **{name}** ({role}): Public IP: {public_ip}, Private IP: {private_ip}, State: {state}")
        if instance_details:
            summary_parts.append("**Instance Details**:\n" + "\n".join(instance_details))

    if eips:
        eip_details = []
        for e in eips:
            eip_details.append(f"  - {e['attributes'].get('public_ip')} -> {e['attributes'].get('instance_id', 'unattached')}")
        summary_parts.append(f"**Elastic IPs ({len(eips)})**:\n" + "\n".join(eip_details))

    # Resource type breakdown
    type_summary = ", ".join([f"{count} {t}(s)" for t, count in sorted(type_counts.items())])
    summary_parts.append(f"**Total Resources**: {type_summary}")

    return "\n\n".join(summary_parts)


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
