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

# Mock embeddings function (in real implementation, this would use AWS Bedrock)
def generate_embedding(text):
    # This is a mock that returns a 1536-dimension vector with random values
    # In production, you would call AWS Bedrock's Titan Embeddings model
    embedding = np.random.uniform(-1, 1, 1536)
    # Normalize the vector to unit length
    embedding = embedding / np.linalg.norm(embedding)
    return embedding.tolist()

def execute_statement(sql, parameters=None, transaction_id=None):
    """Execute an SQL statement on the Aurora PostgreSQL database using the Data API"""
    try:
        params = {
            'resourceArn': RDS_CLUSTER_ARN,
            'secretArn': RDS_SECRET_ARN,
            'database': RDS_DATABASE,
            'sql': sql
        }
        
        if parameters:
            params['parameters'] = parameters
            
        if transaction_id:
            params['transactionId'] = transaction_id
            
        response = rds_client.execute_statement(**params)
        return response
    except ClientError as e:
        logger.error(f"Error executing SQL: {e}")
        raise

def get_document_content(tenant, document_key):
    """Retrieve document content from S3"""
    try:
        # Format the S3 bucket name based on tenant
        bucket_name = f"cloudable-kb-dev-us-east-1-{tenant}-20251114095518"
        
        # Get the object from S3
        response = s3_client.get_object(Bucket=bucket_name, Key=document_key)
        content = response['Body'].read().decode('utf-8')
        return content
    except ClientError as e:
        logger.error(f"Error retrieving document from S3: {e}")
        return None

def query_knowledge_base(tenant, query_text, max_results=3):
    """Query the knowledge base using vector similarity search"""
    try:
        # Generate embedding for the query
        query_embedding = generate_embedding(query_text)
        
        # Convert the embedding to a string representation that PostgreSQL can understand
        embedding_str = str(query_embedding).replace('[', '').replace(']', '')
        
        # Create the SQL query to find similar vectors
        sql = f"""
        SELECT id, chunk_text, metadata, 
               (embedding <=> '[{embedding_str}]'::vector) as distance
        FROM kb_vectors_{tenant}
        ORDER BY distance
        LIMIT :max_results
        """
        
        # Execute the query
        response = execute_statement(
            sql,
            parameters=[
                {'name': 'max_results', 'value': {'longValue': max_results}}
            ]
        )
        
        # Process results
        results = []
        if 'records' in response:
            for record in response['records']:
                chunk_text = record[1]['stringValue'] if 'stringValue' in record[1] else ""
                metadata_str = record[2]['stringValue'] if 'stringValue' in record[2] else "{}"
                distance = record[3]['doubleValue'] if 'doubleValue' in record[3] else 1.0
                
                # Convert distance to a similarity score (1 - distance)
                similarity_score = max(0, 1 - distance)
                
                try:
                    metadata = json.loads(metadata_str)
                except:
                    metadata = {"source": "unknown"}
                
                results.append({
                    "text": chunk_text,
                    "metadata": metadata,
                    "score": similarity_score
                })
        
        return results
    except Exception as e:
        logger.error(f"Error querying knowledge base: {e}")
        return []

def sync_document(tenant, document_key):
    """Process a document and add it to the knowledge base"""
    try:
        # Get the document content
        content = get_document_content(tenant, document_key)
        if not content:
            return {"error": "Document not found or could not be read"}
        
        # In a real implementation, we would split the document into chunks
        # For this demo, we'll create chunks based on sections (marked by ##)
        chunks = []
        lines = content.split('\n')
        current_chunk = ""
        current_heading = ""
        
        for line in lines:
            if line.startswith('## '):
                # If we have a current chunk, add it
                if current_chunk:
                    chunks.append({
                        "text": current_chunk.strip(),
                        "heading": current_heading,
                        "metadata": {
                            "source": document_key,
                            "section": current_heading
                        }
                    })
                
                # Start a new chunk
                current_heading = line.replace('## ', '').strip()
                current_chunk = line + "\n"
            else:
                current_chunk += line + "\n"
        
        # Add the last chunk
        if current_chunk:
            chunks.append({
                "text": current_chunk.strip(),
                "heading": current_heading,
                "metadata": {
                    "source": document_key,
                    "section": current_heading
                }
            })
        
        # Insert chunks into the database
        for chunk in chunks:
            # Generate embedding for the chunk text
            embedding = generate_embedding(chunk["text"])
            embedding_str = str(embedding).replace('[', '').replace(']', '')
            
            # Create a UUID for the chunk
            chunk_id = str(uuid.uuid4())
            
            # Create metadata JSON
            metadata_json = json.dumps(chunk["metadata"])
            
            # Insert the chunk into the database
            sql = f"""
            INSERT INTO kb_vectors_{tenant} (id, chunk_text, embedding, metadata)
            VALUES (:id, :chunk_text, '[{embedding_str}]'::vector, :metadata::jsonb)
            """
            
            execute_statement(
                sql,
                parameters=[
                    {'name': 'id', 'value': {'stringValue': chunk_id}},
                    {'name': 'chunk_text', 'value': {'stringValue': chunk["text"]}},
                    {'name': 'metadata', 'value': {'stringValue': metadata_json}}
                ]
            )
        
        return {
            "message": "Document processed successfully",
            "chunks_processed": len(chunks)
        }
    except Exception as e:
        logger.error(f"Error syncing document: {e}")
        return {"error": str(e)}

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
        
        # Extract request body
        body = {}
        if 'body' in event:
            if isinstance(event['body'], str):
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    pass
            elif isinstance(event['body'], dict):
                body = event['body']
        
        # Process based on path
        if http_method == 'GET' and path.endswith('/health'):
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"message": "Cloudable.AI KB Manager API is operational"})
            }
        
        # Handle KB sync endpoint
        if http_method == 'POST' and path.endswith('/kb/sync'):
            tenant = body.get('tenant', '')
            document_key = body.get('document_key', '')
            
            if not tenant or not document_key:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and document_key"})
                }
            
            # Process the document
            result = sync_document(tenant, document_key)
            
            return {
                'statusCode': 200 if 'error' not in result else 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(result)
            }
        
        # Handle KB query endpoint
        if http_method == 'POST' and path.endswith('/kb/query'):
            tenant = body.get('tenant', '')
            query = body.get('query', '')
            max_results = int(body.get('max_results', 3))
            
            if not tenant or not query:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and query"})
                }
            
            # Query the knowledge base
            results = query_knowledge_base(tenant, query, max_results)
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "results": results,
                    "query": query
                })
            }
        
        # Handle chat endpoint
        if http_method == 'POST' and path.endswith('/chat'):
            tenant = body.get('tenant', '')
            message = body.get('message', '')
            use_kb = body.get('use_kb', True)
            
            if not tenant or not message:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and message"})
                }
            
            # In a real implementation, this would query the KB and then use Bedrock to generate a response
            
            # If using the knowledge base, first retrieve relevant context
            source_documents = []
            if use_kb:
                kb_results = query_knowledge_base(tenant, message, 2)
                source_documents = kb_results
            
            # Generate a response based on the tenant and message
            if tenant == 'acme':
                if 'status' in message.lower():
                    response = "ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025."
                elif 'metrics' in message.lower() or 'success' in message.lower():
                    response = "ACME's success metrics include 30% reduction in order processing time (currently at 18%), 25% improvement in inventory accuracy (currently at 20%), and 15% increase in customer satisfaction (currently at 8%)."
                elif 'next' in message.lower() or 'step' in message.lower():
                    response = "The next steps for ACME are to complete the supply chain module by November 30, schedule field service training for December, and prepare the final phase deployment plan by November 25."
                else:
                    response = "ACME Corporation is a manufacturing company with 500 employees currently implementing a digital transformation project. They're in phase 3 of 5, with several key solutions already implemented and others pending completion by December 2025."
            elif tenant == 'globex':
                if 'status' in message.lower():
                    response = "Globex Industries is currently in the Onboarding stage (phase 1 of 4), with implementation having started on October 2, 2025 and expected completion by June 15, 2026."
                elif 'stakeholder' in message.lower():
                    response = "Key stakeholders at Globex include Thomas Wong (CTO), Aisha Patel (CDO), Robert Martinez (Customer Experience), and Jennifer Lee (Compliance Director)."
                elif 'risk' in message.lower():
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
                    "source_documents": source_documents
                })
            }
        
        # Default response for unsupported paths
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": "Not Found"})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": f"Internal Server Error: {str(e)}"})
        }
