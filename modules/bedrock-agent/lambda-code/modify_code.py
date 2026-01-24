"""
Lambda 6: Modify Terraform Code
Modifies Terraform files based on AI-generated suggestions.
"""

import boto3
import json
import os
from datetime import datetime

s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Modifies Terraform files based on AI-generated suggestions.

    Input: {
        "file_path": "main.tf",
        "modification_type": "add_resource|update_resource|add_variable|refactor|security_fix",
        "description": "Add VPC flow logs to vpc1 module",
        "code_changes": [
            {
                "file": "main.tf",
                "action": "insert_after|insert_before|replace|append|delete",
                "anchor": "module \"vpc1\" {",
                "content": "  enable_flow_logs = true\n",
                "old_content": ""  # for replace action
            }
        ],
        "dry_run": true
    }
    Output: { "status": "success", "changes_made": [...], "backup_location": "..." }
    """

    # Handle Bedrock Agent event format
    if 'actionGroup' in event:
        params = {}
        if 'requestBody' in event and 'content' in event['requestBody']:
            body = event['requestBody']['content'].get('application/json', {})
            if 'properties' in body:
                for prop in body['properties']:
                    params[prop['name']] = prop['value']

        modification_type = params.get('modification_type', 'update_resource')
        description = params.get('description', '')
        code_changes = params.get('code_changes', [])
        dry_run = str(params.get('dry_run', 'true')).lower() == 'true'
        terraform_prefix = params.get('terraform_prefix', 'terraform/')

        # Parse code_changes if it's a string
        if isinstance(code_changes, str):
            try:
                code_changes = json.loads(code_changes)
            except:
                code_changes = []
    else:
        modification_type = event.get('modification_type', 'update_resource')
        description = event.get('description', '')
        code_changes = event.get('code_changes', [])
        dry_run = event.get('dry_run', True)
        terraform_prefix = event.get('terraform_prefix', 'terraform/')

    terraform_bucket = os.environ.get('TERRAFORM_BUCKET')
    backup_prefix = os.environ.get('BACKUP_PREFIX', 'backups/')

    if not terraform_bucket:
        return format_response(event, {
            'error': 'TERRAFORM_BUCKET environment variable not set',
            'message': 'Please configure the Lambda function'
        }, 500)

    if not code_changes:
        return format_response(event, {
            'error': 'No code_changes provided',
            'message': 'Please specify the changes to make'
        }, 400)

    # Track all changes
    changes_made = []
    backup_location = None
    previews = []

    try:
        # Create backup before making changes (unless dry_run)
        if not dry_run:
            backup_location = create_backup(terraform_bucket, terraform_prefix, backup_prefix)

        for change in code_changes:
            file_path = change.get('file')
            action = change.get('action', 'append')
            anchor = change.get('anchor', '')
            content = change.get('content', '')
            old_content = change.get('old_content', '')

            if not file_path:
                continue

            # Read current file
            s3_key = f"{terraform_prefix}{file_path}"
            current_content = read_file(terraform_bucket, s3_key)

            # Apply the change
            new_content, change_details = apply_change(
                current_content, action, anchor, content, old_content
            )

            if new_content != current_content:
                change_record = {
                    'file': file_path,
                    'action': action,
                    'description': change_details,
                    'lines_added': content.count('\n') + 1 if content else 0,
                    'lines_removed': old_content.count('\n') + 1 if old_content else 0
                }

                if dry_run:
                    # Show preview of changes
                    preview = generate_diff_preview(current_content, new_content, file_path)
                    change_record['preview'] = preview
                    previews.append({
                        'file': file_path,
                        'preview': preview
                    })
                else:
                    # Write changes
                    write_file(terraform_bucket, s3_key, new_content, modification_type)

                changes_made.append(change_record)

        # Prepare result
        result = {
            'status': 'success' if changes_made else 'no_changes',
            'dry_run': dry_run,
            'modification_type': modification_type,
            'description': description,
            'changes_made': changes_made,
            'total_files_modified': len(set(c['file'] for c in changes_made)),
            'backup_location': backup_location
        }

        if dry_run:
            result['message'] = 'Changes previewed (dry_run=true). Set dry_run=false to apply.'
            result['previews'] = previews
        else:
            result['message'] = 'Changes applied successfully'
            result['next_steps'] = [
                'Run terraform validate to check syntax',
                'Run terraform plan to review changes',
                'Run terraform apply to deploy changes'
            ]

        return format_response(event, result, 200)

    except Exception as e:
        return format_response(event, {
            'error': str(e),
            'backup_location': backup_location,
            'message': 'Error occurred. Backup available for restore if needed.'
        }, 500)


def read_file(bucket, key):
    """Read file content from S3."""
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        return response['Body'].read().decode('utf-8')
    except s3_client.exceptions.NoSuchKey:
        return ""


def write_file(bucket, key, content, modification_type):
    """Write file content to S3."""
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=content.encode('utf-8'),
        ContentType='text/plain',
        Metadata={
            'modified-by': 'bedrock-agent',
            'modification-type': modification_type,
            'timestamp': datetime.now().isoformat()
        }
    )


def apply_change(content, action, anchor, new_content, old_content):
    """Apply a single change to file content."""
    details = ""

    if action == 'append':
        # Add to end of file
        if content and not content.endswith('\n'):
            content += '\n'
        result = content + new_content
        details = f"Appended {len(new_content)} characters to end of file"

    elif action == 'insert_after':
        # Insert after anchor line
        if anchor in content:
            result = content.replace(anchor, anchor + '\n' + new_content)
            details = f"Inserted content after '{anchor[:50]}...'"
        else:
            result = content
            details = f"Anchor not found: '{anchor[:50]}...'"

    elif action == 'insert_before':
        # Insert before anchor line
        if anchor in content:
            result = content.replace(anchor, new_content + '\n' + anchor)
            details = f"Inserted content before '{anchor[:50]}...'"
        else:
            result = content
            details = f"Anchor not found: '{anchor[:50]}...'"

    elif action == 'replace':
        # Replace old_content with new_content
        if old_content and old_content in content:
            result = content.replace(old_content, new_content)
            details = f"Replaced content ({len(old_content)} chars -> {len(new_content)} chars)"
        else:
            result = content
            details = "Content to replace not found"

    elif action == 'delete':
        # Delete the anchor content
        if anchor in content:
            result = content.replace(anchor, '')
            details = "Deleted content block"
        else:
            result = content
            details = "Content to delete not found"

    else:
        result = content
        details = f"Unknown action: {action}"

    return result, details


def create_backup(bucket, terraform_prefix, backup_prefix):
    """Create a backup of all Terraform files."""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    full_backup_prefix = f"{backup_prefix}{timestamp}/"

    # List and copy all .tf files
    paginator = s3_client.get_paginator('list_objects_v2')
    backed_up = 0

    for page in paginator.paginate(Bucket=bucket, Prefix=terraform_prefix):
        for obj in page.get('Contents', []):
            key = obj['Key']
            if key.endswith('.tf') or key.endswith('.tpl') or key.endswith('.tfvars'):
                # Copy to backup location
                backup_key = key.replace(terraform_prefix, full_backup_prefix)
                s3_client.copy_object(
                    Bucket=bucket,
                    CopySource={'Bucket': bucket, 'Key': key},
                    Key=backup_key
                )
                backed_up += 1

    return f"s3://{bucket}/{full_backup_prefix} ({backed_up} files)"


def generate_diff_preview(old_content, new_content, filename):
    """Generate a simple diff preview."""
    old_lines = old_content.split('\n')
    new_lines = new_content.split('\n')

    # Simple diff - show added/removed lines
    preview_lines = [f"--- {filename} (original)", f"+++ {filename} (modified)"]

    # Find differences (simplified)
    import difflib
    diff = difflib.unified_diff(
        old_lines,
        new_lines,
        fromfile=f'{filename} (original)',
        tofile=f'{filename} (modified)',
        lineterm=''
    )

    preview_lines = list(diff)[:50]  # Limit preview size

    return '\n'.join(preview_lines) if preview_lines else 'No changes detected'


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
