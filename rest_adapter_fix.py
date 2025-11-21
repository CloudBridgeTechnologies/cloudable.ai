def extract_request_details_from_rest_event(event):
    """
    Extract HTTP method, path, and body from an API Gateway event
    This handles both REST API and HTTP API event formats
    """
    http_method = None
    path = None
    body = {}

    # Extract HTTP method
    if 'httpMethod' in event:
        http_method = event['httpMethod']
    elif 'requestContext' in event and 'http' in event['requestContext']:
        http_method = event['requestContext']['http']['method']
    else:
        http_method = "GET"  # Default

    # Extract path
    if 'path' in event:
        path = event['path']
    elif 'requestContext' in event and 'http' in event['requestContext']:
        path = event['requestContext']['http']['path']
    else:
        path = "/"  # Default
        
    # Map API Gateway paths to our internal paths
    path_mapping = {
        '/api/health': '/health',
        '/api/kb/sync': '/kb/sync',
        '/api/kb/query': '/kb/query',
        '/api/chat': '/chat',
        '/api/upload-url': '/kb/upload-url',
        '/api/customer-status': '/kb/status'
    }
    
    if path in path_mapping:
        path = path_mapping[path]

    # Extract body
    if 'body' in event:
        if isinstance(event['body'], str):
            import json
            try:
                body = json.loads(event['body'])
            except json.JSONDecodeError:
                body = {}
        elif isinstance(event['body'], dict):
            body = event['body']
    
    # Map request parameters
    if body and 'tenant' in body:
        body['tenant_id'] = body['tenant']
        
    if body and 'document_key' in body:
        # Keep document_key as is
        pass
        
    if body and 'query' in body:
        # Keep query as is, but add customer_id if not present
        if 'customer_id' not in body:
            body['customer_id'] = 'default'

    return http_method, path, body
