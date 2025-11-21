#!/usr/bin/env python3
"""
Tenant Role-Based Access Control (RBAC) module for Cloudable.AI

This module provides functions for:
1. Defining roles and permissions within each tenant
2. Validating user access to specific operations
3. Managing tenant-level authorization
"""

import json
import logging
import os
from typing import Dict, List, Optional, Set, Union

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Define permission constants
class Permission:
    # Knowledge Base permissions
    KB_READ = "kb:read"
    KB_WRITE = "kb:write"
    KB_ADMIN = "kb:admin"
    
    # Document permissions
    DOC_READ = "doc:read"
    DOC_WRITE = "doc:write"
    DOC_ADMIN = "doc:admin"
    
    # Chat permissions
    CHAT_USE = "chat:use"
    CHAT_ADMIN = "chat:admin"
    
    # Analytics permissions
    ANALYTICS_VIEW = "analytics:view"
    ANALYTICS_ADMIN = "analytics:admin"
    
    # Admin permissions
    TENANT_ADMIN = "tenant:admin"
    USER_ADMIN = "user:admin"

# Define standard roles with their permissions
DEFAULT_ROLES = {
    "reader": {
        "description": "Can read KB and documents, use chat",
        "permissions": [
            Permission.KB_READ,
            Permission.DOC_READ,
            Permission.CHAT_USE
        ]
    },
    "contributor": {
        "description": "Can read/write KB and documents, use chat",
        "permissions": [
            Permission.KB_READ,
            Permission.KB_WRITE,
            Permission.DOC_READ,
            Permission.DOC_WRITE,
            Permission.CHAT_USE
        ]
    },
    "analyst": {
        "description": "Can read KB and documents, use chat, view analytics",
        "permissions": [
            Permission.KB_READ,
            Permission.DOC_READ,
            Permission.CHAT_USE,
            Permission.ANALYTICS_VIEW
        ]
    },
    "admin": {
        "description": "Full access to all tenant resources",
        "permissions": [
            Permission.KB_READ,
            Permission.KB_WRITE,
            Permission.KB_ADMIN,
            Permission.DOC_READ,
            Permission.DOC_WRITE,
            Permission.DOC_ADMIN,
            Permission.CHAT_USE,
            Permission.CHAT_ADMIN,
            Permission.ANALYTICS_VIEW,
            Permission.ANALYTICS_ADMIN,
            Permission.USER_ADMIN
        ]
    },
    "tenant_owner": {
        "description": "Tenant owner with full access including tenant administration",
        "permissions": [
            Permission.KB_READ,
            Permission.KB_WRITE,
            Permission.KB_ADMIN,
            Permission.DOC_READ,
            Permission.DOC_WRITE,
            Permission.DOC_ADMIN,
            Permission.CHAT_USE,
            Permission.CHAT_ADMIN,
            Permission.ANALYTICS_VIEW,
            Permission.ANALYTICS_ADMIN,
            Permission.USER_ADMIN,
            Permission.TENANT_ADMIN
        ]
    }
}

# In-memory cache for tenant roles and user assignments
# In production, this would be stored in a database
_tenant_roles = {}
_user_roles = {}

def get_tenant_roles(tenant_id: str) -> Dict:
    """Get roles defined for a specific tenant"""
    if tenant_id not in _tenant_roles:
        # Initialize with default roles
        _tenant_roles[tenant_id] = DEFAULT_ROLES.copy()
    
    return _tenant_roles[tenant_id]

def create_custom_role(tenant_id: str, role_name: str, description: str, permissions: List[str]) -> Dict:
    """Create a custom role for a tenant"""
    tenant_roles = get_tenant_roles(tenant_id)
    
    # Create the new role
    tenant_roles[role_name] = {
        "description": description,
        "permissions": permissions
    }
    
    return tenant_roles[role_name]

def assign_role_to_user(tenant_id: str, user_id: str, role_name: str) -> bool:
    """Assign a role to a user within a tenant"""
    tenant_roles = get_tenant_roles(tenant_id)
    
    # Check if role exists
    if role_name not in tenant_roles:
        logger.warning(f"Role '{role_name}' does not exist for tenant '{tenant_id}'")
        return False
    
    # Initialize user role dictionary if needed
    if user_id not in _user_roles:
        _user_roles[user_id] = {}
    
    # Assign role to user for this tenant
    _user_roles[user_id][tenant_id] = role_name
    
    logger.info(f"Assigned role '{role_name}' to user '{user_id}' in tenant '{tenant_id}'")
    return True

def get_user_permissions(tenant_id: str, user_id: str) -> Set[str]:
    """Get all permissions a user has within a tenant"""
    # Check if user has any roles
    if user_id not in _user_roles or tenant_id not in _user_roles[user_id]:
        logger.warning(f"User '{user_id}' has no role in tenant '{tenant_id}'")
        return set()
    
    role_name = _user_roles[user_id][tenant_id]
    tenant_roles = get_tenant_roles(tenant_id)
    
    if role_name not in tenant_roles:
        logger.error(f"Role '{role_name}' assigned to user '{user_id}' does not exist in tenant '{tenant_id}'")
        return set()
    
    return set(tenant_roles[role_name]["permissions"])

def check_permission(tenant_id: str, user_id: str, required_permission: str) -> bool:
    """Check if a user has a specific permission within a tenant"""
    user_permissions = get_user_permissions(tenant_id, user_id)
    
    # Check for the specific permission or admin permission
    has_permission = (
        required_permission in user_permissions or
        Permission.TENANT_ADMIN in user_permissions
    )
    
    # Determine the resource type from the permission
    if ":" in required_permission:
        resource_type = required_permission.split(":")[0]
        admin_permission = f"{resource_type}:admin"
        
        # Check if user has admin permission for this resource type
        has_permission = has_permission or (admin_permission in user_permissions)
    
    if not has_permission:
        logger.warning(f"Permission denied: User '{user_id}' lacks '{required_permission}' in tenant '{tenant_id}'")
    
    return has_permission

def validate_api_access(event: Dict, context: Optional[object] = None) -> Dict:
    """
    Validate user access to API based on JWT token and permissions
    
    Returns a dict with:
    - is_authorized: Boolean indicating authorization status
    - tenant_id: Extracted tenant ID
    - user_id: Extracted user ID
    - error: Error message if not authorized
    """
    result = {
        "is_authorized": False,
        "tenant_id": None,
        "user_id": None,
        "error": None
    }
    
    try:
        # In a real implementation, we would extract tenant_id and user_id from:
        # 1. JWT tokens in the Authorization header
        # 2. API Gateway context/authorizer
        # 3. Cognito user pools
        
        # For demonstration, we extract from headers or query parameters
        headers = event.get('headers', {}) or {}
        query_params = event.get('queryStringParameters', {}) or {}
        
        # Extract from body if present
        body = {}
        if 'body' in event:
            if isinstance(event['body'], str):
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    pass
            elif isinstance(event['body'], dict):
                body = event['body']
        
        # Get tenant_id from different possible sources
        tenant_id = (
            headers.get('x-tenant-id') or
            query_params.get('tenant') or
            body.get('tenant')
        )
        
        if not tenant_id:
            result["error"] = "Missing tenant ID"
            return result
        
        # Get user_id from different possible sources
        user_id = (
            headers.get('x-user-id') or
            query_params.get('user') or
            body.get('user_id') or
            "default-user-id"  # For testing only
        )
        
        if not user_id:
            result["error"] = "Missing user ID"
            return result
        
        # Get the required permission based on the API path and method
        required_permission = _get_required_permission(event)
        
        # Check if the user has the required permission
        if required_permission and not check_permission(tenant_id, user_id, required_permission):
            result["error"] = f"User lacks required permission: {required_permission}"
            return result
        
        # If we get here, the user is authorized
        result["is_authorized"] = True
        result["tenant_id"] = tenant_id
        result["user_id"] = user_id
        
        return result
    
    except Exception as e:
        logger.error(f"Error in validate_api_access: {str(e)}")
        result["error"] = "Internal authorization error"
        return result

def _get_required_permission(event: Dict) -> Optional[str]:
    """
    Determine the required permission based on API path and method
    
    This is a simplified example - in production, you would use a more
    sophisticated mapping of API paths to permissions, possibly from a
    configuration file or database.
    """
    # Extract path and method
    path = event.get('path', '')
    method = event.get('httpMethod', '')
    
    # For API Gateway HTTP API integrations
    if 'requestContext' in event and 'http' in event['requestContext']:
        path = event['requestContext']['http'].get('path', path)
        method = event['requestContext']['http'].get('method', method)
    
    # Define permission mappings
    if path.endswith('/health'):
        # Health check endpoint - no auth required
        return None
    
    if path.endswith('/upload-url'):
        return Permission.DOC_WRITE
    
    if path.endswith('/kb/sync'):
        return Permission.KB_WRITE
    
    if path.endswith('/kb/query'):
        return Permission.KB_READ
    
    if path.endswith('/chat'):
        return Permission.CHAT_USE
    
    # Default - require admin permission if path is not recognized
    return Permission.TENANT_ADMIN
