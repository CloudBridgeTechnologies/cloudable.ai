"""
Lambda authorizer for API Gateway to validate Cognito tokens and tenant access.
"""

import os
import json
import logging
import time
import boto3
import urllib.request
from jose import jwk, jwt
from jose.utils import base64url_decode

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Cache for JWKs
jwks_cache = {}
jwks_cache_timestamp = 0
JWKS_CACHE_TTL = 3600  # 1 hour

def get_jwks():
    """Get JWKs from Cognito for token validation"""
    global jwks_cache, jwks_cache_timestamp
    
    # Check if cache is valid
    current_time = time.time()
    if jwks_cache and (current_time - jwks_cache_timestamp) < JWKS_CACHE_TTL:
        return jwks_cache
    
    # Get user pool region and ID from environment
    region = os.environ.get('USER_POOL_REGION', 'us-east-1')
    user_pool_id = os.environ.get('USER_POOL_ID')
    
    if not user_pool_id:
        raise Exception("USER_POOL_ID environment variable not set")
    
    # Fetch JWKs from Cognito
    keys_url = f'https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json'
    try:
        with urllib.request.urlopen(keys_url) as f:
            response = f.read().decode('utf-8')
        
        keys = json.loads(response)['keys']
        jwks_cache = {key['kid']: key for key in keys}
        jwks_cache_timestamp = current_time
        
        return jwks_cache
    except Exception as e:
        logger.error(f"Error fetching JWKs: {str(e)}")
        raise Exception('Error fetching JWKs')

def verify_token(token):
    """Verify JWT token from Cognito"""
    # Get token header
    token_header = jwt.get_unverified_header(token)
    kid = token_header.get('kid')
    
    # Get JWKs
    jwks = get_jwks()
    key = jwks.get(kid)
    
    if not key:
        raise Exception('Invalid token: Key ID not found')
    
    # Get user pool region and ID from environment
    region = os.environ.get('USER_POOL_REGION', 'us-east-1')
    user_pool_id = os.environ.get('USER_POOL_ID')
    client_id = os.environ.get('CLIENT_ID')
    
    if not user_pool_id or not client_id:
        raise Exception("USER_POOL_ID or CLIENT_ID environment variable not set")
    
    # Build the public key
    public_key = jwk.construct(key)
    
    # Verify the token
    try:
        # Decode and verify the token
        claims = jwt.decode(
            token,
            public_key,
            algorithms=['RS256'],
            audience=client_id,
            issuer=f'https://cognito-idp.{region}.amazonaws.com/{user_pool_id}'
        )
        return claims
    except Exception as e:
        logger.error(f"Token verification failed: {str(e)}")
        raise Exception(f"Invalid token: {str(e)}")

def check_tenant_access(user_id, tenant_id):
    """Check if user has access to the specified tenant"""
    try:
        # Get tenant_users table name from environment
        table_name = os.environ.get('TENANT_TABLE', f"tenant-users-{os.environ.get('ENV', 'dev')}")
        table = dynamodb.Table(table_name)
        
        # Query for user's tenant access
        response = table.get_item(
            Key={
                'UserId': user_id,
                'TenantId': tenant_id
            }
        )
        
        # User has access if the item exists
        return 'Item' in response
    except Exception as e:
        logger.error(f"Error checking tenant access: {str(e)}")
        return False

def extract_tenant_id(event):
    """Extract tenant_id from the event"""
    # Try to get from path parameters
    path_parameters = event.get('pathParameters') or {}
    if path_parameters.get('tenant_id'):
        return path_parameters.get('tenant_id')
    
    # Try to extract from body if present
    if event.get('body'):
        try:
            body = event['body']
            # Handle base64 encoding
            if event.get('isBase64Encoded', False):
                import base64
                body = base64.b64decode(body).decode('utf-8')
                
            # Parse as JSON
            if isinstance(body, str):
                body_json = json.loads(body)
                if body_json.get('tenant_id'):
                    return body_json.get('tenant_id')
        except Exception:
            pass
    
    # Try to get from query string parameters
    query_params = event.get('queryStringParameters') or {}
    if query_params.get('tenant_id'):
        return query_params.get('tenant_id')
    
    # Fallback: no tenant_id found
    return None

def handler(event, context):
    """Lambda authorizer handler"""
    logger.info(f"Authorizer event: {json.dumps(event)}")
    
    # Extract authorization token from header
    auth_header = event.get('headers', {}).get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        logger.error("No valid Authorization header found")
        return generate_policy(None, 'Deny', event.get('methodArn'), {})
    
    token = auth_header.replace('Bearer ', '')
    
    try:
        # Verify token
        claims = verify_token(token)
        
        # Extract user identity
        user_id = claims.get('sub')
        email = claims.get('email')
        
        # Extract tenant_id from request
        tenant_id = extract_tenant_id(event)
        
        # If tenant_id is found, verify user has access
        if tenant_id:
            has_access = check_tenant_access(user_id, tenant_id)
            if not has_access:
                logger.warning(f"User {user_id} ({email}) denied access to tenant {tenant_id}")
                return generate_policy(user_id, 'Deny', event.get('methodArn'), claims)
        
        # Generate policy document for API Gateway
        return generate_policy(user_id, 'Allow', event.get('methodArn'), claims)
        
    except Exception as e:
        logger.error(f"Authorization failed: {str(e)}")
        return generate_policy(None, 'Deny', event.get('methodArn'), {})

def generate_policy(principal_id, effect, resource, claims):
    """Generate IAM policy document for API Gateway authorization"""
    auth_response = {
        'principalId': principal_id or 'unauthorized',
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        },
        'context': {
            'userId': principal_id or '',
            'email': claims.get('email', ''),
            'groups': ','.join(claims.get('cognito:groups', [])),
            'isAdmin': str(claims.get('custom:isAdmin', 'false')).lower() == 'true'
        }
    }
    
    return auth_response
