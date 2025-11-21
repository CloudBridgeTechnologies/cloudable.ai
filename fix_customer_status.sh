#!/bin/bash

# Script to fix customer status by creating the schema and tables

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  FIXING CUSTOMER STATUS API"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
echo -e "Using AWS Region: ${GREEN}$AWS_DEFAULT_REGION${NC}"

# Get the RDS cluster ARN
RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query "DBClusters[0].DBClusterArn" --output text)
if [ -z "$RDS_CLUSTER_ARN" ] || [ "$RDS_CLUSTER_ARN" == "None" ]; then
    echo -e "${RED}Failed to get RDS cluster ARN${NC}"
    exit 1
fi
echo -e "RDS Cluster ARN: ${GREEN}$RDS_CLUSTER_ARN${NC}"

# Get the RDS secret ARN
RDS_SECRET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'aurora-dev-admin')].ARN" --output text)
if [ -z "$RDS_SECRET_ARN" ] || [ "$RDS_SECRET_ARN" == "None" ]; then
    echo -e "${RED}Failed to get RDS secret ARN${NC}"
    exit 1
fi
echo -e "RDS Secret ARN: ${GREEN}$RDS_SECRET_ARN${NC}"

# Get the database name
RDS_DATABASE=$(aws lambda get-function-configuration --function-name kb-manager-dev-core --query "Environment.Variables.RDS_DATABASE" --output text)
if [ -z "$RDS_DATABASE" ] || [ "$RDS_DATABASE" == "None" ]; then
    echo -e "${YELLOW}RDS database name not found in Lambda environment, using default 'cloudable'${NC}"
    RDS_DATABASE="cloudable"
else
    echo -e "RDS Database: ${GREEN}$RDS_DATABASE${NC}"
fi

# Create a Python script to create the schema and tables
echo -e "\n${YELLOW}Creating Python script to set up customer status schema and tables...${NC}"

cat > setup_customer_status_schema.py << 'EOF'
#!/usr/bin/env python3
"""
Script to create the customer_status schema and tables
"""

import argparse
import boto3
import time
import json
from botocore.exceptions import ClientError

def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(description='Create customer_status schema and tables')
    parser.add_argument('--cluster-arn', required=True, help='RDS cluster ARN')
    parser.add_argument('--secret-arn', required=True, help='RDS secret ARN')
    parser.add_argument('--database', required=True, help='RDS database name')
    parser.add_argument('--tenants', required=True, help='Comma-separated list of tenants')
    return parser.parse_args()

def execute_statement(client, cluster_arn, secret_arn, database, sql, parameters=None):
    """Execute an SQL statement using the RDS Data API"""
    try:
        response = client.execute_statement(
            resourceArn=cluster_arn,
            secretArn=secret_arn,
            database=database,
            sql=sql,
            parameters=parameters or []
        )
        return response
    except ClientError as e:
        print(f"Error executing SQL: {e}")
        print(f"SQL: {sql}")
        if parameters:
            print(f"Parameters: {parameters}")
        raise

def create_schema(client, cluster_arn, secret_arn, database):
    """Create the customer_status schema"""
    try:
        # Check if schema exists
        check_sql = "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'customer_status');"
        response = execute_statement(client, cluster_arn, secret_arn, database, check_sql)
        
        schema_exists = False
        if response['records']:
            if 'booleanValue' in response['records'][0][0]:
                schema_exists = response['records'][0][0]['booleanValue']
        
        if schema_exists:
            print("Schema 'customer_status' already exists")
        else:
            # Create schema
            create_sql = "CREATE SCHEMA customer_status;"
            execute_statement(client, cluster_arn, secret_arn, database, create_sql)
            print("Schema 'customer_status' created successfully")
        return True
    except Exception as e:
        print(f"Error creating schema: {e}")
        return False

def create_tenant_tables(client, cluster_arn, secret_arn, database, tenant):
    """Create customer status tables for a specific tenant"""
    try:
        print(f"Creating tables for tenant: {tenant}")
        
        # Create customers table
        customers_table_sql = f"""
        CREATE TABLE IF NOT EXISTS customer_status.customers_{tenant} (
            customer_id TEXT PRIMARY KEY,
            customer_name TEXT NOT NULL,
            current_stage TEXT NOT NULL,
            status_summary TEXT,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """
        execute_statement(client, cluster_arn, secret_arn, database, customers_table_sql)
        print(f"Created customer_status.customers_{tenant} table")
        
        # Create customer_milestones table
        milestones_table_sql = f"""
        CREATE TABLE IF NOT EXISTS customer_status.customer_milestones_{tenant} (
            milestone_id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            milestone_name TEXT NOT NULL,
            status TEXT NOT NULL,
            planned_date DATE,
            completion_date DATE,
            notes TEXT,
            FOREIGN KEY (customer_id) REFERENCES customer_status.customers_{tenant}(customer_id)
        );
        """
        execute_statement(client, cluster_arn, secret_arn, database, milestones_table_sql)
        print(f"Created customer_status.customer_milestones_{tenant} table")
        
        # Create view for customer status
        view_sql = f"""
        CREATE OR REPLACE VIEW customer_status.customer_status_view_{tenant} AS
        SELECT 
            c.customer_id, 
            c.customer_name, 
            c.current_stage,
            CASE
                WHEN c.current_stage = 'Onboarding' THEN 1
                WHEN c.current_stage = 'Planning' THEN 2
                WHEN c.current_stage = 'Implementation' THEN 3
                WHEN c.current_stage = 'Testing' THEN 4
                WHEN c.current_stage = 'Go-Live' THEN 5
                WHEN c.current_stage = 'Post-Launch' THEN 6
                ELSE 99
            END AS stage_order,
            c.status_summary,
            c.last_updated
        FROM 
            customer_status.customers_{tenant} c;
        """
        execute_statement(client, cluster_arn, secret_arn, database, view_sql)
        print(f"Created customer_status_view_{tenant} view")
        
        # Insert sample data
        insert_customers_sql = f"""
        INSERT INTO customer_status.customers_{tenant} (customer_id, customer_name, current_stage, status_summary)
        VALUES 
            ('cust-001', 'ACME Corp', 'Implementation', 'Phase 3 of 5 in progress. On track for December completion.'),
            ('cust-002', 'TechInnovate', 'Planning', 'Requirements gathering completed. Solution design in progress.'),
            ('cust-003', 'Global Retail', 'Testing', 'Integration testing in progress. UAT scheduled for next month.')
        ON CONFLICT (customer_id) DO NOTHING;
        """
        execute_statement(client, cluster_arn, secret_arn, database, insert_customers_sql)
        print(f"Inserted sample customers for tenant {tenant}")
        
        insert_milestones_sql = f"""
        INSERT INTO customer_status.customer_milestones_{tenant} (milestone_id, customer_id, milestone_name, status, planned_date, completion_date, notes)
        VALUES 
            ('ms-001-001', 'cust-001', 'Project Kickoff', 'Completed', '2025-08-15', '2025-08-15', 'Successfully completed with all stakeholders'),
            ('ms-001-002', 'cust-001', 'Requirements Gathering', 'Completed', '2025-09-15', '2025-09-20', 'All requirements documented'),
            ('ms-001-003', 'cust-001', 'Solution Design', 'Completed', '2025-10-15', '2025-10-18', 'Architecture approved'),
            ('ms-001-004', 'cust-001', 'Implementation Phase 1', 'Completed', '2025-10-30', '2025-11-02', 'Core system implemented'),
            ('ms-001-005', 'cust-001', 'Implementation Phase 2', 'In Progress', '2025-11-15', NULL, 'Integration components in progress'),
            ('ms-001-006', 'cust-001', 'Implementation Phase 3', 'Planned', '2025-11-30', NULL, 'Final customizations'),
            ('ms-001-007', 'cust-001', 'Testing', 'Planned', '2025-12-15', NULL, 'Full system testing'),
            ('ms-001-008', 'cust-001', 'Go-Live', 'Planned', '2025-12-31', NULL, 'Production deployment')
        ON CONFLICT (milestone_id) DO NOTHING;
        """
        execute_statement(client, cluster_arn, secret_arn, database, insert_milestones_sql)
        print(f"Inserted sample milestones for tenant {tenant}")
        
        return True
    except Exception as e:
        print(f"Error creating tables for tenant {tenant}: {e}")
        return False

def main():
    """Main function"""
    args = parse_args()
    
    # Initialize RDS Data API client
    rds_client = boto3.client('rds-data', region_name='us-east-1')
    
    print(f"Setting up customer status for database: {args.database}")
    print(f"RDS Cluster ARN: {args.cluster_arn}")
    print(f"RDS Secret ARN: {args.secret_arn}")
    
    # Create schema
    schema_created = create_schema(rds_client, args.cluster_arn, args.secret_arn, args.database)
    if not schema_created:
        print("Failed to create schema, exiting")
        exit(1)
    
    # Create tables for each tenant
    tenants = args.tenants.split(',')
    print(f"Setting up tables for tenants: {tenants}")
    
    failures = 0
    for tenant in tenants:
        tenant = tenant.strip().lower()
        if not tenant:
            continue
        
        success = create_tenant_tables(rds_client, args.cluster_arn, args.secret_arn, args.database, tenant)
        if not success:
            failures += 1
    
    if failures > 0:
        print(f"Failed to create tables for {failures} tenant(s)")
        exit(1)
    else:
        print("All customer status tables created successfully")

if __name__ == '__main__':
    main()
EOF

chmod +x setup_customer_status_schema.py

# Run the script to create schema and tables
echo -e "\n${YELLOW}Creating customer status schema and tables...${NC}"
python3 setup_customer_status_schema.py \
    --cluster-arn "$RDS_CLUSTER_ARN" \
    --secret-arn "$RDS_SECRET_ARN" \
    --database "$RDS_DATABASE" \
    --tenants "acme,globex"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create schema and tables${NC}"
    exit 1
else
    echo -e "\n${GREEN}Customer status schema and tables created successfully${NC}"
fi

echo -e "\n${BLUE}=========================================================="
echo "  CUSTOMER STATUS API FIX COMPLETED"
echo -e "==========================================================${NC}"

# Provide next steps
echo -e "\nNext steps:"
echo -e "1. Test the customer status API"
echo -e "2. Fix Langfuse integration"
echo -e "3. Run comprehensive tests to verify all functionality"
