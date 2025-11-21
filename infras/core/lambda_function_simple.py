import json
import os
import boto3
import logging
import uuid
import time
from botocore.exceptions import ClientError
from typing import Dict, Any, Optional, List

# Import Langfuse integration
try:
    import langfuse_integration
    LANGFUSE_ENABLED = True
    logger = logging.getLogger()
    logger.info("Langfuse integration loaded successfully")
except ImportError:
    LANGFUSE_ENABLED = False
    logger = logging.getLogger()
    logger.warning("Langfuse integration not found, running without LLM observability")

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Import RBAC module
try:
    import tenant_rbac
    RBAC_ENABLED = True
    logger.info("RBAC module loaded successfully")
    
    # Import and run seed script for testing (in production, this would be done elsewhere)
    try:
        import seed_rbac_roles
        logger.info("Seeding RBAC roles for testing...")
        seed_rbac_roles.main()
        logger.info("RBAC roles seeded successfully")
    except ImportError:
        logger.warning("RBAC seed script not found, skipping role initialization")
    except Exception as e:
        logger.error(f"Error seeding RBAC roles: {e}")
except ImportError:
    RBAC_ENABLED = False
    logger.warning("RBAC module not found, running with basic tenant validation only")

# Import metrics module
try:
    import tenant_metrics
    METRICS_ENABLED = True
    logger.info("Tenant metrics module loaded successfully")
except ImportError:
    METRICS_ENABLED = False
    logger.warning("Tenant metrics module not found, running without usage tracking")

# Initialize AWS clients
aws_region = os.environ.get('AWS_REGION', 'eu-west-1')
s3_client = boto3.client('s3', region_name=aws_region)

# Import customer status handler
try:
    from customer_status_handler import handle_customer_status_request
    CUSTOMER_STATUS_ENABLED = True
    logger.info("Customer status handler loaded successfully")
except ImportError:
    CUSTOMER_STATUS_ENABLED = False
    logger.warning("Customer status handler not found, endpoint will not be available")

def track_request_metrics(tenant_id, user_id, api_name, status_code, start_time, event, response_body=None):
    """Track API request metrics if metrics module is enabled"""
    if not METRICS_ENABLED:
        return
        
    try:
        # Calculate execution time
        execution_time_ms = int((time.time() - start_time) * 1000)
        
        # Get request size (approximate)
        request_size_bytes = len(json.dumps(event)) if event else 0
        
        # Get response size (approximate)
        response_size_bytes = len(response_body) if response_body else 0
        
        # Determine user ID if not provided
        if not user_id:
            # Try to extract from headers or body
            headers = event.get('headers', {}) or {}
            if 'x-user-id' in headers:
                user_id = headers['x-user-id']
            else:
                # Check body
                body = {}
                if 'body' in event:
                    if isinstance(event['body'], str):
                        try:
                            body = json.loads(event['body'])
                        except json.JSONDecodeError:
                            pass
                    elif isinstance(event['body'], dict):
                        body = event['body']
                
                user_id = body.get('user_id', 'anonymous')
        
        # Track the API call
        metric_id = tenant_metrics.track_api_call(
            tenant_id=tenant_id,
            user_id=user_id,
            api_name=api_name,
            status_code=status_code,
            execution_time_ms=execution_time_ms,
            request_size_bytes=request_size_bytes,
            response_size_bytes=response_size_bytes
        )
        
        logger.info(f"Tracked API metrics: {api_name} for tenant {tenant_id}, metric_id: {metric_id}")
    except Exception as e:
        # Don't fail the request if metrics tracking fails
        logger.error(f"Error tracking metrics: {str(e)}")

def generate_presigned_url(tenant, filename, content_type):
    """Generate a presigned URL for S3 upload"""
    try:
        # Get AWS region from environment or default to eu-west-1
        aws_region = os.environ.get('AWS_REGION', 'eu-west-1')
        # Format the S3 bucket name based on tenant and region
        bucket_name = f"cloudable-kb-dev-{aws_region}-{tenant}-20251114095518"
        
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

def validate_tenant_access(tenant, context=None, event=None, required_permission=None):
    """
    Validates that the tenant is valid and the request has appropriate permissions
    
    Args:
        tenant (str): Tenant identifier
        context (obj): Lambda context object
        event (dict): API Gateway event
        required_permission (str): Permission required for this operation
    """
    # Basic tenant validation (always run)
    valid_tenants = ["acme", "globex", "initech", "umbrella"]
    
    if not tenant or tenant.lower() not in valid_tenants:
        logger.warning(f"Unauthorized tenant access attempt: {tenant}")
        return False
        
    # If RBAC is enabled and we have an event with a required permission, perform permission check
    if RBAC_ENABLED and event and required_permission:
        # Extract user ID from event (headers, query params, or body)
        user_id = None
        
        # Check headers
        if 'headers' in event and event['headers']:
            user_id = event['headers'].get('x-user-id')
        
        # Check query parameters
        if not user_id and 'queryStringParameters' in event and event['queryStringParameters']:
            user_id = event['queryStringParameters'].get('user')
        
        # Check body
        if not user_id and 'body' in event:
            body = event.get('body', {})
            if isinstance(body, str):
                try:
                    body = json.loads(body)
                    user_id = body.get('user_id')
                except json.JSONDecodeError:
                    pass
            elif isinstance(body, dict):
                user_id = body.get('user_id')
        
        # Fall back to a default user ID for testing
        if not user_id:
            user_id = "default-user"
            
        logger.info(f"Checking permission: {required_permission} for user: {user_id} in tenant: {tenant}")
        
        # Check if the user has the required permission
        has_permission = tenant_rbac.check_permission(tenant, user_id, required_permission)
        
        if not has_permission:
            logger.warning(f"Permission denied: User {user_id} lacks {required_permission} in tenant {tenant}")
            return False
            
        logger.info(f"Permission granted: User {user_id} has {required_permission} in tenant {tenant}")
    
    return True

def handler(event, context):
    """Lambda handler function"""
    request_id = context.aws_request_id if context else "unknown"
    start_time = time.time()
    
    try:
        logger.info(f"[RequestId: {request_id}] Received event: {json.dumps(event)}")
        
        # Get the HTTP method and path
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        # For API Gateway HTTP API integrations
        if 'requestContext' in event and 'http' in event['requestContext']:
            http_method = event['requestContext']['http']['method']
            path = event['requestContext']['http']['path']
        
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
                
        # Extract tenant from request headers or body
        tenant = None
        if 'tenant' in body:
            tenant = body.get('tenant')
            logger.info(f"Tenant from request body: {tenant}")
        elif 'headers' in event and event['headers'] and 'x-tenant-id' in event['headers']:
            # In production, tenants should be identified by secure headers or tokens
            tenant = event['headers']['x-tenant-id']
            logger.info(f"Tenant from request header: {tenant}")
        
        logger.info(f"HTTP Method: {http_method}, Path: {path}, Body: {json.dumps(body)}")
        
        # Process health check
        if http_method == 'GET' and path.endswith('/health'):
            response_body = json.dumps({"message": "Cloudable.AI KB Manager API is operational"})
            status_code = 200
            track_request_metrics(None, None, "health_check", status_code, start_time, event, response_body)
            return {
                'statusCode': status_code,
                'headers': {'Content-Type': 'application/json'},
                'body': response_body
            }
        
        # Handle upload URL generation
        if http_method == 'POST' and path.endswith('/upload-url'):
            tenant = body.get('tenant', '')
            filename = body.get('filename', '')
            content_type = body.get('content_type', 'application/octet-stream')
            
            logger.info(f"Upload URL request: tenant={tenant}, filename={filename}, content_type={content_type}")
            
            if not tenant or not filename:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and filename"})
                }
                
            # Validate tenant access permissions - ensure proper tenant isolation and check user permissions
            if not validate_tenant_access(tenant, context, event, "doc:write"):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Unauthorized access. Invalid tenant or insufficient permissions."})
                }
            
            presigned_data = generate_presigned_url(tenant, filename, content_type)
            if not presigned_data:
                return {
                    'statusCode': 500,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Failed to generate presigned URL"})
                }
            
            # Prepare response
            response_body = json.dumps(presigned_data)
            status_code = 200
            
            # Track metrics
            user_id = event.get('headers', {}).get('x-user-id') if event.get('headers') else None
            track_request_metrics(
                tenant_id=tenant,
                user_id=user_id,
                api_name="upload_url",
                status_code=status_code,
                start_time=start_time,
                event=event,
                response_body=response_body
            )
            
            # Track document metrics if metrics are enabled
            if METRICS_ENABLED:
                try:
                    tenant_metrics.track_document_upload(
                        tenant_id=tenant,
                        user_id=user_id or 'anonymous',
                        document_key=presigned_data.get('key', ''),
                        file_size_bytes=0,  # We don't know the size yet
                        file_type=content_type
                    )
                except Exception as e:
                    logger.error(f"Error tracking document metrics: {str(e)}")
            
            return {
                'statusCode': status_code,
                'headers': {'Content-Type': 'application/json'},
                'body': response_body
            }
        
        # Handle KB sync endpoint
        if http_method == 'POST' and path.endswith('/kb/sync'):
            tenant = body.get('tenant', '')
            document_key = body.get('document_key', '')
            
            logger.info(f"KB sync request: tenant={tenant}, document_key={document_key}")
            
            if not tenant or not document_key:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and document_key"})
                }
                
            # Validate tenant access permissions - ensure proper tenant isolation and check user permissions
            if not validate_tenant_access(tenant, context, event, "kb:write"):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Unauthorized access. Invalid tenant or insufficient permissions."})
                }
                
            # Ensure the document belongs to the tenant's bucket
            # Check if the document belongs to another tenant
            if (document_key.startswith("documents/") and 
                ("/" in document_key[len("documents/"):]) and 
                any(other_tenant in document_key for other_tenant in ["acme", "globex", "initech", "umbrella"] if other_tenant != tenant)):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Unauthorized access. Document does not belong to this tenant."})
                }
            
            # Check if the document has already been processed before
            # In a real implementation, we would check a database table for the document's status
            # For this demo implementation, we'll simulate completion based on certain patterns
            
            # Generate a deterministic hash from the document key to simulate consistent behavior
            import hashlib
            doc_hash = int(hashlib.md5(document_key.encode()).hexdigest(), 16) % 100
            
            # Documents with hash < 80 are considered "completed" (80% of documents)
            # Documents with hash >= 80 are still "processing" (20% of documents)
            is_completed = doc_hash < 80
            
            # Prepare response
            response_data = {
                "message": "Document sync completed" if is_completed else "Document sync initiated",
                "tenant": tenant,
                "document_key": document_key,
                "status": "completed" if is_completed else "processing",
                "completion_time": time.strftime("%Y-%m-%d %H:%M:%S") if is_completed else None
            }
            response_body = json.dumps(response_data)
            status_code = 200
            
            # Track metrics
            user_id = event.get('headers', {}).get('x-user-id') if event.get('headers') else None
            track_request_metrics(
                tenant_id=tenant,
                user_id=user_id,
                api_name="kb_sync",
                status_code=status_code,
                start_time=start_time,
                event=event,
                response_body=response_body
            )
            
            # Track KB sync metrics if metrics are enabled
            if METRICS_ENABLED:
                try:
                    tenant_metrics.track_kb_sync(
                        tenant_id=tenant,
                        user_id=user_id or 'anonymous',
                        document_key=document_key,
                        execution_time_ms=int((time.time() - start_time) * 1000)
                    )
                except Exception as e:
                    logger.error(f"Error tracking KB sync metrics: {str(e)}")
            
            # Mock successful response
            return {
                'statusCode': status_code,
                'headers': {'Content-Type': 'application/json'},
                'body': response_body
            }
        
        # Handle KB query endpoint
        if http_method == 'POST' and path.endswith('/kb/query'):
            tenant = body.get('tenant', '')
            query = body.get('query', '')
            max_results = int(body.get('max_results', 3))
            
            logger.info(f"KB query request: tenant={tenant}, query={query}, max_results={max_results}")
            
            if not tenant or not query:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and query"})
                }
                
            # Validate tenant access permissions - ensure proper tenant isolation and check user permissions
            if not validate_tenant_access(tenant, context, event, "kb:read"):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Unauthorized access. Invalid tenant or insufficient permissions."})
                }
                
            # In a real implementation, we would also validate that:
            # 1. The authenticated user has access to the specified tenant
            # 2. Knowledge base table name matches the tenant ID
            # 3. Any embedding API calls are scoped to the tenant's data
            
            # Implement stronger tenant isolation:
            # 1. Check if the query references another tenant name and reject if it does
            # 2. Only return information specific to the requesting tenant
            # 3. Filter out cross-tenant references in results
            
            other_tenants = ["acme", "globex", "initech", "umbrella"]
            other_tenants.remove(tenant.lower())
            
            # Check if the query explicitly asks about other tenants
            cross_tenant_query = False
            for other_tenant in other_tenants:
                if other_tenant in query.lower():
                    # We detected a query asking about another tenant
                    cross_tenant_query = True
                    logger.warning(f"Cross-tenant query detected: tenant {tenant} asking about {other_tenant}")
                    break
            
            # Mock response based on query - but only return tenant-specific information
            results = []
            
            if cross_tenant_query:
                # Return a privacy-preserving message rather than data from another tenant
                results.append({
                    "text": f"Information about other organizations is not available. This knowledge base only contains information about {tenant}.",
                    "metadata": {"source": f"{tenant.capitalize()} Privacy Policy", "section": "Data Access", "kb_id": f"KB-{tenant.upper()}-PRIVACY"},
                    "score": 0.99
                })
            elif tenant == 'acme':
                if 'status' in query.lower() or 'implementation' in query.lower():
                    results.append({
                        "text": "ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025.",
                        "metadata": {"source": "Customer Journey Report - ACME Manufacturing", "section": "Current Status", "kb_id": "KB-ACME-2025-11-01"},
                        "score": 0.95
                    })
                elif 'metrics' in query.lower() or 'success' in query.lower():
                    results.append({
                        "text": "Success metrics include 30% reduction in order processing time (currently at 18%), 25% improvement in inventory accuracy (currently at 20%), and 15% increase in customer satisfaction (currently at 8%).",
                        "metadata": {"source": "ACME Digital Transformation Progress Report", "section": "Success Metrics", "kb_id": "KB-ACME-2025-11-05"},
                        "score": 0.91
                    })
                elif 'next' in query.lower() or 'step' in query.lower():
                    results.append({
                        "text": "Next steps for ACME: Complete supply chain module by November 30, Schedule field service training for December, Prepare final phase deployment plan by November 25.",
                        "metadata": {"source": "ACME Implementation Roadmap", "section": "Next Steps", "kb_id": "KB-ACME-2025-11-10"},
                        "score": 0.89
                    })
            elif tenant == 'globex':
                if 'status' in query.lower() or 'implementation' in query.lower():
                    results.append({
                        "text": "Globex Industries is currently in the Onboarding stage (phase 1 of 4), with implementation having started on October 2, 2025 and expected completion by June 15, 2026.",
                        "metadata": {"source": "Globex Industries Onboarding Report", "section": "Current Status", "kb_id": "KB-GLOBEX-2025-11-08"},
                        "score": 0.93
                    })
                elif 'stakeholder' in query.lower():
                    results.append({
                        "text": "Key stakeholders at Globex include Thomas Wong (CTO), Aisha Patel (CDO), Robert Martinez (Customer Experience), and Jennifer Lee (Compliance Director).",
                        "metadata": {"source": "Globex Project Charter", "section": "Key Stakeholders", "kb_id": "KB-GLOBEX-2025-11-01"},
                        "score": 0.97
                    })
            
            # Add generic fallback result if no specific matches
            if not results:
                results.append({
                    "text": f"Information about {tenant} found in customer journey documentation.",
                    "metadata": {"source": f"{tenant.capitalize()} Customer Knowledge Base", "kb_id": f"KB-{tenant.upper()}-GENERAL"},
                    "score": 0.75
                })
            
            # Prepare response
            response_data = {
                "results": results,
                "query": query
            }
            response_body = json.dumps(response_data)
            status_code = 200
            execution_time_ms = int((time.time() - start_time) * 1000)
            
            # Track metrics
            user_id = event.get('headers', {}).get('x-user-id') if event.get('headers') else None
            track_request_metrics(
                tenant_id=tenant,
                user_id=user_id,
                api_name="kb_query",
                status_code=status_code,
                start_time=start_time,
                event=event,
                response_body=response_body
            )
            
            # Track KB query metrics if metrics are enabled
            if METRICS_ENABLED:
                try:
                    tenant_metrics.track_kb_query(
                        tenant_id=tenant,
                        user_id=user_id or 'anonymous',
                        query=query,
                        result_count=len(results),
                        execution_time_ms=execution_time_ms
                    )
                except Exception as e:
                    logger.error(f"Error tracking KB query metrics: {str(e)}")
            
            # Track with Langfuse if enabled
            if LANGFUSE_ENABLED:
                try:
                    # Create a trace for this request
                    trace_id = langfuse_integration.create_trace(
                        name="kb_query",
                        tenant_id=tenant,
                        user_id=user_id,
                        metadata={
                            "path": path,
                            "method": http_method,
                            "max_results": max_results,
                            "cross_tenant_query": cross_tenant_query
                        }
                    )
                    
                    # Trace the KB query
                    langfuse_integration.trace_kb_query(
                        trace_id=trace_id,
                        query=query,
                        results=results,
                        tenant_id=tenant,
                        execution_time_ms=execution_time_ms,
                        metadata={
                            "user_id": user_id or "anonymous",
                            "result_count": len(results)
                        }
                    )
                    
                    # Flush observations to Langfuse
                    langfuse_integration.flush_observations()
                    
                    logger.info(f"Traced KB query in Langfuse: {trace_id}")
                except Exception as e:
                    logger.error(f"Error tracking with Langfuse: {str(e)}")
            
            # Return response
            return {
                'statusCode': status_code,
                'headers': {'Content-Type': 'application/json'},
                'body': response_body
            }
        
        # Handle chat endpoint
        if http_method == 'POST' and path.endswith('/chat'):
            tenant = body.get('tenant', '')
            message = body.get('message', '')
            use_kb = body.get('use_kb', True)
            
            logger.info(f"Chat request: tenant={tenant}, message={message}, use_kb={use_kb}")
            
            if not tenant or not message:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and message"})
                }
                
            # Validate tenant access permissions - ensure proper tenant isolation and check user permissions
            if not validate_tenant_access(tenant, context, event, "chat:use"):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Unauthorized access. Invalid tenant or insufficient permissions."})
                }
                
            # In a production system, we would also:
            # 1. Validate that the authenticated user has permissions for this tenant
            # 2. Ensure any LLM context includes only the tenant's own data
            # 3. Apply tenant-specific usage quotas and rate limits
            # 4. Log usage for tenant-specific billing
            
            # Implement stronger tenant isolation for chat:
            # 1. Check if the message references another tenant name and reject if it does
            # 2. Only return information specific to the requesting tenant
            
            other_tenants = ["acme", "globex", "initech", "umbrella"]
            other_tenants.remove(tenant.lower())
            
            # Check if the query explicitly asks about other tenants
            cross_tenant_query = False
            for other_tenant in other_tenants:
                if other_tenant in message.lower():
                    # We detected a query asking about another tenant
                    cross_tenant_query = True
                    logger.warning(f"Cross-tenant chat detected: tenant {tenant} asking about {other_tenant}")
                    break
                    
            # Generate a response based on the tenant, message, and use_kb flag
            response = ""
            source_documents = []
            
            # Check if KB mode is disabled
            if not use_kb:
                # Return a generic response when KB mode is disabled
                response = "I'm a knowledge base assistant. Please enable KB mode to get contextual answers."
                source_documents = []
            elif cross_tenant_query:
                # Return a privacy-preserving message rather than data from another tenant
                response = f"I can only provide information about {tenant}. Information about other organizations is not available in this knowledge base."
                source_documents = [
                    {"text": "Privacy Policy", "metadata": {"source": f"{tenant.capitalize()} Privacy Policy", "section": "Data Access", "kb_id": f"KB-{tenant.upper()}-PRIVACY"}}
                ]
            elif tenant == 'acme':
                if 'status' in message.lower() or 'progress' in message.lower():
                    response = "ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025. They've completed 3 key solutions: Cloud-based ERP system integration, Customer data platform with AI-powered analytics, and Automated order processing workflow."
                    source_documents = [
                        {"text": "Current Status: Implementation", "metadata": {"source": "Customer Journey Report - ACME Manufacturing", "kb_id": "KB-ACME-2025-11-01"}},
                        {"text": "Key Solutions Implemented", "metadata": {"source": "ACME Solution Architecture", "kb_id": "KB-ACME-2025-10-15"}}
                    ]
                elif 'metrics' in message.lower() or 'success' in message.lower():
                    response = "ACME's success metrics include 30% reduction in order processing time (currently at 18%), 25% improvement in inventory accuracy (currently at 20%), and 15% increase in customer satisfaction (currently at 8%)."
                    source_documents = [
                        {"text": "Success Metrics", "metadata": {"source": "ACME Digital Transformation Progress Report", "kb_id": "KB-ACME-2025-11-05"}},
                        {"text": "KPI Dashboard", "metadata": {"source": "ACME Executive Summary", "kb_id": "KB-ACME-2025-11-12"}}
                    ]
                else:
                    response = "ACME Corporation is a manufacturing company with 500 employees currently implementing a digital transformation project. They're in phase 3 of 5, with several key solutions already implemented and others pending completion by December 2025."
                    source_documents = [
                        {"text": "Company Profile", "metadata": {"source": "ACME Corporation Profile", "kb_id": "KB-ACME-2025-08-01"}}
                    ]
            elif tenant == 'globex':
                if 'risk' in message.lower():
                    response = "Implementation risks for Globex include multiple legacy systems requiring complex integration, strict regulatory requirements in financial services, and cross-departmental coordination challenges."
                    source_documents = [
                        {"text": "Risk Factors", "metadata": {"source": "Globex Risk Assessment", "kb_id": "KB-GLOBEX-2025-10-25"}},
                        {"text": "Mitigation Strategies", "metadata": {"source": "Globex Project Plan", "kb_id": "KB-GLOBEX-2025-10-30"}}
                    ]
                elif 'status' in message.lower() or 'progress' in message.lower():
                    response = "Globex Industries is currently in the Onboarding stage (phase 1 of 4), with implementation having started on October 2, 2025 and expected completion by June 15, 2026."
                    source_documents = [
                        {"text": "Current Status: Onboarding", "metadata": {"source": "Globex Industries Onboarding Report", "kb_id": "KB-GLOBEX-2025-11-08"}}
                    ]
                else:
                    response = "Globex Industries is a large financial services provider with 2,000+ employees across multiple regions. They're in the early onboarding phase of their digital transformation, focused on customer experience and operational efficiency."
                    source_documents = [
                        {"text": "Company Overview", "metadata": {"source": "Globex Industries Profile", "kb_id": "KB-GLOBEX-2025-09-15"}}
                    ]
            else:
                response = f"No specific information found for tenant: {tenant}"
                source_documents = []
            
            # Prepare response
            response_data = {
                "response": response,
                "source_documents": source_documents
            }
            response_body = json.dumps(response_data)
            status_code = 200
            execution_time_ms = int((time.time() - start_time) * 1000)
            
            # Estimate token count (very rough estimate)
            message_tokens = len(message.split()) * 1.5  # rough estimate
            response_tokens = len(response.split()) * 1.5  # rough estimate
            total_tokens = int(message_tokens + response_tokens)
            
            # Track metrics
            user_id = event.get('headers', {}).get('x-user-id') if event.get('headers') else None
            track_request_metrics(
                tenant_id=tenant,
                user_id=user_id,
                api_name="chat",
                status_code=status_code,
                start_time=start_time,
                event=event,
                response_body=response_body
            )
            
            # Track chat metrics if metrics are enabled
            if METRICS_ENABLED:
                try:                    
                    tenant_metrics.track_chat_session(
                        tenant_id=tenant,
                        user_id=user_id or 'anonymous',
                        message_count=1,  # Single message in this API call
                        total_tokens=total_tokens,
                        use_kb=use_kb,
                        session_duration_seconds=int((time.time() - start_time))
                    )
                except Exception as e:
                    logger.error(f"Error tracking chat metrics: {str(e)}")
                    
            # Track with Langfuse if enabled
            if LANGFUSE_ENABLED:
                try:
                    # Create a trace for this request
                    trace_id = langfuse_integration.create_trace(
                        name="chat_interaction",
                        tenant_id=tenant,
                        user_id=user_id,
                        metadata={
                            "path": path,
                            "method": http_method,
                            "use_kb": use_kb,
                            "cross_tenant_query": cross_tenant_query
                        }
                    )
                    
                    # Trace the chat interaction
                    langfuse_integration.trace_chat(
                        trace_id=trace_id,
                        message=message,
                        response=response,
                        source_documents=source_documents if use_kb else [],
                        tenant_id=tenant,
                        use_kb=use_kb,
                        execution_time_ms=execution_time_ms,
                        token_count=total_tokens,
                        metadata={
                            "user_id": user_id or "anonymous",
                            "source_count": len(source_documents) if use_kb else 0
                        }
                    )
                    
                    # Flush observations to Langfuse
                    langfuse_integration.flush_observations()
                    
                    logger.info(f"Traced chat interaction in Langfuse: {trace_id}")
                except Exception as e:
                    logger.error(f"Error tracking with Langfuse: {str(e)}")
            
            # Return response
            return {
                'statusCode': status_code,
                'headers': {'Content-Type': 'application/json'},
                'body': response_body
            }
            
        # Handle customer status endpoint
        if http_method == 'POST' and path.endswith('/customer-status'):
            # For now, we'll use a mock implementation directly in this function
            # instead of relying on an external module
            tenant = body.get('tenant', '')
            customer_id = body.get('customer_id', '')
            
            # Validate tenant access
            if not validate_tenant_access(tenant, context, event, "customer:read"):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Unauthorized access. Invalid tenant or insufficient permissions."})
                }
            
            # Mock implementation for customer status
            status_data = {}
            if tenant == 'acme':
                status_data = {
                    "customer_id": "acme-001",
                    "customer_name": "ACME Corporation",
                    "current_stage": "Implementation",
                    "stage_order": 3,
                    "status_summary": "Active implementation in progress",
                    "implementation_progress": 65,
                    "key_contacts": [
                        {"name": "John Smith", "role": "Project Sponsor", "email": "jsmith@acme-example.com"},
                        {"name": "Mary Johnson", "role": "IT Director", "email": "mjohnson@acme-example.com"}
                    ],
                    "milestones": [
                        {"name": "Project Kickoff", "status": "completed", "completion_date": "2025-09-15"},
                        {"name": "Requirements Gathering", "status": "completed", "completion_date": "2025-10-01"},
                        {"name": "Solution Design", "status": "completed", "completion_date": "2025-10-20"},
                        {"name": "Implementation", "status": "in_progress", "target_date": "2025-12-10"},
                        {"name": "Testing", "status": "not_started", "target_date": "2025-12-20"},
                        {"name": "Go-Live", "status": "not_started", "target_date": "2026-01-15"}
                    ]
                }
            elif tenant == 'globex':
                status_data = {
                    "customer_id": "globex-001",
                    "customer_name": "GLOBEX Corporation",
                    "current_stage": "Implementation",
                    "stage_order": 3,
                    "status_summary": "Active implementation in progress",
                    "implementation_progress": 42,
                    "key_contacts": [
                        {"name": "Alice Chen", "role": "CIO", "email": "achen@globex-example.com"},
                        {"name": "Bob Wilson", "role": "Project Manager", "email": "bwilson@globex-example.com"}
                    ],
                    "milestones": [
                        {"name": "Project Kickoff", "status": "completed", "completion_date": "2025-10-02"},
                        {"name": "Requirements Gathering", "status": "completed", "completion_date": "2025-10-25"},
                        {"name": "Solution Design", "status": "in_progress", "target_date": "2025-11-30"},
                        {"name": "Implementation", "status": "not_started", "target_date": "2026-02-15"},
                        {"name": "Testing", "status": "not_started", "target_date": "2026-03-01"},
                        {"name": "Go-Live", "status": "not_started", "target_date": "2026-04-01"}
                    ]
                }
            else:
                return {
                    'statusCode': 404,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": f"No customer status found for tenant: {tenant}"})
                }
            
            # Filter by customer_id if provided
            if customer_id:
                if customer_id != status_data.get("customer_id"):
                    return {
                        'statusCode': 404,
                        'headers': {'Content-Type': 'application/json'},
                        'body': json.dumps({"error": f"Customer {customer_id} not found for tenant: {tenant}"})
                    }
            
            # Track metrics
            user_id = event.get('headers', {}).get('x-user-id') if event.get('headers') else None
            track_request_metrics(
                tenant_id=tenant,
                user_id=user_id,
                api_name="customer_status",
                status_code=200,
                start_time=start_time,
                event=event
            )
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(status_data)
            }
        
        # Default response for unsupported paths
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": "Not Found"})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        
        # Prepare error response
        error_response = {
            "message": "Internal Server Error",
            "error": str(e)
        }
        response_body = json.dumps(error_response)
        status_code = 500
        
        # Extract tenant ID if possible
        tenant_id = None
        if 'body' in event and event['body']:
            if isinstance(event['body'], str):
                try:
                    body_data = json.loads(event['body'])
                    tenant_id = body_data.get('tenant')
                except json.JSONDecodeError:
                    pass
            elif isinstance(event['body'], dict):
                tenant_id = event['body'].get('tenant')
        
        # Track error metrics if possible
        if METRICS_ENABLED and tenant_id:
            try:
                # Get the path to identify the API endpoint
                path = event.get('path', '')
                if 'requestContext' in event and 'http' in event['requestContext']:
                    path = event['requestContext']['http'].get('path', path)
                
                # Determine the API name from the path
                api_name = "unknown"
                if path.endswith('/upload-url'):
                    api_name = "upload_url"
                elif path.endswith('/kb/sync'):
                    api_name = "kb_sync"
                elif path.endswith('/kb/query'):
                    api_name = "kb_query"
                elif path.endswith('/chat'):
                    api_name = "chat"
                
                # Track the error
                user_id = event.get('headers', {}).get('x-user-id') if event.get('headers') else None
                tenant_metrics.track_api_call(
                    tenant_id=tenant_id,
                    user_id=user_id or "anonymous",
                    api_name=f"{api_name}_error",
                    status_code=status_code,
                    execution_time_ms=int((time.time() - start_time) * 1000),
                    additional_data={"error_message": str(e)}
                )
            except Exception as metrics_error:
                logger.error(f"Error tracking error metrics: {str(metrics_error)}")
        
        # Return error response
        return {
            'statusCode': status_code,
            'headers': {'Content-Type': 'application/json'},
            'body': response_body
        }
