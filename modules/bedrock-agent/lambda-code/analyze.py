"""
Lambda 2: Analyze Terraform Module
Parses Terraform content and extracts resource information.
"""

import json
import re


def lambda_handler(event, context):
    """
    Parses Terraform content and extracts resource information.

    Input: { "content": "terraform code...", "filename": "main.tf" }
    Output: { "resources": [...], "modules": [...], "variables": [...] }
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
        filename = params.get('filename', 'unknown.tf')
    else:
        content = event.get('content', '')
        filename = event.get('filename', 'unknown.tf')

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

        result = {
            'filename': filename,
            'resources': resources,
            'modules': modules,
            'variables': variables,
            'outputs': outputs,
            'data_sources': data_sources,
            'locals': locals_block,
            'providers': providers,
            'summary': {
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
