import os
import json
import boto3
import uuid
from datetime import datetime, timedelta
import logging
from typing import Optional, Dict, Any
import re
import html
from rest_adapter import extract_request_details_from_rest_event

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3', region_name=os.environ.get('REGION', 'us-east-1'), config=boto3.session.Config(signature_version='s3v4'))
bedrock_client = boto3.client('bedrock-agent', region_name=os.environ.get('REGION', 'us-east-1'))
bedrock_runtime = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('REGION', 'us-east-1'))
rds_client = boto3.client('rds-data', region_name=os.environ.get('REGION', 'us-east-1'))

def validate_input(tenant_id: str, customer_id: str = None) -> dict:
    """Validate tenant and customer IDs"""
    errors = []
    
    if not tenant_id or not isinstance(tenant_id, str):
        errors.append("Tenant ID is required and must be a string")
    elif not re.match(r'^[a-zA-Z0-9_-]{1,20}$', tenant_id):
        errors.append("Invalid tenant ID format")
    
    if customer_id is not None:
        if not customer_id or not isinstance(customer_id, str):
            errors.append("Customer ID must be a string")
        elif not re.match(r'^[a-zA-Z0-9_-]{1,20}$', customer_id):
            errors.append("Invalid customer ID format")
    
    if errors:
        return {"valid": False, "error": "; ".join(errors)}
    
    return {"valid": True}

def generate_presigned_url(tenant_id: str, filename: str) -> dict:
    """Generate presigned URL for document upload"""
    try:
        # Validate inputs
        validation = validate_input(tenant_id)
        if not validation["valid"]:
            return {"error": validation["error"], "statusCode": 400}
        
        # Sanitize filename
        safe_filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
        if len(safe_filename) > 100:
            safe_filename = safe_filename[:100]
        
        # Generate unique key with timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        document_key = f"documents/{timestamp}_{uuid.uuid4().hex[:8]}_{safe_filename}"
        
        # Get tenant bucket name from environment
        bucket_name = os.environ.get(f'BUCKET_{tenant_id.upper()}')
        if not bucket_name:
            return {"error": "Tenant bucket not configured", "statusCode": 404}
        
        # Get KMS key ARN from environment
        kms_key_arn = os.environ.get('S3_KMS_KEY_ARN')
        
        # Generate presigned URL with KMS encryption (valid for 1 hour)
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': document_key,
                'ContentType': 'application/pdf',
                'ServerSideEncryption': 'aws:kms',
                'SSEKMSKeyId': kms_key_arn
            },
            ExpiresIn=3600
        )
        
        logger.info(f"Generated presigned URL for tenant {tenant_id}, key: {document_key}")
        
        return {
            "presigned_url": presigned_url,
            "document_key": document_key,
            "bucket_name": bucket_name,
            "expires_in": 3600,
            "kms_key_id": kms_key_arn  # Include KMS key ID in response for client usage
        }
        
    except Exception as e:
        logger.error(f"Error generating presigned URL: {str(e)}")
        return {"error": f"Failed to generate upload URL: {str(e)}", "statusCode": 500}

def generate_presigned_post(tenant_id: str, filename: str, content_type: str = "application/pdf") -> dict:
    """Generate a presigned POST form for document upload (robust with SSE-KMS)"""
    try:
        validation = validate_input(tenant_id)
        if not validation["valid"]:
            return {"error": validation["error"], "statusCode": 400}

        safe_filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)[:100]
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        document_key = f"documents/{timestamp}_{uuid.uuid4().hex[:8]}_{safe_filename}"

        bucket_name = os.environ.get(f'BUCKET_{tenant_id.upper()}')
        if not bucket_name:
            return {"error": "Tenant bucket not configured", "statusCode": 404}

        kms_key_arn = os.environ.get('S3_KMS_KEY_ARN')

        conditions = [
            {"bucket": bucket_name},
            ["starts-with", "$key", "documents/"],
            {"x-amz-server-side-encryption": "aws:kms"},
            {"x-amz-server-side-encryption-aws-kms-key-id": kms_key_arn},
            {"Content-Type": content_type}
        ]

        fields = {
            "key": document_key,
            "x-amz-server-side-encryption": "aws:kms",
            "x-amz-server-side-encryption-aws-kms-key-id": kms_key_arn,
            "Content-Type": content_type
        }

        post = s3_client.generate_presigned_post(
            Bucket=bucket_name,
            Key=document_key,
            Fields=fields,
            Conditions=conditions,
            ExpiresIn=3600
        )

        logger.info(f"Generated presigned POST for tenant {tenant_id}, key: {document_key}")

        return {
            "url": post["url"],
            "fields": post["fields"],
            "document_key": document_key,
            "bucket_name": bucket_name,
            "expires_in": 3600
        }

    except Exception as e:
        logger.error(f"Error generating presigned POST: {str(e)}")
        return {"error": f"Failed to generate upload form: {str(e)}", "statusCode": 500}

def trigger_knowledge_sync(tenant_id: str, document_key: str) -> dict:
    """Trigger knowledge base synchronization after document upload"""
    try:
        # Get knowledge base ID for tenant
        kb_id = os.environ.get(f'KB_ID_{tenant_id.upper()}')
        ds_id = os.environ.get(f'DS_ID_{tenant_id.upper()}')
        
        if not kb_id or not ds_id:
            logger.error(f"Knowledge base not configured for tenant {tenant_id}")
            return {"error": "Knowledge base not configured for tenant", "statusCode": 404}
        
        # Start ingestion job
        response = bedrock_client.start_ingestion_job(
            knowledgeBaseId=kb_id,
            dataSourceId=ds_id,
            description=f"Auto-sync after document upload: {document_key}"
        )
        
        ingestion_job_id = response['ingestionJob']['ingestionJobId']
        
        logger.info(f"Started ingestion job {ingestion_job_id} for tenant {tenant_id}")
        
        return {
            "ingestion_job_id": ingestion_job_id,
            "status": "started",
            "knowledge_base_id": kb_id
        }
        
    except Exception as e:
        logger.error(f"Error triggering knowledge sync: {str(e)}")
        return {"error": f"Failed to sync knowledge base: {str(e)}", "statusCode": 500}

def query_knowledge_base(tenant_id: str, customer_id: str, query: str) -> dict:
    """Query the knowledge base using RDS with pgvector"""
    try:
        # Validate inputs
        validation = validate_input(tenant_id, customer_id)
        if not validation["valid"]:
            return {"error": validation["error"], "statusCode": 400}
        
        # Validate and sanitize query
        if not query or len(query.strip()) < 3:
            return {"error": "Query must be at least 3 characters", "statusCode": 400}
        if len(query) > 1000:
            return {"error": "Query too long (max 1000 characters)", "statusCode": 400}
        
        sanitized_query = html.escape(query.strip())
        
        # Generate embeddings using Bedrock Titan
        embedding_result = generate_embedding(sanitized_query)
        if "error" in embedding_result:
            return {"error": embedding_result["error"], "statusCode": 500}
            
        # Get RDS connection parameters
        cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
        secret_arn = os.environ.get('RDS_SECRET_ARN')
        db_name = os.environ.get('RDS_DATABASE', 'cloudable')
        table_name = f"kb_vectors_{tenant_id}"
        
        # Log the parameters for debugging
        logger.info(f"RDS Query Parameters: cluster_arn={cluster_arn}, db_name={db_name}, table={table_name}")
        
        # SQL for vector similarity search with pgvector
        sql_query = f"""
        SELECT chunk_text, metadata, 1 - (embedding <=> :embedding) AS score
        FROM {table_name}
        ORDER BY embedding <=> :embedding
        LIMIT 5;
        """
        
        # Execute SQL using Data API
        try:
            # Log key RDS connection info, ensuring secrets are not leaked
            logger.info(f"RDS Query: Connecting to database {db_name}, table {table_name}")
            logger.info(f"Using cluster ARN ending with: ...{cluster_arn[-8:]}")
            logger.info(f"Using secret ARN ending with: ...{secret_arn[-8:]}")
            logger.info(f"Query will search for {len(embedding_result['embedding'])} dimensional vectors")
            
            # Create a metric for query start time
            start_time = datetime.now()
            
            # Execute the query
            response = rds_client.execute_statement(
                resourceArn=cluster_arn,
                secretArn=secret_arn,
                database=db_name,
                sql=sql_query,
                parameters=[
                    {'name': 'embedding', 'value': {'arrayValue': {'floatValues': embedding_result["embedding"]}}}
                ]
            )
            
            # Calculate query duration
            duration_ms = (datetime.now() - start_time).total_seconds() * 1000
            record_count = len(response.get('records', []))
            
            # Log success with performance metrics
            logger.info(f"RDS Query executed successfully in {duration_ms:.2f}ms, returned {record_count} records")
            
            # Publish custom CloudWatch metrics for monitoring
            try:
                cloudwatch_client = boto3.client('cloudwatch')
                cloudwatch_client.put_metric_data(
                    Namespace='CloudableAI/KB',
                    MetricData=[
                        {
                            'MetricName': 'QueryDuration',
                            'Dimensions': [
                                {'Name': 'TenantId', 'Value': tenant_id},
                                {'Name': 'Environment', 'Value': os.environ.get('ENV', 'dev')}
                            ],
                            'Value': duration_ms,
                            'Unit': 'Milliseconds'
                        },
                        {
                            'MetricName': 'QueryResultCount',
                            'Dimensions': [
                                {'Name': 'TenantId', 'Value': tenant_id},
                                {'Name': 'Environment', 'Value': os.environ.get('ENV', 'dev')}
                            ],
                            'Value': record_count,
                            'Unit': 'Count'
                        }
                    ]
                )
            except Exception as e:
                # Don't fail the query if metrics publishing fails
                logger.warning(f"Failed to publish CloudWatch metrics: {str(e)}")
        except Exception as e:
            logger.error(f"RDS Query error: {str(e)}")
            return {"error": f"Database query error: {str(e)}", "statusCode": 500}
        
        # Process results
        results = []
        for record in response.get('records', []):
            chunk_text = record[0]['stringValue']
            metadata_str = record[1]['stringValue']
            score = float(record[2]['doubleValue'])
            
            try:
                metadata = json.loads(metadata_str) if metadata_str else {}
            except json.JSONDecodeError:
                metadata = {}
                
            results.append({
                'content': {'text': chunk_text},
                'metadata': metadata,
                'score': score
            })
            
        if not results:
            return {"answer": "I don't know. I couldn't find any relevant information in the knowledge base."}
            
        # Extract relevant content
        relevant_content = []
        for result in results:
            content = result.get('content', {}).get('text', '')
            score = result.get('score', 0)
            
            if score >= 0.2:  # Include moderate-confidence results
                relevant_content.append(content)
        
        if not relevant_content and results:
            # Fallback to top result snippet if available
            top = results[0].get('content', {}).get('text', '')
            if top:
                relevant_content.append(top)
        if not relevant_content:
            return {"answer": "I don't know. The information I found doesn't seem relevant to your question."}
        
        # Format the response with context
        context = "\n\n".join(relevant_content[:3])  # Use top 3 results
        
        # Generate answer using the configured model
        model_arn = os.environ.get('CLAUDE_MODEL_ARN', 'anthropic.claude-3-sonnet-20240229-v1:0')
        
        answer_prompt = f"""Based on the following information from the knowledge base, please answer the user's question. If the information doesn't contain a clear answer, respond with "I don't know."

Context from knowledge base:
{context}

User question: {sanitized_query}

Please provide a helpful and accurate answer based only on the provided context. If you cannot answer based on the context, say "I don't know.":"""
        
        # Use Claude to generate a natural response
        claude_response = boto3.client('bedrock-runtime', region_name=os.environ.get('REGION')).invoke_model(
            modelId=model_arn,
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 500,
                "messages": [
                    {
                        "role": "user",
                        "content": answer_prompt
                    }
                ]
            })
        )
        
        claude_result = json.loads(claude_response['body'].read())
        answer = claude_result['content'][0]['text']
        
        logger.info(f"Knowledge base query successful for tenant {tenant_id}, customer {customer_id}")
        
        return {
            "answer": answer,
            "sources_count": len(results),
            "confidence_scores": [r.get('score', 0) for r in results[:3]]
        }
        
    except Exception as e:
        logger.error(f"Error querying knowledge base: {str(e)}")
        return {"error": f"Failed to query knowledge base: {str(e)}", "statusCode": 500}

def generate_embedding(text: str) -> dict:
    """Generate embeddings using Bedrock Titan Embeddings model"""
    try:
        response = bedrock_runtime.invoke_model(
            modelId="amazon.titan-embed-text-v1",
            body=json.dumps({"inputText": text})
        )
        embedding_response = json.loads(response["body"].read())
        embedding = embedding_response.get("embedding")
        return {"embedding": embedding}
    except Exception as e:
        logger.error(f"Error generating embedding: {str(e)}")
        return {"error": f"Failed to generate embedding: {str(e)}"}

def get_ingestion_status(tenant_id: str, ingestion_job_id: str) -> dict:
    """Get knowledge base ingestion job status"""
    try:
        validation = validate_input(tenant_id)
        if not validation["valid"]:
            return {"error": validation["error"], "statusCode": 400}

        kb_id = os.environ.get(f'KB_ID_{tenant_id.upper()}')
        ds_id = os.environ.get(f'DS_ID_{tenant_id.upper()}')
        if not kb_id or not ds_id:
            return {"error": "Knowledge base not configured for tenant", "statusCode": 404}

        resp = bedrock_client.get_ingestion_job(
            knowledgeBaseId=kb_id,
            dataSourceId=ds_id,
            ingestionJobId=ingestion_job_id
        )
        job = resp.get('ingestionJob', {})
        return {
            "status": job.get('status'),
            "startedAt": job.get('startedAt'),
            "updatedAt": job.get('updatedAt'),
            "errors": job.get('failureReasons')
        }
    except Exception as e:
        logger.error(f"Error getting ingestion status: {str(e)}")
        return {"error": f"Failed to get ingestion status: {str(e)}", "statusCode": 500}

def handler(event, context):
    """Main Lambda handler"""
    logger.info(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Extract request details - handles both REST API and HTTP API formats
        http_method, path, body = extract_request_details_from_rest_event(event)
        logger.info(f"Parsed request: method={http_method}, path={path}, body keys={list(body.keys()) if body else 'empty'}")
        
        # For REST API, we need to handle the resource path differently
        # Convert resource paths to the HTTP API format for compatibility
        if event.get('resource'):
            # Map REST API resources to our HTTP API paths
            path_mapping = {
                '/chat': '/chat',
                '/kb/query': '/kb/query',
                '/kb/upload-url': '/kb/upload-url',
                '/kb/upload-form': '/kb/upload-form',
                '/kb/sync': '/kb/sync',
                '/kb/ingestion-status': '/kb/ingestion-status'
            }
            resource = event.get('resource', '')
            if resource in path_mapping:
                path = path_mapping[resource]
                logger.info(f"Mapped resource {resource} to path {path}")
        
        # Route based on path and method
        if path == '/kb/upload-url' and http_method == 'POST':
            # Generate presigned URL for document upload
            tenant_id = body.get('tenant_id')
            filename = body.get('filename')
            
            if not tenant_id or not filename:
                return _response(400, {"error": "tenant_id and filename are required"})
            
            result = generate_presigned_url(tenant_id, filename)
            status_code = result.pop('statusCode', 200)
            return _response(status_code, result)
        elif path == '/kb/upload-form' and http_method == 'POST':
            # Generate presigned POST form
            tenant_id = body.get('tenant_id')
            filename = body.get('filename')
            content_type = body.get('content_type', 'application/pdf')

            if not tenant_id or not filename:
                return _response(400, {"error": "tenant_id and filename are required"})

            result = generate_presigned_post(tenant_id, filename, content_type)
            status_code = result.pop('statusCode', 200)
            return _response(status_code, result)
        
        elif path == '/kb/sync' and http_method == 'POST':
            # Trigger knowledge base sync
            tenant_id = body.get('tenant_id')
            document_key = body.get('document_key')
            
            if not tenant_id or not document_key:
                return _response(400, {"error": "tenant_id and document_key are required"})
            
            result = trigger_knowledge_sync(tenant_id, document_key)
            status_code = result.pop('statusCode', 200)
            return _response(status_code, result)
        
        elif path == '/kb/query' and http_method == 'POST':
            # Query knowledge base
            tenant_id = body.get('tenant_id')
            customer_id = body.get('customer_id')
            query = body.get('query')
            
            if not tenant_id or not customer_id or not query:
                return _response(400, {"error": "tenant_id, customer_id, and query are required"})
            
            result = query_knowledge_base(tenant_id, customer_id, query)
            status_code = result.pop('statusCode', 200)
            return _response(status_code, result)
        elif path == '/kb/ingestion-status' and http_method == 'POST':
            tenant_id = body.get('tenant_id')
            job_id = body.get('ingestion_job_id')
            if not tenant_id or not job_id:
                return _response(400, {"error": "tenant_id and ingestion_job_id are required"})
            result = get_ingestion_status(tenant_id, job_id)
            status_code = result.pop('statusCode', 200)
            return _response(status_code, result)
        
        else:
            return _response(404, {"error": "Endpoint not found"})
    
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return _response(500, {"error": "Internal server error"})

def _response(status_code: int, body: dict) -> dict:
    """Generate HTTP response"""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        },
        "body": json.dumps(body)
    }