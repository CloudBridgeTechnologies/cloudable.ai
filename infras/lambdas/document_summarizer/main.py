import os
import sys
import json
import logging
import urllib.parse
import time
import uuid
from datetime import datetime
import re
from io import BytesIO
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
PACKAGE_DIR = CURRENT_DIR / "package"
if PACKAGE_DIR.exists() and str(PACKAGE_DIR) not in sys.path:
    sys.path.insert(0, str(PACKAGE_DIR))

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from pypdf import PdfReader

# Configure logging
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

def get_bedrock_client():
    """Get or create Bedrock client with proper configuration"""
    if not hasattr(get_bedrock_client, 'client'):
        session = boto3.session.Session()
        get_bedrock_client.client = session.client(
            'bedrock-runtime', 
            region_name=os.environ.get('REGION', 'us-east-1'),
            config=Config(
                retries={'max_attempts': 2, 'mode': 'standard'},
                connect_timeout=5,
                read_timeout=300
            )
        )
    return get_bedrock_client.client

def get_textract_client():
    """Get or create Textract client with proper configuration"""
    if not hasattr(get_textract_client, 'client'):
        session = boto3.session.Session()
        get_textract_client.client = session.client(
            'textract',
            region_name=os.environ.get('REGION', 'us-east-1'),
            config=Config(
                retries={'max_attempts': 3, 'mode': 'standard'},
                connect_timeout=5,
                read_timeout=120
            )
        )
    return get_textract_client.client

# Configuration 
MAX_CHUNK_SIZE = int(os.environ.get('MAX_CHUNK_SIZE', '100000'))  # Increased to 100K chars for large documents
CLAUDE_MODEL_ID = os.environ.get('CLAUDE_MODEL_ID', 'anthropic.claude-3-sonnet-20240229-v1:0')
SUMMARY_BUCKET_SUFFIX = os.environ.get('SUMMARY_BUCKET_SUFFIX', 'summaries')
CHUNK_SIZE = 20000  # Size of each chunk for multi-part summarization (reduced for stability)
CHUNK_OVERLAP = 300  # Overlap between chunks to maintain context

def handle_document_event(event, context):
    """
    Process document for summarization from S3 events
    
    AWS Lambda handler function triggered by S3 event notifications
    when processed documents are created in the tenant bucket.
    
    Args:
        event (dict): The S3 event notification
        context (LambdaContext): Lambda runtime information
        
    Returns:
        dict: Response with status code and message
    """
    logger.info("Document summarization process started")
    
    if not event or 'Records' not in event:
        logger.error("Invalid event structure: missing Records")
        return {
            'statusCode': 400,
            'body': json.dumps('Invalid event structure')
        }
    
    try:
        # Track metrics for monitoring
        successful_docs = 0
        failed_docs = 0
        
        # Process each record in the S3 event
        for record in event.get('Records', []):
            # Validate record structure
            if 's3' not in record or 'bucket' not in record['s3'] or 'object' not in record['s3']:
                logger.warning("Invalid record structure in S3 event")
                continue
                
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            # Log document event with request ID for tracing
            request_id = context.aws_request_id if context else 'no-context'
            logger.info(f"Processing document event: bucket={bucket}, key={key}, request_id={request_id}")
            
            # Skip files that don't start with documents/ or already have _processed in name
            if not key.startswith('documents/'):
                logger.info(f"Skipping non-document file: {key}")
                continue
                
            if "_processed" in key:
                logger.info(f"Processing summarization for: {bucket}/{key}")
                try:
                    summary_key = summarize_document(bucket, key)
                    if summary_key:
                        successful_docs += 1
                    else:
                        failed_docs += 1
                except Exception as doc_error:
                    failed_docs += 1
                    logger.error(f"Error processing document {bucket}/{key}: {str(doc_error)}")
                    # Continue processing other documents despite individual failures
            else:
                logger.info(f"Skipping unprocessed file: {key}")
                continue
        
        # Log summarization metrics
        logger.info(f"Document summarization complete. Successful: {successful_docs}, Failed: {failed_docs}")
                
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document summarization complete',
                'successful': successful_docs,
                'failed': failed_docs
            })
        }
    except Exception as e:
        logger.error(f"Unexpected error in document processing: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Error processing documents for summarization',
                'message': str(e)
            })
        }

def summarize_document(bucket, key):
    """
    Summarize a document and store the summary in the summaries bucket
    
    Args:
        bucket (str): S3 bucket containing the document
        key (str): S3 key of the document
        
    Returns:
        str: S3 key of the generated summary document, or None if failed
        
    Raises:
        Exception: If any step in the summarization process fails
    """
    start_time = time.time()
    s3_client = get_s3_client()
    bedrock_client = get_bedrock_client()
    
    try:
        # Extract tenant from bucket name for proper routing
        tenant = "unknown"
        tenant_match = re.search(r'-([^-]+)$', bucket)
        if tenant_match:
            tenant = tenant_match.group(1)
            
        logger.info(f"Starting summarization for document: bucket={bucket}, key={key}, tenant={tenant}")
            
        # Get the document metadata
        try:
            response = s3_client.head_object(Bucket=bucket, Key=key)
            content_type = response.get('ContentType', 'application/pdf')
            metadata_json = response.get('Metadata', {}).get('kb_metadata', '{}')
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logger.error(f"S3 head_object failed: bucket={bucket}, key={key}, error={error_code}")
            if error_code == 'NoSuchKey':
                raise FileNotFoundError(f"Document {key} not found in bucket {bucket}")
            raise
        
        # Parse metadata
        try:
            metadata = json.loads(metadata_json)
            logger.debug(f"Found document metadata: title={metadata.get('title', 'Unknown')}, "
                        f"type={metadata.get('document_type', 'Unknown')}")
        except json.JSONDecodeError:
            metadata = {}
            logger.warning(f"Could not parse metadata JSON: {metadata_json}")
        
        # Get the document content
        try:
            s3_obj = s3_client.get_object(Bucket=bucket, Key=key)
            content = s3_obj['Body'].read()
            content_size = len(content)
            logger.info(f"Retrieved document content: size={content_size} bytes")
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logger.error(f"S3 get_object failed: bucket={bucket}, key={key}, error={error_code}")
            raise
        
        # Extract text based on content type
        extract_start = time.time()
        if content_type.lower() == 'application/pdf':
            document_text = extract_pdf_text(content)
        else:
            document_text = content.decode('utf-8', errors='replace')
            
        extract_time = time.time() - extract_start
        text_length = len(document_text)
        logger.info(f"Text extracted: length={text_length} chars, time={extract_time:.2f}s")
        
        # Generate summary using Bedrock
        summary_start = time.time()
        summary = generate_summary(document_text, metadata.get('title', 'Document'), bedrock_client)
        summary_time = time.time() - summary_start
        logger.info(f"Summary generated: length={len(summary)} chars, time={summary_time:.2f}s")
        
        # Create summary document with rich metadata
        document_uuid = metadata.get('uuid', str(uuid.uuid4()))
        summary_data = {
            "original_document": {
                "bucket": bucket,
                "key": key,
                "document_id": document_uuid
            },
            "metadata": metadata,
            "summary": summary,
            "generated_at": datetime.utcnow().isoformat(),
            "model_used": CLAUDE_MODEL_ID,
            "processing_stats": {
                "extract_time_seconds": extract_time,
                "summary_time_seconds": summary_time,
                "text_length": text_length,
                "summary_length": len(summary)
            }
        }
        
        # Create destination bucket name for summaries
        summary_bucket = f"cloudable-{SUMMARY_BUCKET_SUFFIX}-{os.environ.get('ENV', 'dev')}-{os.environ.get('REGION', 'us-east-1')}-{tenant}"
        
        # Generate a summary key that preserves document lineage and ensures uniqueness
        filename = key.split('/')[-1]
        base_name = os.path.splitext(filename)[0]  # Remove extension
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        summary_id = uuid.uuid4().hex[:8]
        summary_key = f"summaries/{timestamp}_{summary_id}_summary_{base_name}.json"
        
        # Store the summary with properly structured metadata
        try:
            s3_client.put_object(
                Bucket=summary_bucket,
                Key=summary_key,
                Body=json.dumps(summary_data, indent=2),
                ContentType='application/json',
                Metadata={
                    "source_document": key,
                    "document_title": metadata.get('title', 'Unknown'),
                    "document_id": document_uuid,
                    "summary_type": "executive",
                    "summary_id": summary_id,
                    "creation_date": timestamp
                },
                ServerSideEncryption="AES256"  # Enable server-side encryption
            )
        except ClientError as e:
            logger.error(f"Error storing summary: bucket={summary_bucket}, key={summary_key}, error={str(e)}")
            raise
        
        total_time = time.time() - start_time
        logger.info(f"Summary stored at {summary_bucket}/{summary_key} (total_time={total_time:.2f}s)")
        return summary_key
        
    except Exception as e:
        logger.error(f"Error summarizing document {bucket}/{key}: {str(e)}", exc_info=True)
        raise

def extract_pdf_text(pdf_content):
    """
    Extract text from PDF binary content
    
    Args:
        pdf_content (bytes): Raw PDF content
        
    Returns:
        str: Extracted text content from PDF
        
    Raises:
        ValueError: If PDF extraction fails due to invalid PDF format
    """
    textract_client = get_textract_client()

    try:
        response = textract_client.detect_document_text(Document={'Bytes': pdf_content})

        lines = []
        for block in response.get('Blocks', []):
            if block.get('BlockType') == 'LINE' and 'Text' in block:
                lines.append(block['Text'])

        if lines:
            return "\n".join(lines).strip()

        logger.warning("Textract returned no text for the PDF document; falling back to PyPDF")

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        if error_code in {"UnsupportedDocumentException", "InvalidParameterException", "InvalidS3ObjectException"}:
            logger.warning(f"Textract could not process document ({error_code}); falling back to PyPDF", exc_info=True)
        else:
            logger.error(f"Textract client error: {error_code}", exc_info=True)
            raise
    except Exception as e:
        logger.warning(f"Textract extraction failed: {str(e)}; falling back to PyPDF", exc_info=True)

    return extract_pdf_text_with_pypdf(pdf_content)


def extract_pdf_text_with_pypdf(pdf_content):
    """Extract text using PyPDF as a fallback when Textract is unavailable."""
    try:
        reader = PdfReader(BytesIO(pdf_content))
        if reader.is_encrypted:
            try:
                reader.decrypt("")
            except Exception:
                raise ValueError("Encrypted PDFs are not supported for summarization")

        total_pages = len(reader.pages)
        if total_pages == 0:
            logger.warning("PDF document contains no pages")
            return ""

        logger.info(f"PyPDF fallback: pages={total_pages}, encrypted={reader.is_encrypted}")

        text_parts = []
        for page in reader.pages:
            page_text = page.extract_text() or ""
            text_parts.append(page_text)

        return "\n".join(text_parts).strip()

    except Exception as e:
        logger.error(f"Error extracting PDF text with PyPDF: {str(e)}", exc_info=True)
        raise

def summarize_large_document(text, title, bedrock_client):
    """
    Summarize a large document by processing it in chunks and combining summaries
    
    Args:
        text (str): Full document text
        title (str): Document title
        bedrock_client (boto3.client): Initialized Bedrock client
    
    Returns:
        str: Combined summary of the entire document
    """
    try:
        logger.info(f"Starting chunk-based summarization for large document: {title}")
        
        # Split text into smaller chunks for more reliable processing
        chunks = []
        start = 0
        while start < len(text):
            end = min(start + CHUNK_SIZE, len(text))
            chunks.append(text[start:end])
            start = end - CHUNK_OVERLAP if end < len(text) else end
        
        logger.info(f"Split document into {len(chunks)} chunks")
        
        # Summarize each chunk - limit to 10 chunks max for very large documents
        # Use max 10 chunks to balance completeness with Lambda processing limits
        max_chunks = 10
        if len(chunks) > max_chunks:
            logger.warning(f"Document produced {len(chunks)} chunks, limiting to first {max_chunks}")
            chunks = chunks[:max_chunks]
            
        chunk_summaries = []
        for i, chunk in enumerate(chunks):
            logger.info(f"Summarizing chunk {i+1}/{min(len(chunks), 5)}")
            
            chunk_prompt = f"""
            Summarize the following section of the document "{title}":
            
            {chunk}
            
            Provide a concise summary of the key points in this section.
            """
            
            response = bedrock_client.invoke_model(
                modelId=CLAUDE_MODEL_ID,
                body=json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 500,
                    "temperature": 0,
                    "messages": [{"role": "user", "content": chunk_prompt}]
                })
            )
            
            response_body = json.loads(response.get('body').read())
            chunk_summary = response_body['content'][0]['text']
            chunk_summaries.append(chunk_summary)
        
        # Combine chunk summaries into final summary
        logger.info("Combining chunk summaries into final summary")
        
        combined_text = "\n\n".join(chunk_summaries)
        
        final_prompt = f"""
        You are an expert document summarizer. Based on the following section summaries from the document "{title}", 
        create a comprehensive executive summary:
        
        {combined_text}
        
        Please provide a well-structured executive summary that includes:
        1. Executive Overview: Main topic and purpose
        2. Key Points: Bulleted list of important information
        3. Details & Facts: Specific information from the document
        4. Conclusions: Main takeaways
        
        Format the summary in a professional business format.
        """
        
        response = bedrock_client.invoke_model(
            modelId=CLAUDE_MODEL_ID,
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 2000,
                "temperature": 0,
                "messages": [{"role": "user", "content": final_prompt}]
            })
        )
        
        response_body = json.loads(response.get('body').read())
        final_summary = response_body['content'][0]['text']
        
        logger.info("Chunk-based summarization completed successfully")
        return final_summary
        
    except Exception as e:
        logger.error(f"Error in chunk-based summarization: {str(e)}", exc_info=True)
        # Fallback to first chunk only
        return f"Error processing full document. Partial summary based on beginning of document:\n\n{generate_summary(text[:CHUNK_SIZE], title, bedrock_client)}"

def generate_summary(text, title, bedrock_client):
    """
    Generate a document summary using Amazon Bedrock (Claude)
    
    Args:
        text (str): Document text to summarize
        title (str): Document title
        bedrock_client (boto3.client): Initialized Bedrock client
        
    Returns:
        str: Generated document summary
        
    Raises:
        Exception: If Bedrock API call fails
    """
    try:
        # Validate input
        if not text or len(text) < 100:
            logger.warning(f"Document text too short for summarization: {len(text)} chars")
            return f"The document '{title}' contains insufficient text for summarization."
            
        # Handle large documents by summarizing in chunks if necessary
        original_length = len(text)
        if original_length > MAX_CHUNK_SIZE:
            logger.info(f"Document is large ({original_length} chars), using chunk-based summarization")
            # For very large documents, we'll use a different approach
            # Split into manageable chunks and summarize each, then combine
            return summarize_large_document(text, title, bedrock_client)
        
        # For normal-sized documents, proceed with single summarization
        truncation_notice = ""
        
        # Create the prompt for summarization with clear instructions
        prompt = f"""
        You are an expert document summarizer. Your task is to create a comprehensive executive summary of the following document:
        
        DOCUMENT TITLE: {title}
        
        DOCUMENT TEXT:
        {text}
        
        {truncation_notice}
        
        Please provide a well-structured executive summary that includes:
        1. Main topic and purpose of the document
        2. Key points and information
        3. Important details, facts, and figures
        4. Conclusions or recommendations
        
        Format your summary with the following sections:
        - Executive Overview: 1-2 paragraphs summarizing the document's purpose and main points
        - Key Points: Bulleted list of the most important information
        - Details & Facts: Important specific information from the document
        - Conclusions: Main takeaways or recommendations from the document
        
        Focus on capturing the most essential information in a professional business format.
        """
        
        # Call Bedrock with Claude model using structured request with error handling
        try:
            start_time = time.time()
            response = bedrock_client.invoke_model(
                modelId=CLAUDE_MODEL_ID,
                body=json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 2000,  # Increased for more comprehensive summaries
                    "temperature": 0,    # Zero temperature for consistent, deterministic outputs
                    "system": "You are an AI assistant that creates concise and accurate document summaries for business professionals.",
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ]
                })
            )
            
            # Calculate and log API call latency
            latency = time.time() - start_time
            logger.info(f"Bedrock API call completed in {latency:.2f}s")
            
            # Parse the response
            try:
                response_body = json.loads(response.get('body').read())
                
                # Extract content from the response
                if 'content' in response_body and isinstance(response_body['content'], list) and response_body['content']:
                    summary = response_body['content'][0].get('text', '')
                    
                    # No truncation notice needed anymore as we handle large documents with chunking
                        
                    return summary
                else:
                    logger.error(f"Unexpected response structure from Bedrock: {str(response_body)}")
                    return "Error: Unable to generate summary due to unexpected API response format."
                    
            except (json.JSONDecodeError, KeyError) as e:
                logger.error(f"Error parsing Bedrock response: {str(e)}", exc_info=True)
                return "Error: Unable to parse the summary generated by the AI model."
                
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_message = e.response.get('Error', {}).get('Message', 'No message')
            logger.error(f"Bedrock API error: {error_code} - {error_message}")
            
            # Handle common error cases
            if 'ThrottlingException' in str(e):
                raise Exception("Summary generation temporarily unavailable due to high demand. Please try again shortly.")
            elif 'ValidationException' in str(e) and 'Input content is too large' in str(e):
                return "The document is too large for summarization. Please try with a smaller document."
            else:
                raise Exception(f"Error calling Bedrock API: {error_code} - {error_message}")
            
    except Exception as e:
        logger.error(f"Error generating summary with Bedrock: {str(e)}", exc_info=True)
        raise
