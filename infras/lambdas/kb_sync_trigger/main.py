import json
import os
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock_agent = boto3.client('bedrock-agent')

def handler(event, context):
    """
    Lambda function to trigger a sync operation for a Knowledge Base
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract request parameters
        body = json.loads(event.get('body', '{}'))
        tenant_id = body.get('tenant_id')
        document_id = body.get('document_id')
        
        if not tenant_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': 'Missing tenant_id parameter'
                })
            }
            
        # Get Knowledge Base ID from environment variables
        kb_id_env_var = f"KB_ID_{tenant_id.upper()}"
        kb_id = os.environ.get(kb_id_env_var)
        
        if not kb_id:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': f'Knowledge Base not found for tenant {tenant_id}'
                })
            }
            
        # Trigger KB sync operation
        logger.info(f"Starting KB sync for tenant {tenant_id}, document_id: {document_id}")
        
        # This is a placeholder - actual implementation would use Bedrock APIs
        # or trigger a sync job based on document_id
        
        return {
            'statusCode': 202,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': 'KB sync initiated',
                'tenant_id': tenant_id,
                'document_id': document_id,
                'status': 'processing'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in KB sync trigger: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}'
            })
        }
import os
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock_agent = boto3.client('bedrock-agent')

def handler(event, context):
    """
    Lambda function to trigger a sync operation for a Knowledge Base
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract request parameters
        body = json.loads(event.get('body', '{}'))
        tenant_id = body.get('tenant_id')
        document_id = body.get('document_id')
        
        if not tenant_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': 'Missing tenant_id parameter'
                })
            }
            
        # Get Knowledge Base ID from environment variables
        kb_id_env_var = f"KB_ID_{tenant_id.upper()}"
        kb_id = os.environ.get(kb_id_env_var)
        
        if not kb_id:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': f'Knowledge Base not found for tenant {tenant_id}'
                })
            }
            
        # Trigger KB sync operation
        logger.info(f"Starting KB sync for tenant {tenant_id}, document_id: {document_id}")
        
        # This is a placeholder - actual implementation would use Bedrock APIs
        # or trigger a sync job based on document_id
        
        return {
            'statusCode': 202,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': 'KB sync initiated',
                'tenant_id': tenant_id,
                'document_id': document_id,
                'status': 'processing'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in KB sync trigger: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}'
            })
        }
