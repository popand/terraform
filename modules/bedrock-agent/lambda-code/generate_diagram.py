"""
Lambda: Generate Architecture Diagram
Reads Terraform files and generates a Mermaid diagram of the infrastructure.
The diagram can be rendered in chat UI using a Mermaid renderer.
"""

import boto3
import json
import os

s3_client = boto3.client('s3')
bedrock_runtime = boto3.client('bedrock-runtime')
ec2_client = boto3.client('ec2')


def lambda_handler(event, context):
    """
    Generates a Mermaid architecture diagram from Terraform files.
    Returns the diagram code for rendering in chat.
    """

    terraform_bucket = os.environ.get('TERRAFORM_BUCKET')

    if not terraform_bucket:
        return format_response(event, {
            'error': 'Missing environment variable',
            'message': 'TERRAFORM_BUCKET must be configured'
        }, 500)

    # Get diagram type and format from parameters
    diagram_type = 'architecture'  # default
    output_format = 'ascii'  # default to ascii for better chat display
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
        diagram_type = params.get('diagram_type', 'architecture')
        output_format = params.get('format', 'ascii')
    else:
        diagram_type = event.get('diagram_type', 'architecture')
        output_format = event.get('format', 'ascii')

    try:
        # For "deployed" diagram type, read from live infrastructure
        if diagram_type == 'deployed':
            state_bucket = os.environ.get('STATE_BUCKET', terraform_bucket)
            deployed_info = get_deployed_infrastructure(state_bucket)

            if not deployed_info:
                return format_response(event, {
                    'error': 'No deployed infrastructure found',
                    'message': 'No Terraform state found. Run terraform apply first.'
                }, 404)

            diagram = generate_deployed_diagram(deployed_info)
            message = 'Deployed infrastructure diagram generated from live state.'
        else:
            # Read Terraform files from S3
            terraform_content = read_terraform_files(terraform_bucket)

            if not terraform_content:
                return format_response(event, {
                    'error': 'No Terraform files found',
                    'message': f'No .tf files found in s3://{terraform_bucket}/terraform/'
                }, 404)

            # Generate diagram using Bedrock
            if output_format == 'mermaid':
                diagram = generate_mermaid_diagram(terraform_content, diagram_type)
                message = 'Architecture diagram generated successfully. The diagram below shows the infrastructure layout.'
            else:
                diagram = generate_ascii_diagram(terraform_content, diagram_type)
                message = 'ASCII architecture diagram generated successfully.'

        result = {
            'status': 'success',
            'diagram_type': diagram_type,
            'diagram': diagram,
            'format': output_format,
            'message': message
        }

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to generate diagram'
        }, 500)


def read_terraform_files(bucket):
    """Read all .tf files from S3 bucket."""

    content_parts = []
    prefix = 'terraform/'

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
                        # Include more content for diagram generation
                        truncated = file_content[:1000] + ('...' if len(file_content) > 1000 else '')
                        content_parts.append(f"### {display_name}\n```hcl\n{truncated}\n```")
                    except Exception:
                        pass

        return '\n'.join(content_parts) if content_parts else None

    except Exception:
        return None


def generate_mermaid_diagram(terraform_content, diagram_type):
    """Use Bedrock to generate a Mermaid diagram from Terraform code."""

    if diagram_type == 'network':
        focus = "Focus on VPCs, subnets, route tables, internet gateways, NAT gateways, and network connectivity."
    elif diagram_type == 'security':
        focus = "Focus on security groups, firewalls, IAM roles, and security boundaries."
    elif diagram_type == 'compute':
        focus = "Focus on EC2 instances, load balancers, and compute resources."
    else:  # architecture (default)
        focus = "Show the complete infrastructure including VPCs, subnets, EC2 instances, firewalls, and their connections."

    prompt = f"""Analyze this Terraform configuration and create a Mermaid diagram.
{focus}

Requirements:
1. Use Mermaid flowchart syntax (graph TD or graph LR)
2. Keep it clean and readable - max 20-25 nodes
3. Use meaningful labels (not just resource IDs)
4. Group related resources using subgraphs for VPCs
5. Show connections between resources with arrows
6. Use appropriate shapes: [(database)], {{decision}}, [process], ([service])

Example format:
```mermaid
graph TD
    subgraph VPC1["VPC 1 - 10.0.0.0/16"]
        IGW1[Internet Gateway]
        PUB1[Public Subnet<br/>10.0.1.0/24]
        PRIV1[Private Subnet<br/>10.0.2.0/24]
        FW1{{FortiGate Firewall}}
        EC2_1([Ubuntu Server])
    end

    Internet((Internet)) --> IGW1
    IGW1 --> PUB1
    PUB1 --> FW1
    FW1 --> PRIV1
    PRIV1 --> EC2_1
```

Terraform Configuration:
{terraform_content}

Generate ONLY the Mermaid diagram code (starting with ```mermaid and ending with ```). No other text."""

    try:
        response = bedrock_runtime.invoke_model(
            modelId='us.anthropic.claude-sonnet-4-20250514-v1:0',
            contentType='application/json',
            accept='application/json',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 2000,
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            })
        )

        response_body = json.loads(response['body'].read())
        diagram_text = response_body['content'][0]['text']

        # Extract just the mermaid code if wrapped
        if '```mermaid' in diagram_text:
            start = diagram_text.find('```mermaid')
            end = diagram_text.find('```', start + 10)
            if end != -1:
                diagram_text = diagram_text[start:end + 3]

        return diagram_text

    except Exception as e:
        # Fallback to a basic diagram
        return generate_basic_diagram()


def generate_ascii_diagram(terraform_content, diagram_type):
    """Use Bedrock to generate an ASCII diagram from Terraform code."""

    if diagram_type == 'network':
        focus = "Focus on VPCs, subnets, route tables, internet gateways, and network connectivity."
    elif diagram_type == 'security':
        focus = "Focus on security groups, firewalls, and security boundaries."
    elif diagram_type == 'compute':
        focus = "Focus on EC2 instances and compute resources."
    else:  # architecture (default)
        focus = "Show the complete infrastructure including VPCs, subnets, EC2 instances, firewalls, and VPN connections."

    prompt = f"""Analyze this Terraform configuration and create a simple ASCII diagram.
{focus}

Requirements:
1. Use simple ASCII box characters: +, -, |, =
2. Keep it clean and readable - fit within 80 characters width
3. Use meaningful labels
4. Show VPCs as large boxes containing their resources
5. Show VPN tunnel connection between FortiGates with === or ~~~
6. Use clear arrows for traffic flow: --> or <-->

Example format:
```
                              INTERNET
                                 |
            +--------------------+--------------------+
            |                                         |
    +-------v--------+                       +--------v-------+
    |    VPC 1       |                       |     VPC 2      |
    | 10.0.0.0/16    |                       | 10.100.0.0/16  |
    |                |                       |                |
    | +------------+ |                       | +------------+ |
    | | FortiGate1 |=========================| FortiGate2 | |
    | | 3.x.x.x    | |     VPN Tunnel       | | 3.x.x.x    | |
    | +-----+------+ |                       | +-----+------+ |
    |       |        |                       |       |        |
    | +-----v------+ |                       | +-----v------+ |
    | | Ubuntu-1   | |                       | | Ubuntu-2   | |
    | | 10.0.1.10  | |                       | | 10.100.1.10| |
    | +------------+ |                       | +------------+ |
    +----------------+                       +----------------+
```

Terraform Configuration:
{terraform_content}

Generate ONLY the ASCII diagram inside a code block. No other text. Make it informative with real IP addresses if visible in the config."""

    try:
        response = bedrock_runtime.invoke_model(
            modelId='us.anthropic.claude-sonnet-4-20250514-v1:0',
            contentType='application/json',
            accept='application/json',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 2000,
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            })
        )

        response_body = json.loads(response['body'].read())
        diagram_text = response_body['content'][0]['text']

        # Clean up the response - extract just the diagram
        if '```' in diagram_text:
            start = diagram_text.find('```')
            end = diagram_text.find('```', start + 3)
            if end != -1:
                # Get content between the backticks
                diagram_text = diagram_text[start:end + 3]

        return diagram_text

    except Exception as e:
        # Fallback to a basic ASCII diagram
        return generate_basic_ascii_diagram()


def generate_basic_ascii_diagram():
    """Generate a basic fallback ASCII diagram."""

    return """```
                              INTERNET
                                 |
            +--------------------+--------------------+
            |                                         |
    +-------v--------+                       +--------v-------+
    |    VPC 1       |                       |     VPC 2      |
    | 10.0.0.0/16    |                       | 10.100.0.0/16  |
    |                |                       |                |
    | +------------+ |                       | +------------+ |
    | | FortiGate1 |=========================| FortiGate2 | |
    | +-----+------+ |     VPN Tunnel       | +-----+------+ |
    |       |        |                       |       |        |
    | +-----v------+ |                       | +-----v------+ |
    | | Ubuntu-1   | |                       | | Ubuntu-2   | |
    | +------------+ |                       | +------------+ |
    +----------------+                       +----------------+
```"""


def generate_basic_diagram():
    """Generate a basic fallback Mermaid diagram."""

    return """```mermaid
graph TD
    subgraph VPC1["VPC 1"]
        IGW1[Internet Gateway]
        PUB1[Public Subnet]
        PRIV1[Private Subnet]
        FW1{{FortiGate}}
        EC2_1([Server])
    end

    subgraph VPC2["VPC 2"]
        IGW2[Internet Gateway]
        PUB2[Public Subnet]
        PRIV2[Private Subnet]
        FW2{{FortiGate}}
        EC2_2([Server])
    end

    Internet((Internet)) --> IGW1
    Internet --> IGW2
    IGW1 --> FW1
    IGW2 --> FW2
    FW1 -.VPN Tunnel.- FW2
    FW1 --> EC2_1
    FW2 --> EC2_2
```"""


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
