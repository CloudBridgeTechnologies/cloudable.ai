"""
Fixed version of Langfuse integration module with correct authentication
"""
import json
import os
import logging
import uuid
import base64
import requests

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# URL for Langfuse API 
LANGFUSE_HOST = os.environ.get('LANGFUSE_HOST', 'https://cloud.langfuse.com')
LANGFUSE_PUBLIC_KEY = os.environ.get('LANGFUSE_PUBLIC_KEY')
LANGFUSE_SECRET_KEY = os.environ.get('LANGFUSE_SECRET_KEY')
LANGFUSE_PROJECT_ID = os.environ.get('LANGFUSE_PROJECT_ID', 'cmhz8tqhk00duad07xptpuo06')

def send_trace_to_langfuse(trace_id, event_type, trace_data):
    """
    Send trace data directly to Langfuse
    
    Args:
        trace_id: ID of the trace
        event_type: Type of event (trace, span, generation, etc.)
        trace_data: Data to send
    """
    try:
        if not LANGFUSE_PUBLIC_KEY or not LANGFUSE_SECRET_KEY:
            logger.warning("Langfuse API keys not configured")
            return False
            
        # Create auth header
        auth_string = f"{LANGFUSE_PUBLIC_KEY}:{LANGFUSE_SECRET_KEY}"
        encoded_auth = base64.b64encode(auth_string.encode('utf-8')).decode('utf-8')
        auth_header = f"Basic {encoded_auth}"
        
        # Add trace ID if not present
        if 'id' not in trace_data:
            trace_data['id'] = trace_id
            
        # Add project ID
        if LANGFUSE_PROJECT_ID and 'projectId' not in trace_data:
            trace_data['projectId'] = LANGFUSE_PROJECT_ID
            
        # Set up headers
        headers = {
            'Content-Type': 'application/json',
            'Authorization': auth_header
        }
        
        # Construct URL
        url = f"{LANGFUSE_HOST}/api/public/{event_type}s"
        
        # Send request
        logger.info(f"Making request to Langfuse: {url}")
        logger.info(f"Auth header present: {bool(auth_header)}")
        
        response = requests.post(
            url,
            headers=headers,
            json=trace_data
        )
        
        if response.status_code != 200:
            logger.error(f"Langfuse API error: {response.status_code} {response.text}")
            return False
            
        logger.info(f"Successfully sent {event_type} to Langfuse")
        return True
    except Exception as e:
        logger.error(f"Error sending data to Langfuse: {e}")
        return False

def trace_kb_query(tenant_id, query, results):
    """
    Send KB query trace to Langfuse
    """
    trace_id = str(uuid.uuid4())
    
    # Create trace
    trace_data = {
        'name': 'kb_query',
        'userId': tenant_id,
        'metadata': {
            'tenant_id': tenant_id
        }
    }
    
    success = send_trace_to_langfuse(trace_id, 'trace', trace_data)
    
    if success:
        # Create span for the query
        span_data = {
            'name': 'kb_query_operation',
            'traceId': trace_id,
            'input': {'query': query},
            'output': {'results': results},
            'metadata': {
                'tenant_id': tenant_id,
                'result_count': len(results)
            }
        }
        send_trace_to_langfuse(str(uuid.uuid4()), 'span', span_data)
        
    return success

def trace_chat(tenant_id, message, response):
    """
    Send chat trace to Langfuse
    """
    trace_id = str(uuid.uuid4())
    
    # Create trace
    trace_data = {
        'name': 'chat',
        'userId': tenant_id,
        'metadata': {
            'tenant_id': tenant_id
        }
    }
    
    success = send_trace_to_langfuse(trace_id, 'trace', trace_data)
    
    if success:
        # Create generation for the chat
        generation_data = {
            'name': 'chat_response',
            'traceId': trace_id,
            'model': 'ai.cloudable.custom',
            'prompt': message,
            'completion': response,
            'metadata': {
                'tenant_id': tenant_id
            }
        }
        send_trace_to_langfuse(str(uuid.uuid4()), 'generation', generation_data)
        
    return success

def handler(event, context):
    """Test handler to verify Langfuse connection"""
    try:
        logger.info(f"Testing Langfuse integration with event: {json.dumps(event)}")
        
        # Extract tenant and query from the event
        tenant_id = 'test-tenant'
        query = 'Test query'
        
        if 'tenant' in event:
            tenant_id = event['tenant']
        if 'query' in event:
            query = event['query']
            
        # Create test results
        results = [
            {
                'text': 'Test result',
                'metadata': {'source': 'Test source'},
                'score': 0.95
            }
        ]
        
        # Send test trace
        success = trace_kb_query(tenant_id, query, results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': success,
                'message': 'Langfuse test completed' if success else 'Langfuse test failed'
            })
        }
    except Exception as e:
        logger.error(f"Error in test handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'message': f'Error: {str(e)}'
            })
        }
