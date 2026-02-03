"""
Lambda 2: Analyze Terraform Module
Parses Terraform content and extracts resource information.
Reads files from S3 when called via Bedrock Agent.
"""

import boto3
import json
import os
import re

s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Parses Terraform content and extracts resource information.
    When called from Bedrock Agent, reads files from S3 automatically.

    Input: { "content": "terraform code...", "filename": "main.tf" }
    Or via Agent: reads from S3 bucket
    Output: { "resources": [...], "modules": [...], "variables": [...] }
    """

    # Handle Bedrock Agent event format - read files from S3
    if 'actionGroup' in event:
        # Get optional module_name parameter
        params = {}
        if 'parameters' in event:
            for param in event.get('parameters', []):
                params[param['name']] = param['value']

        module_name = params.get('module_name', '')

        # Read all terraform files from S3
        terraform_bucket = os.environ.get('TERRAFORM_BUCKET')
        if not terraform_bucket:
            return format_response(event, {
                'error': 'Missing TERRAFORM_BUCKET environment variable'
            }, 500)

        content, files_read = read_terraform_files(terraform_bucket, module_name)
        if not content:
            return format_response(event, {
                'error': 'No Terraform files found',
                'message': f'No .tf files found in s3://{terraform_bucket}/terraform/'
            }, 404)

        filename = f"Combined ({len(files_read)} files)"
    else:
        content = event.get('content', '')
        filename = event.get('filename', 'unknown.tf')
        files_read = [filename] if content else []

    if not content:
        return format_response(event, {
            'error': 'No content provided',
            'message': 'Please provide Terraform content to analyze'
        }, 400)

    try:
        # Extract resources
        resources = extract_resources(content)

        # Extract modules
        modules = extract_modules(content)

        # Extract variables
        variables = extract_variables(content)

        # Extract outputs
        outputs = extract_outputs(content)

        # Extract data sources
        data_sources = extract_data_sources(content)

        # Extract locals
        locals_block = extract_locals(content)

        # Extract provider configurations
        providers = extract_providers(content)

        # Create human-readable summary
        summary_text = generate_summary(resources, modules, variables, outputs)

        result = {
            'filename': filename,
            'files_analyzed': files_read if 'files_read' in dir() else [filename],
            'resources': resources,
            'modules': modules,
            'variables': variables,
            'outputs': outputs,
            'data_sources': data_sources,
            'locals': locals_block,
            'providers': providers,
            'summary': summary_text,
            'counts': {
                'resource_count': len(resources),
                'module_count': len(modules),
                'variable_count': len(variables),
                'output_count': len(outputs),
                'data_source_count': len(data_sources)
            }
        }

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'message': 'Failed to analyze Terraform content'
        }, 500)


def read_terraform_files(bucket, module_filter=''):
    """Read all .tf files from S3 bucket."""
    content_parts = []
    files_read = []
    prefix = 'terraform/'

    try:
        paginator = s3_client.get_paginator('list_objects_v2')

        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get('Contents', []):
                key = obj['Key']
                if key.endswith('.tf') and not key.endswith('.tfstate'):
                    # Filter by module if specified
                    if module_filter:
                        if f'modules/{module_filter}/' not in key and module_filter.lower() not in key.lower():
                            continue

                    try:
                        response = s3_client.get_object(Bucket=bucket, Key=key)
                        file_content = response['Body'].read().decode('utf-8')
                        display_name = key.replace(prefix, '')
                        files_read.append(display_name)
                        content_parts.append(file_content)
                    except Exception:
                        pass

        return '\n\n'.join(content_parts), files_read

    except Exception:
        return None, []


def generate_summary(resources, modules, variables, outputs):
    """Generate a human-readable summary of the analysis."""
    lines = []

    # Group resources by type
    resource_types = {}
    for r in resources:
        rtype = r['type']
        if rtype not in resource_types:
            resource_types[rtype] = []
        resource_types[rtype].append(r['name'])

    lines.append("## Infrastructure Analysis\n")

    if modules:
        lines.append("### Modules Used")
        for m in modules:
            lines.append(f"- **{m['name']}**: {m['source']}")
        lines.append("")

    if resource_types:
        lines.append("### Resources by Type")
        for rtype, names in sorted(resource_types.items()):
            lines.append(f"- **{rtype}** ({len(names)}): {', '.join(names[:5])}" +
                        (f" ... +{len(names)-5} more" if len(names) > 5 else ""))
        lines.append("")

    if variables:
        lines.append(f"### Variables ({len(variables)} total)")
        for v in variables[:10]:
            desc = f" - {v['description']}" if v.get('description') else ""
            lines.append(f"- `{v['name']}`{desc}")
        if len(variables) > 10:
            lines.append(f"- ... and {len(variables)-10} more")
        lines.append("")

    if outputs:
        lines.append(f"### Outputs ({len(outputs)} total)")
        for o in outputs[:10]:
            lines.append(f"- `{o['name']}`")
        lines.append("")

    return '\n'.join(lines)


def extract_resources(content):
    """Extract resource blocks from Terraform content."""
    resources = []

    # Match resource blocks: resource "type" "name" { ... }
    pattern = r'resource\s+"([^"]+)"\s+"([^"]+)"\s*\{'
    matches = re.findall(pattern, content)

    for resource_type, resource_name in matches:
        # Try to extract description or tags
        resource_block = extract_block(content, f'resource "{resource_type}" "{resource_name}"')
        description = extract_attribute(resource_block, 'description')
        tags = extract_tags(resource_block)

        resources.append({
            'type': resource_type,
            'name': resource_name,
            'full_name': f'{resource_type}.{resource_name}',
            'description': description,
            'tags': tags
        })

    return resources


def extract_modules(content):
    """Extract module blocks from Terraform content."""
    modules = []

    # Match module blocks
    pattern = r'module\s+"([^"]+)"\s*\{'
    module_names = re.findall(pattern, content)

    for module_name in module_names:
        module_block = extract_block(content, f'module "{module_name}"')

        # Extract source
        source_match = re.search(r'source\s*=\s*"([^"]+)"', module_block)
        source = source_match.group(1) if source_match else ''

        # Extract version if present
        version_match = re.search(r'version\s*=\s*"([^"]+)"', module_block)
        version = version_match.group(1) if version_match else None

        modules.append({
            'name': module_name,
            'source': source,
            'version': version
        })

    return modules


def extract_variables(content):
    """Extract variable blocks from Terraform content."""
    variables = []

    # Match variable blocks
    pattern = r'variable\s+"([^"]+)"\s*\{'
    var_names = re.findall(pattern, content)

    for var_name in var_names:
        var_block = extract_block(content, f'variable "{var_name}"')

        description = extract_attribute(var_block, 'description')
        var_type = extract_attribute(var_block, 'type')
        default = extract_attribute(var_block, 'default')

        variables.append({
            'name': var_name,
            'description': description,
            'type': var_type,
            'has_default': default is not None
        })

    return variables


def extract_outputs(content):
    """Extract output blocks from Terraform content."""
    outputs = []

    pattern = r'output\s+"([^"]+)"\s*\{'
    output_names = re.findall(pattern, content)

    for output_name in output_names:
        output_block = extract_block(content, f'output "{output_name}"')

        description = extract_attribute(output_block, 'description')
        value_match = re.search(r'value\s*=\s*(.+?)(?:\n|$)', output_block)
        value = value_match.group(1).strip() if value_match else ''
        sensitive = 'sensitive' in output_block and 'true' in output_block

        outputs.append({
            'name': output_name,
            'description': description,
            'value_expression': value[:100],  # Truncate long expressions
            'sensitive': sensitive
        })

    return outputs


def extract_data_sources(content):
    """Extract data source blocks from Terraform content."""
    data_sources = []

    pattern = r'data\s+"([^"]+)"\s+"([^"]+)"\s*\{'
    matches = re.findall(pattern, content)

    for data_type, data_name in matches:
        data_sources.append({
            'type': data_type,
            'name': data_name,
            'full_name': f'data.{data_type}.{data_name}'
        })

    return data_sources


def extract_locals(content):
    """Extract locals blocks from Terraform content."""
    locals_list = []

    # Find locals blocks
    pattern = r'locals\s*\{([^}]+)\}'
    matches = re.findall(pattern, content, re.DOTALL)

    for block in matches:
        # Extract individual local values
        local_pattern = r'(\w+)\s*='
        local_names = re.findall(local_pattern, block)
        locals_list.extend(local_names)

    return list(set(locals_list))  # Remove duplicates


def extract_providers(content):
    """Extract provider configurations from Terraform content."""
    providers = []

    pattern = r'provider\s+"([^"]+)"\s*\{'
    provider_names = re.findall(pattern, content)

    for provider_name in provider_names:
        provider_block = extract_block(content, f'provider "{provider_name}"')

        alias_match = re.search(r'alias\s*=\s*"([^"]+)"', provider_block)
        alias = alias_match.group(1) if alias_match else None

        region_match = re.search(r'region\s*=\s*"([^"]+)"', provider_block)
        region = region_match.group(1) if region_match else None

        providers.append({
            'name': provider_name,
            'alias': alias,
            'region': region
        })

    return providers


def extract_block(content, block_start):
    """Extract a complete block starting with the given pattern."""
    start_idx = content.find(block_start)
    if start_idx == -1:
        return ''

    # Find opening brace
    brace_idx = content.find('{', start_idx)
    if brace_idx == -1:
        return ''

    # Count braces to find matching close
    depth = 1
    idx = brace_idx + 1

    while idx < len(content) and depth > 0:
        if content[idx] == '{':
            depth += 1
        elif content[idx] == '}':
            depth -= 1
        idx += 1

    return content[start_idx:idx]


def extract_attribute(block, attr_name):
    """Extract a simple attribute value from a block."""
    pattern = rf'{attr_name}\s*=\s*"([^"]*)"'
    match = re.search(pattern, block)
    return match.group(1) if match else None


def extract_tags(block):
    """Extract tags from a resource block."""
    tags = {}
    tags_match = re.search(r'tags\s*=\s*\{([^}]+)\}', block)
    if tags_match:
        tags_content = tags_match.group(1)
        tag_pattern = r'(\w+)\s*=\s*"([^"]*)"'
        for key, value in re.findall(tag_pattern, tags_content):
            tags[key] = value
    return tags


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
