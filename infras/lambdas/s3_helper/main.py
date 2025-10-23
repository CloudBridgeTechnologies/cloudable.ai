import os
import json
import logging
import urllib.parse
from datetime import datetime
import uuid
import re
import traceback
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger()

# Initialize AWS clients lazily to improve cold start times
def get_s3_client():
    """Get or create S3 client with proper configuration"""
    if not hasattr(get_s3_client, 'client'):
        session = boto3.session.Session()
        get_s3_client.client = session.client(
            's3', 
            region_name=os.environ.get('REGION', 'us-east-1'),
            config=Config(
                retries={'max_attempts': 3, 'mode': 'standard'},
                max_pool_connections=10
            )
        )
    return get_s3_client.client

def get_lambda_client():
    if not hasattr(get_lambda_client, 'client'):
        session = boto3.session.Session()
        get_lambda_client.client = session.client(
            'lambda',
            region_name=os.environ.get('REGION', 'us-east-1'),
            config=Config(
                retries={'max_attempts': 2, 'mode': 'standard'}
            )
        )
    return get_lambda_client.client

# Constants
DEFAULT_REGION = os.environ.get('REGION', 'us-east-1')
DEFAULT_ENV = os.environ.get('ENV', 'dev')
ENABLE_DETAILED_METRICS = os.environ.get('ENABLE_DETAILED_METRICS', 'false').lower() == 'true'
DOCUMENT_TYPES = {
    '.pdf': 'pdf',
    '.txt': 'text',
    '.md': 'markdown',
    '.docx': 'word',
    '.doc': 'word',
    '.xlsx': 'excel',
    '.xls': 'excel',
    '.csv': 'csv',
    '.pptx': 'powerpoint',
    '.ppt': 'powerpoint',
    '.json': 'json',
    '.html': 'html',
    '.htm': 'html'
}

def handle_s3_event(event, context):
    """
    Process S3 events and add metadata to make KB compatible
    
    This function processes S3 object creation events, extracts metadata,
    and creates a processed version of the document with structured metadata
    for knowledge base ingestion and summarization.
    
    Args:
        event (dict): S3 event notification
        context (object): Lambda context object
        
    Returns:
        dict: Response containing status code and processing results
    """
    start_time = datetime.utcnow()
    s3_client = get_s3_client()
    request_id = context.aws_request_id if context else 'no-context'
    processing_results = {
        'processed': 0,
        'skipped': 0,
        'failed': 0,
        'processing_time_ms': 0
    }
    
    logger.info(f"S3 Helper Lambda invoked: request_id={request_id}")
    
    # Input validation
    if not event or 'Records' not in event:
        logger.error("Invalid event structure: missing Records")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid event structure'})
        }
    
    try:
        # Process each record in the S3 event
        for record in event.get('Records', []):
            # Validate record structure
            if 's3' not in record or 'bucket' not in record['s3'] or 'object' not in record['s3']:
                logger.warning(f"Invalid record structure in S3 event: {json.dumps(record)}")
                processing_results['skipped'] += 1
                continue
                
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            object_size = record['s3'].get('object', {}).get('size', 0)
            
            # Log event details
            logger.info(f"Processing S3 event: bucket={bucket}, key={key}, size={object_size} bytes")
            
            # Skip files that don't match our document criteria
            if not key.startswith('documents/'):
                logger.info(f"Skipping non-document file: {key}")
                processing_results['skipped'] += 1
                continue
            
            if "/processed/" in key:
                logger.info(f"Skipping already processed file: {key}")
                processing_results['skipped'] += 1
                continue
            
            # Process the document
            success = process_document(s3_client, bucket, key)
            if success:
                processing_results['processed'] += 1
            else:
                processing_results['failed'] += 1
                
        # Calculate processing time
        end_time = datetime.utcnow()
        processing_time = end_time - start_time
        processing_results['processing_time_ms'] = int(processing_time.total_seconds() * 1000)
        
        # Log summary
        logger.info(f"Processing complete: processed={processing_results['processed']}, " + 
                    f"skipped={processing_results['skipped']}, failed={processing_results['failed']}, " +
                    f"time={processing_results['processing_time_ms']}ms")
                
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processing complete',
                'results': processing_results
            })
        }
    except Exception as e:
        logger.error(f"Unexpected error in handler: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Error processing documents',
                'message': str(e)
            })
        }

def process_document(s3_client, bucket, key):
    """
    Process a single document from S3
    
    Args:
        s3_client: Boto3 S3 client
        bucket (str): S3 bucket name
        key (str): S3 object key
        
    Returns:
        bool: True if processing was successful, False otherwise
    """
    try:
        # Log start of document processing
        logger.info(f"Processing document: bucket={bucket}, key={key}")
        document_id = str(uuid.uuid4())
        
        # Get the original document's metadata
        try:
            response = s3_client.head_object(Bucket=bucket, Key=key)
            content_type = response.get('ContentType', 'application/pdf')
            original_metadata = response.get('Metadata', {})
            logger.debug(f"Original metadata: content_type={content_type}, metadata={original_metadata}")
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logger.error(f"Error getting object metadata: bucket={bucket}, key={key}, error_code={error_code}")
            return False
                
        # Download the content with appropriate error handling
        try:
            s3_obj = s3_client.get_object(Bucket=bucket, Key=key)
            content = s3_obj['Body'].read()
            content_length = len(content)
            logger.info(f"Downloaded document: size={content_length} bytes")
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logger.error(f"Error downloading object: bucket={bucket}, key={key}, error_code={error_code}")
            return False
        
        # Extract file details
        filename = key.split('/')[-1]
        base_name, extension = os.path.splitext(filename)
        
        # Determine document type based on file extension
        doc_type = DOCUMENT_TYPES.get(extension.lower(), "unknown")
        
        # Extract timestamp if available in standard format
        timestamp_match = re.search(r'(\d{8}_\d{6})', filename)
        upload_timestamp = timestamp_match.group(1) if timestamp_match else datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        # Identify tenant from bucket name
        tenant = "unknown"
        tenant_match = re.search(r'-([^-]+)$', bucket)
        if tenant_match:
            tenant = tenant_match.group(1)
        
        # Add document classification
        document_category = classify_document(filename)
        
        # Create a rich structured metadata object
        metadata = {
            "document_id": document_id,
            "source": key,
            "title": extract_title(filename),
            "content_type": content_type,
            "document_type": doc_type,
            "document_category": document_category,
            "file_size_bytes": content_length,
            "upload_timestamp": upload_timestamp,
            "processing_timestamp": datetime.utcnow().isoformat(),
            "tenant": tenant,
            "version": "1.0",
            "uuid": document_id,
            "original_metadata": original_metadata
        }
        
        # Create a new key within documents/processed/ to trigger summarization
        path_parts = key.split('/')
        if len(path_parts) > 1:
            dir_parts = path_parts[:-1]
        else:
            dir_parts = []

        if 'processed' in dir_parts:
            logger.info(f"Skipping file already in processed directory: {key}")
            return False

        if 'raw' in dir_parts:
            raw_index = dir_parts.index('raw')
            processed_parts = dir_parts[:raw_index] + ['processed']
        else:
            processed_parts = dir_parts + ['processed'] if dir_parts else ['processed']

        processed_dir = '/'.join(processed_parts)
        
        # Create two versions - one for summarization and one for knowledge base
        processed_summary_key = f"{processed_dir}/{base_name}_processed_summary{extension}" if processed_dir else f"processed/{base_name}_processed_summary{extension}"
        processed_kb_key = f"{processed_dir}/{base_name}_processed_kb{extension}" if processed_dir else f"processed/{base_name}_processed_kb{extension}"
        
        # For backward compatibility, use the summary key as the main processed key
        processed_key = processed_summary_key
        
        # Upload with structured metadata that OpenSearch can parse
        try:
            s3_client.put_object(
                Bucket=bucket,
                Key=processed_key,
                Body=content,
                ContentType=content_type,
                Metadata={
                    "kb_metadata": json.dumps(metadata)
                },
                # Enable server-side encryption
                ServerSideEncryption="AES256"
            )
            logger.info(f"Summary version uploaded: bucket={bucket}, key={processed_key}, document_id={document_id}")
            
            # Also upload the KB version with the same content
            s3_client.put_object(
                Bucket=bucket,
                Key=processed_kb_key,
                Body=content,
                ContentType=content_type,
                Metadata={
                    "kb_metadata": json.dumps(metadata)
                },
                # Enable server-side encryption
                ServerSideEncryption="AES256"
            )
            logger.info(f"KB version uploaded: bucket={bucket}, key={processed_kb_key}")

            kb_sync_function = os.environ.get('KB_SYNC_FUNCTION')
            if kb_sync_function:
                try:
                    lambda_payload = {
                        "Records": [
                            {
                                "s3": {
                                    "bucket": {"name": bucket},
                                    "object": {"key": processed_kb_key}
                                }
                            }
                        ]
                    }
                    get_lambda_client().invoke(
                        FunctionName=kb_sync_function,
                        InvocationType='Event',
                        Payload=json.dumps(lambda_payload).encode('utf-8')
                    )
                    logger.info(f"Triggered KB sync via Lambda for KB key: {processed_kb_key}")
                except Exception as invoke_error:
                    logger.error(f"Failed to invoke KB sync trigger: {invoke_error}", exc_info=True)
            return True
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logger.error(f"Error uploading document versions: bucket={bucket}, error_code={error_code}")
            return False
            
    except Exception as e:
        logger.error(f"Error processing document {bucket}/{key}: {str(e)}", exc_info=True)
        return False

def extract_title(filename):
    """Extract a more readable title from filename"""
    # Remove extension
    base_name = os.path.splitext(filename)[0]
    
    # Remove timestamp patterns
    base_name = re.sub(r'\d{8}_\d{6}', '', base_name)
    
    # Remove UUIDs or random hex strings
    base_name = re.sub(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', '', base_name, flags=re.IGNORECASE)
    base_name = re.sub(r'[a-f0-9]{8}', '', base_name, flags=re.IGNORECASE)
    
    # Replace underscores and hyphens with spaces
    base_name = base_name.replace('_', ' ').replace('-', ' ')
    
    # Clean up multiple spaces
    base_name = re.sub(r'\s+', ' ', base_name).strip()
    
    # Title case the result
    title = ' '.join(word.capitalize() for word in base_name.split())
    
    # If we end up with empty string, use the original filename
    return title if title else filename

def classify_document(filename):
    """Simple document classification based on filename"""
    filename_lower = filename.lower()
    
    if any(keyword in filename_lower for keyword in ['policy', 'policies']):
        return "policy"
    elif any(keyword in filename_lower for keyword in ['manual', 'guide', 'handbook']):
        return "guide"
    elif any(keyword in filename_lower for keyword in ['report', 'analysis']):
        return "report"
    elif any(keyword in filename_lower for keyword in ['form', 'application']):
        return "form"
    elif any(keyword in filename_lower for keyword in ['contract', 'agreement', 'legal']):
        return "legal"
    elif any(keyword in filename_lower for keyword in ['memo', 'minutes', 'meeting']):
        return "internal"
    else:
        return "document"

def extract_title(filename):
    """Extract a more readable title from filename"""
    # Remove extension
    base_name = os.path.splitext(filename)[0]
    
    # Remove timestamp patterns
    base_name = re.sub(r'\d{8}_\d{6}', '', base_name)
    
    # Remove UUIDs or random hex strings
    base_name = re.sub(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', '', base_name, flags=re.IGNORECASE)
    base_name = re.sub(r'[a-f0-9]{8}', '', base_name, flags=re.IGNORECASE)
    
    # Replace underscores and hyphens with spaces
    base_name = base_name.replace('_', ' ').replace('-', ' ')
    
    # Clean up multiple spaces
    base_name = re.sub(r'\s+', ' ', base_name).strip()
    
    # Title case the result
    title = ' '.join(word.capitalize() for word in base_name.split())
    
    # If we end up with empty string, use the original filename
    return title if title else filename

def classify_document(filename):
    """Simple document classification based on filename"""
    filename_lower = filename.lower()
    
    if any(keyword in filename_lower for keyword in ['policy', 'policies']):
        return "policy"
    elif any(keyword in filename_lower for keyword in ['manual', 'guide', 'handbook']):
        return "guide"
    elif any(keyword in filename_lower for keyword in ['report', 'analysis']):
        return "report"
    elif any(keyword in filename_lower for keyword in ['form', 'application']):
        return "form"
    elif any(keyword in filename_lower for keyword in ['contract', 'agreement', 'legal']):
        return "legal"
    elif any(keyword in filename_lower for keyword in ['memo', 'minutes', 'meeting']):
        return "internal"
    else:
        return "document"