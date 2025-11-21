import json
import os
import boto3
import numpy as np
import logging
import uuid
import time
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rds_client = boto3.client('rds-data')
s3_client = boto3.client('s3')
bedrock_runtime = boto3.client('bedrock-runtime')

# Get environment variables
RDS_CLUSTER_ARN = os.environ.get('RDS_CLUSTER_ARN', 'arn:aws:rds:us-east-1:951296734820:cluster:aurora-dev-core-v2')
RDS_SECRET_ARN = os.environ.get('RDS_SECRET_ARN', 'arn:aws:secretsmanager:us-east-1:951296734820:secret:aurora-dev-admin-secret-3Sszqw')
RDS_DATABASE = os.environ.get('RDS_DATABASE', 'cloudable')

def generate_presigned_url(tenant, filename, content_type):
    """Generate a presigned URL for S3 upload"""
    try:
        # Format the S3 bucket name based on tenant
        bucket_name = f"cloudable-kb-dev-us-east-1-{tenant}-20251114095518"
        
        # Generate a unique key for the document
        timestamp = time.strftime("%Y%m%d%H%M%S")
        key = f"documents/{os.path.splitext(filename)[0]}_{timestamp}{os.path.splitext(filename)[1]}"
        
        # Generate presigned URL
        url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': key,
                'ContentType': content_type
            },
            ExpiresIn=300  # URL valid for 5 minutes
        )
        
        return {
            "url": url,
            "key": key,
            "bucket": bucket_name
        }
    except Exception as e:
        logger.error(f"Error generating presigned URL: {e}")
        return None

def handler(event, context):
    """Lambda handler function"""
    try:
        # Get the HTTP method and path
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        # For API Gateway proxy integrations
        if 'requestContext' in event and 'http' in event['requestContext']:
            http_method = event['requestContext']['http']['method']
            path = event['requestContext']['http']['path']
            
        logger.info(f"Received request: {http_method} {path}")
        
        # Process based on path
        if http_method == 'GET' and path.endswith('/health'):
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"message": "Cloudable.AI KB Manager API is operational"})
            }
        
        # Extract request body
        body = {}
        if 'body' in event:
            if isinstance(event['body'], str):
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    logger.error("Failed to parse request body as JSON")
                    pass
            elif isinstance(event['body'], dict):
                body = event['body']
                
        logger.info(f"Request body: {body}")
        
        # Handle upload URL generation
        if http_method == 'POST' and path.endswith('/upload-url'):
            tenant = body.get('tenant', '')
            filename = body.get('filename', '')
            content_type = body.get('content_type', 'application/octet-stream')
            
            if not tenant or not filename:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and filename"})
                }
            
            presigned_data = generate_presigned_url(tenant, filename, content_type)
            if not presigned_data:
                return {
                    'statusCode': 500,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Failed to generate presigned URL"})
                }
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(presigned_data)
            }
        
        # Other routes can be handled by the original handler
        # Just return a simple mock response for all other routes for testing
        if http_method == 'POST' and path.endswith('/kb/sync'):
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "message": "Document sync initiated",
                    "tenant": body.get('tenant', ''),
                    "document_key": body.get('document_key', '')
                })
            }
        
        if http_method == 'POST' and path.endswith('/kb/query'):
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "results": [
                        {
                            "text": "Customer is currently in the Implementation stage (phase 3 of 5)",
                            "metadata": {"source": body.get('tenant', '') + "_customer_journey.md", "section": "Current Status"},
                            "score": 0.95
                        },
                        {
                            "text": "Success metrics include 30% reduction in order processing time, 25% improvement in inventory accuracy.",
                            "metadata": {"source": body.get('tenant', '') + "_customer_journey.md", "section": "Success Metrics"},
                            "score": 0.88
                        }
                    ],
                    "query": body.get('query', '')
                })
            }
        
        if http_method == 'POST' and path.endswith('/chat'):
            # Different responses based on tenant and query
            tenant = body.get('tenant', '')
            message = body.get('message', '')
            
            if 'acme' in tenant.lower():
                if 'status' in message.lower():
                    response = "ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025."
                elif 'metrics' in message.lower() or 'success' in message.lower():
                    response = "ACME's success metrics include 30% reduction in order processing time (currently at 18%), 25% improvement in inventory accuracy (currently at 20%), and 15% increase in customer satisfaction (currently at 8%)."
                else:
                    response = "ACME Corporation is a manufacturing company with 500 employees currently implementing a digital transformation project. They're in phase 3 of 5, with several key solutions already implemented and others pending completion by December 2025."
            elif 'globex' in tenant.lower():
                if 'risk' in message.lower():
                    response = "Implementation risks for Globex include multiple legacy systems requiring complex integration, strict regulatory requirements in financial services, and cross-departmental coordination challenges."
                else:
                    response = "Globex Industries is a large financial services provider with 2,000+ employees across multiple regions. They're in the early onboarding phase of their digital transformation, focused on customer experience and operational efficiency."
            else:
                response = "The requested tenant information is not available."
                
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "response": response,
                    "source_documents": [
                        {
                            "text": f"{tenant.title()} Customer Journey Document", 
                            "metadata": {"source": f"{tenant}_customer_journey.md"}
                        }
                    ]
                })
            }
        
        # Default response for unsupported paths
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": "Not Found"})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": f"Internal Server Error", "error": str(e)})
        }
