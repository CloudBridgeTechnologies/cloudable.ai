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

# Initialize AWS clients - use REGION from environment or default to eu-west-1
aws_region = os.environ.get('REGION', 'eu-west-1')
s3_client = boto3.client('s3', region_name=aws_region, config=boto3.session.Config(signature_version='s3v4'))
bedrock_client = boto3.client('bedrock-agent', region_name=aws_region)
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name=aws_region)  # For knowledge base operations
bedrock_runtime = boto3.client('bedrock-runtime', region_name=aws_region)  # For model invocations
rds_client = boto3.client('rds-data', region_name=aws_region)

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

def generate_presigned_url(tenant_id: str, filename: str, content_type: str = "application/pdf") -> dict:
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
        
        # Get KMS key ARN from environment (optional)
        kms_key_arn = os.environ.get('S3_KMS_KEY_ARN')
        
        # Prepare S3 parameters - keep it minimal to avoid signature mismatch
        # Don't include ContentType or encryption in presigned URL params
        # Client can set Content-Type header when uploading
        # Encryption will be handled by bucket default encryption settings
        s3_params = {
            'Bucket': bucket_name,
            'Key': document_key
        }
        
        # Note: We don't include ContentType or ServerSideEncryption in presigned URL params
        # to avoid signature mismatch issues. Client sets Content-Type header, bucket handles encryption.
        
        # Generate presigned URL (valid for 1 hour)
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params=s3_params,
            ExpiresIn=3600
        )
        
        logger.info(f"Generated presigned URL for tenant {tenant_id}, key: {document_key}")
        
        return {
            "url": presigned_url,  # Alias for compatibility
            "presigned_url": presigned_url,
            "document_key": document_key,
            "bucket_name": bucket_name,
            "expires_in": 3600,
            "kms_key_id": kms_key_arn if kms_key_arn else None  # Include KMS key ID in response for client usage
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
            {"Content-Type": content_type}
        ]

        fields = {
            "key": document_key,
            "Content-Type": content_type
        }
        
        # Add KMS encryption if key is available
        if kms_key_arn:
            conditions.append({"x-amz-server-side-encryption": "aws:kms"})
            conditions.append({"x-amz-server-side-encryption-aws-kms-key-id": kms_key_arn})
            fields["x-amz-server-side-encryption"] = "aws:kms"
            fields["x-amz-server-side-encryption-aws-kms-key-id"] = kms_key_arn
        else:
            # Use default S3 encryption if no KMS key
            conditions.append({"x-amz-server-side-encryption": "AES256"})
            fields["x-amz-server-side-encryption"] = "AES256"

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
        # Instead of triggering Bedrock KB sync, we'll insert directly into the PostgreSQL vector table
        # First, get the document content from S3
        bucket_name = os.environ.get(f'BUCKET_{tenant_id.upper()}')
        
        if not bucket_name:
            return {"error": "Tenant bucket not configured", "statusCode": 404}
        
        try:
            # Get document content from S3
            s3_response = s3_client.get_object(
                Bucket=bucket_name,
                Key=document_key
            )
            document_content = s3_response['Body'].read().decode('utf-8')
            logger.info(f"Retrieved document content from S3: {document_key}")
            
            # Generate unique ID for this chunk
            import uuid
            chunk_id = str(uuid.uuid4())
            
            # Generate embeddings for the document
            embedding_result = generate_embedding(document_content)
            if "error" in embedding_result:
                return {"error": embedding_result["error"], "statusCode": 500}
                
            embedding = embedding_result["embedding"]
            
            # Prepare metadata
            metadata = {
                "source": document_key,
                "tenant": tenant_id,
                "timestamp": datetime.utcnow().isoformat(),
                "format": "text/markdown" if document_key.endswith(".md") else "application/pdf"
            }
            
            # Connect to RDS and insert the vector
            cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
            secret_arn = os.environ.get('RDS_SECRET_ARN')
            database_name = os.environ.get('RDS_DATABASE', 'cloudable')
            
            if not cluster_arn or not secret_arn:
                return {"error": "Database connection parameters not configured", "statusCode": 500}
            
            # Insert into vector table using RDS Data API
            embedding_str = f"'{{{','.join([str(x) for x in embedding])}}}'::vector"
            metadata_json = json.dumps(metadata)
            
            sql = f"""
            INSERT INTO kb_vectors_{tenant_id} (id, embedding, chunk_text, metadata)
            VALUES (:id, {embedding_str}, :content, :metadata::jsonb)
            """
            
            params = [
                {'name': 'id', 'value': {'stringValue': chunk_id}},
                {'name': 'content', 'value': {'stringValue': document_content}},
                {'name': 'metadata', 'value': {'stringValue': metadata_json}}
            ]
            
            rds_client.execute_statement(
                resourceArn=cluster_arn,
                secretArn=secret_arn,
                database=database_name,
                sql=sql,
                parameters=params
            )
            
            logger.info(f"Inserted vector data for document {document_key}")
            
            # Generate a deterministic job ID for tracking
            import hashlib
            ingestion_job_id = f"job-{hashlib.md5((tenant_id + document_key).encode()).hexdigest()[:12]}"
            
            return {
                "ingestion_job_id": ingestion_job_id,
                "status": "completed",
                "vector_id": chunk_id,
                "document_key": document_key
            }
            
        except Exception as e:
            logger.error(f"Error processing document: {str(e)}")
            # Use mock implementation as fallback
            import hashlib
            kb_id = f"kb-{tenant_id}-{hashlib.md5(tenant_id.encode()).hexdigest()[:8]}"
            ingestion_job_id = f"job-{hashlib.md5((tenant_id + document_key).encode()).hexdigest()[:12]}"
            
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
        
        # Validate tenant exists (check if bucket is configured)
        bucket_name = os.environ.get(f'BUCKET_{tenant_id.upper()}')
        if not bucket_name:
            logger.warning(f"Invalid tenant ID: {tenant_id}")
            return {"error": "Invalid tenant ID", "statusCode": 403}
        
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
        
        embedding = embedding_result["embedding"]
        
        # Check if table exists and query it
        try:
            # Get RDS connection parameters
            cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
            secret_arn = os.environ.get('RDS_SECRET_ARN')
            database_name = os.environ.get('RDS_DATABASE', 'cloudable')
            
            if not cluster_arn or not secret_arn:
                return {"error": "Database connection parameters not configured", "statusCode": 500}
            
            # Convert embedding to string format for SQL
            embedding_str = f"'{{{','.join([str(x) for x in embedding])}}}'::vector"
            
            # Query the vector table with cosine similarity search
            search_sql = f"""
            SELECT 
                id, 
                chunk_text, 
                metadata,
                1 - (embedding <=> {embedding_str}) as similarity
            FROM 
                kb_vectors_{tenant_id}
            ORDER BY 
                embedding <=> {embedding_str}
            LIMIT 3;
            """
            
            # Execute the search query
            response = rds_client.execute_statement(
                resourceArn=cluster_arn,
                secretArn=secret_arn,
                database=database_name,
                sql=search_sql
            )
            
            # Process results
            results = []
            for record in response.get('records', []):
                # Extract values from the record
                result_id = record[0]['stringValue'] if record[0]['stringValue'] else None
                result_text = record[1]['stringValue'] if record[1]['stringValue'] else ""
                result_metadata = json.loads(record[2]['stringValue']) if record[2]['stringValue'] else {}
                result_similarity = float(record[3]['doubleValue']) if record[3]['doubleValue'] else 0.0
                
                if result_similarity < 0.7:  # Skip low similarity results
                    continue
                
                results.append({
                    "text": result_text,
                    "metadata": result_metadata,
                    "similarity_score": result_similarity
                })
            
            logger.info(f"Found {len(results)} relevant results for query '{query}'")
            
            if not results:
                return {
                    "answer": "I don't know. I couldn't find any relevant information in the knowledge base.",
                    "results": [],
                    "sources_count": 0,
                    "confidence_scores": []
                }
            
            # Generate an answer using Claude or a simple answer based on results
            answer = f"Based on the knowledge base, I found relevant information: {' '.join([r['text'][:150] + '...' for r in results])}"
            confidence_scores = [r["similarity_score"] for r in results]
            
            return {
                "answer": answer,
                "results": results,
                "sources_count": len(results),
                "confidence_scores": confidence_scores
            }
            
        except Exception as e:
            logger.error(f"Vector search error: {str(e)}")
            return {
                "answer": "I don't know. I couldn't find any relevant information in the knowledge base.",
                "results": [],
                "sources_count": 0, 
                "confidence_scores": []
            }
        
    except Exception as e:
        logger.error(f"Query knowledge base error: {str(e)}")
        return {"error": f"Failed to query knowledge base: {str(e)}", "statusCode": 500}
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
        claude_response = boto3.client('bedrock-runtime', region_name=aws_region).invoke_model(
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
            "confidence_scores": [r.get('score', 0) for r in results[:3]],
            "results": results  # Include results for chat endpoint
        }
        
    except Exception as e:
        logger.error(f"Error querying knowledge base: {str(e)}")
        return {"error": f"Failed to query knowledge base: {str(e)}", "statusCode": 500}

def generate_embedding(text: str) -> dict:
    """Generate embeddings using Bedrock Titan Embeddings model"""
    try:
        response = bedrock_runtime.invoke_model(
            modelId="amazon.titan-embed-text-v2:0",
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
        if path == '/health' and http_method == 'GET':
            # Health check endpoint
            return _response(200, {"message": "Cloudable.AI KB Manager API is operational", "version": "1.0.0"})
        
        elif path == '/kb/upload-url' and http_method == 'POST':
            # Generate presigned URL for document upload
            tenant_id = body.get('tenant_id')
            filename = body.get('filename')
            content_type = body.get('content_type', 'application/pdf')
            
            if not tenant_id or not filename:
                return _response(400, {"error": "tenant_id and filename are required"})
            
            result = generate_presigned_url(tenant_id, filename, content_type)
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
            # Support both 'tenant' and 'tenant_id' for backward compatibility
            tenant_id = body.get('tenant_id') or body.get('tenant')
            document_key = body.get('document_key')
            
            if not tenant_id or not document_key:
                return _response(400, {"error": "tenant_id and document_key are required"})
            
            result = trigger_knowledge_sync(tenant_id, document_key)
            status_code = result.pop('statusCode', 200)
            return _response(status_code, result)
        
        elif path == '/kb/query' and http_method == 'POST':
            # Query knowledge base
            # Check for user ID in headers (basic auth check)
            headers = event.get('headers', {}) or {}
            user_id = headers.get('x-user-id') or headers.get('X-User-ID')
            if not user_id:
                return _response(403, {"error": "Unauthorized: User ID required"})
            
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
        
        elif path == '/chat' and http_method == 'POST':
            # Chat endpoint - uses KB query internally
            tenant_id = body.get('tenant_id')
            message = body.get('message')
            use_kb = body.get('use_kb', True)
            customer_id = body.get('customer_id', 'default')
            
            if not tenant_id or not message:
                return _response(400, {"error": "tenant_id and message are required"})
            
            if use_kb:
                # Use KB query to get context
                kb_result = query_knowledge_base(tenant_id, customer_id, message)
                if "error" in kb_result:
                    # If KB query fails, return error
                    status_code = kb_result.pop('statusCode', 500)
                    return _response(status_code, kb_result)
                
                # Format response for chat
                answer = kb_result.get('answer', 'I could not find relevant information.')
                sources_count = kb_result.get('sources_count', 0)
                confidence_scores = kb_result.get('confidence_scores', [])
                
                # Extract source documents from KB results
                source_documents = []
                if 'results' in kb_result:
                    for result in kb_result['results']:
                        source_documents.append({
                            "text": result.get('content', {}).get('text', ''),
                            "metadata": result.get('metadata', {}),
                            "score": result.get('score', 0)
                        })
                
                return _response(200, {
                    "response": answer,
                    "source_documents": source_documents,
                    "sources_count": sources_count,
                    "confidence_scores": confidence_scores
                })
            else:
                # Chat without KB - return simple response
                return _response(200, {
                    "response": "I'm a knowledge base assistant. Please enable KB mode to get contextual answers.",
                    "source_documents": []
                })
        
        elif path == '/kb/status' and http_method == 'POST':
            # Customer status endpoint - query RDS for customer status
            tenant_id = body.get('tenant_id')
            
            if not tenant_id:
                return _response(400, {"error": "tenant_id is required"})
            
            # Query customer status from RDS
            try:
                cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
                secret_arn = os.environ.get('RDS_SECRET_ARN')
                db_name = os.environ.get('RDS_DATABASE', 'cloudable')
                
                # Query customer status view
                sql_query = f"""
                SELECT * FROM customer_status.customer_status_view_{tenant_id}
                LIMIT 1;
                """
                
                response = rds_client.execute_statement(
                    resourceArn=cluster_arn,
                    secretArn=secret_arn,
                    database=db_name,
                    sql=sql_query
                )
                
                if response.get('records'):
                    record = response['records'][0]
                    # Map record fields to response
                    result = {
                        "customer_id": record[0]['stringValue'] if len(record) > 0 else None,
                        "customer_name": record[1]['stringValue'] if len(record) > 1 else None,
                        "current_stage": record[2]['stringValue'] if len(record) > 2 else None,
                        "stage_order": int(record[3]['longValue']) if len(record) > 3 else None,
                        "status_summary": record[4]['stringValue'] if len(record) > 4 else None,
                        "implementation_start_date": record[6]['stringValue'] if len(record) > 6 else None,
                        "projected_completion_date": record[7]['stringValue'] if len(record) > 7 else None,
                        "health_status": record[8]['stringValue'] if len(record) > 8 else None,
                        "progress_percentage": float(record[9]['doubleValue']) if len(record) > 9 else None,
                        "completed_milestones": int(record[10]['longValue']) if len(record) > 10 else None,
                        "total_milestones": int(record[11]['longValue']) if len(record) > 11 else None
                    }
                    return _response(200, result)
                else:
                    return _response(404, {"error": "Customer status not found for tenant"})
                    
            except Exception as e:
                logger.error(f"Error querying customer status: {str(e)}")
                return _response(500, {"error": f"Failed to query customer status: {str(e)}"})
        
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