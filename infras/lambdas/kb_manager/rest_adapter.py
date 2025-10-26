"""
REST API adapter module for handling different API Gateway request formats.

This module provides utility functions for extracting HTTP method, path, and body 
from API Gateway events, handling both REST API and HTTP API formats.
"""
import json
import base64
from typing import Tuple, Dict, Any, Optional

def extract_request_details_from_rest_event(event: Dict[str, Any]) -> Tuple[str, str, Dict[str, Any]]:
    """Extract HTTP method, path, and body from API Gateway event
    
    Handles both REST API and HTTP API formats
    
    Args:
        event: API Gateway event
    
    Returns:
        tuple: (http_method, path, body)
    """
    body = {}
    
    # Extract HTTP method
    if 'httpMethod' in event:
        # REST API
        http_method = event['httpMethod']
    elif 'requestContext' in event and 'http' in event['requestContext']:
        # HTTP API v2
        http_method = event['requestContext']['http']['method']
    else:
        http_method = 'GET'
    
    # Extract path
    if 'path' in event:
        # REST API or HTTP API v2 with simple path
        path = event['path']
    elif 'rawPath' in event:
        # HTTP API v2 with rawPath
        path = event['rawPath']
    elif 'resource' in event:
        # Fallback to resource path
        path = event['resource']
    else:
        path = '/'
    
    # Extract body
    if 'body' in event and event['body']:
        try:
            # Handle base64 encoding
            if event.get('isBase64Encoded', False):
                decoded_body = base64.b64decode(event['body']).decode('utf-8')
                body = json.loads(decoded_body)
            else:
                # Handle JSON string
                body = json.loads(event['body'])
        except (json.JSONDecodeError, ValueError):
            # If not valid JSON, use raw body
            body = {'raw_content': event['body']}
    
    return http_method, path, body
