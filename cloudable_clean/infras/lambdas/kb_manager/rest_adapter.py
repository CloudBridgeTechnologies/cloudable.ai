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
    
    # Map API Gateway paths to internal paths
    # Handle both /api/* and /dev/api/* paths
    path_mapping = {
        '/api/health': '/health',
        '/dev/api/health': '/health',
        '/api/kb/sync': '/kb/sync',
        '/dev/api/kb/sync': '/kb/sync',
        '/api/kb/query': '/kb/query',
        '/dev/api/kb/query': '/kb/query',
        '/api/chat': '/chat',
        '/dev/api/chat': '/chat',
        '/api/upload-url': '/kb/upload-url',
        '/dev/api/upload-url': '/kb/upload-url',
        '/api/customer-status': '/kb/status',
        '/dev/api/customer-status': '/kb/status',
        '/kb/upload-form': '/kb/upload-form',
        '/kb/ingestion-status': '/kb/ingestion-status'
    }
    
    if path in path_mapping:
        path = path_mapping[path]
    elif path.startswith('/api/'):
        # Generic mapping for /api/* paths
        path = path.replace('/api/', '/kb/')
    elif path.startswith('/dev/api/'):
        # Generic mapping for /dev/api/* paths
        path = path.replace('/dev/api/', '/kb/')
    
    # Extract body
    if 'body' in event and event['body']:
        try:
            # Handle base64 encoding
            if event.get('isBase64Encoded', False):
                decoded_body = base64.b64decode(event['body']).decode('utf-8')
                body = json.loads(decoded_body) if isinstance(decoded_body, str) else decoded_body
            else:
                # Handle JSON string or dict
                if isinstance(event['body'], dict):
                    body = event['body']  # Already a dict, no need to parse
                elif isinstance(event['body'], str):
                    body = json.loads(event['body'])  # Parse JSON string
                else:
                    body = {'raw_content': str(event['body'])}
        except (json.JSONDecodeError, ValueError) as e:
            # If not valid JSON, use raw body
            body = {'raw_content': event['body']}
            print(f"Error parsing body: {str(e)}")
    
    # Map tenant to tenant_id for backward compatibility
    if 'tenant' in body and 'tenant_id' not in body:
        body['tenant_id'] = body['tenant']
    
    # Add default customer_id if not present for queries
    if path == '/kb/query' and 'customer_id' not in body:
        body['customer_id'] = 'default'
    
    return http_method, path, body
