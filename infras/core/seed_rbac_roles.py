#!/usr/bin/env python3
"""
This script seeds initial RBAC roles and user assignments for testing.
"""

import logging
import tenant_rbac

# Configure logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def main():
    """Seed initial RBAC roles and user assignments"""
    logger.info("Seeding RBAC roles and user assignments for testing...")
    
    # Define test tenants
    tenants = ["acme", "globex", "initech", "umbrella"]
    
    # Define test users
    admin_users = ["user-admin-001", "user-admin-002"]
    reader_users = ["user-reader-001", "user-reader-002"]
    writer_users = ["user-writer-001", "user-writer-002"]
    analyst_users = ["user-analyst-001"]
    
    # Assign roles for each tenant
    for tenant in tenants:
        logger.info(f"Setting up roles for tenant: {tenant}")
        
        # Assign admin roles
        for user in admin_users:
            tenant_rbac.assign_role_to_user(tenant, user, "admin")
            logger.info(f"Assigned 'admin' role to {user} in {tenant}")
        
        # Assign reader roles
        for user in reader_users:
            tenant_rbac.assign_role_to_user(tenant, user, "reader")
            logger.info(f"Assigned 'reader' role to {user} in {tenant}")
        
        # Assign contributor (writer) roles
        for user in writer_users:
            tenant_rbac.assign_role_to_user(tenant, user, "contributor")
            logger.info(f"Assigned 'contributor' role to {user} in {tenant}")
        
        # Assign analyst roles
        for user in analyst_users:
            tenant_rbac.assign_role_to_user(tenant, user, "analyst")
            logger.info(f"Assigned 'analyst' role to {user} in {tenant}")
        
        # Verify role assignments
        for user in admin_users:
            permissions = tenant_rbac.get_user_permissions(tenant, user)
            logger.info(f"User {user} has {len(permissions)} permissions in {tenant}")
            
            # Check if user has admin permission
            has_admin = tenant_rbac.check_permission(tenant, user, tenant_rbac.Permission.TENANT_ADMIN)
            logger.info(f"User {user} has admin permission: {has_admin}")
    
    logger.info("RBAC roles and user assignments seeded successfully")

if __name__ == "__main__":
    main()
