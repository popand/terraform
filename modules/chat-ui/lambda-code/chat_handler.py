"""
Chat Handler Lambda - Invokes Bedrock Agent and returns response
"""
import json
import os
import boto3
from botocore.config import Config

# Initialize clients
config = Config(
    retries={'max_attempts': 3, 'mode': 'standard'}
)
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', config=config)

# Environment variables
AGENT_ID = os.environ.get('AGENT_ID')
AGENT_ALIAS_ID = os.environ.get('AGENT_ALIAS_ID')

def lambda_handler(event, context):
    """Handle chat requests and invoke Bedrock Agent."""

    # Handle CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return cors_response(200, {})

    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        message = body.get('message', '')
        session_id = body.get('sessionId', 'default-session')

        if not message:
            return cors_response(400, {'error': 'Message is required'})

        if not AGENT_ID or not AGENT_ALIAS_ID:
            return cors_response(500, {'error': 'Agent configuration missing'})

        # Invoke Bedrock Agent
        response = invoke_agent(message, session_id)

        return cors_response(200, {'response': response})

    except json.JSONDecodeError:
        return cors_response(400, {'error': 'Invalid JSON in request body'})
    except Exception as e:
        print(f"Error: {str(e)}")
        return cors_response(500, {'error': str(e)})


def invoke_agent(message: str, session_id: str) -> str:
    """Invoke Bedrock Agent and collect streaming response."""

    response = bedrock_agent_runtime.invoke_agent(
        agentId=AGENT_ID,
        agentAliasId=AGENT_ALIAS_ID,
        sessionId=session_id,
        inputText=message,
        enableTrace=False
    )

    # Collect the streaming response
    completion = ""
    for event in response.get('completion', []):
        if 'chunk' in event:
            chunk_data = event['chunk']
            if 'bytes' in chunk_data:
                completion += chunk_data['bytes'].decode('utf-8')

    return completion if completion else "No response from agent"


def cors_response(status_code: int, body: dict) -> dict:
    """Return response with CORS headers."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,x-api-key,Authorization',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps(body)
    }
