#!/usr/bin/env python3
"""
Simple script to set up customer status tables using RDS Data API
"""

import boto3
import sys
import os

# Get parameters from environment or command line
RDS_CLUSTER_ARN = os.environ.get('RDS_CLUSTER_ARN') or sys.argv[1] if len(sys.argv) > 1 else None
RDS_SECRET_ARN = os.environ.get('RDS_SECRET_ARN') or sys.argv[2] if len(sys.argv) > 2 else None
RDS_DATABASE = os.environ.get('RDS_DATABASE', 'cloudable')
AWS_REGION = os.environ.get('AWS_REGION', 'eu-west-1')

if not RDS_CLUSTER_ARN or not RDS_SECRET_ARN:
    print("Usage: python3 setup_customer_status_simple.py <RDS_CLUSTER_ARN> <RDS_SECRET_ARN>")
    print("Or set environment variables: RDS_CLUSTER_ARN, RDS_SECRET_ARN")
    sys.exit(1)

rds_client = boto3.client('rds-data', region_name=AWS_REGION)

def execute_sql(sql):
    """Execute SQL statement"""
    try:
        response = rds_client.execute_statement(
            resourceArn=RDS_CLUSTER_ARN,
            secretArn=RDS_SECRET_ARN,
            database=RDS_DATABASE,
            sql=sql
        )
        return response
    except Exception as e:
        print(f"Error: {e}")
        print(f"SQL: {sql[:200]}...")
        raise

# Create schema
print("Creating customer_status schema...")
execute_sql('CREATE SCHEMA IF NOT EXISTS customer_status;')
print("✓ Schema created")

# For each tenant, create tables and views
for tenant in ['acme', 'globex']:
    print(f"\nSetting up tables for tenant: {tenant}")
    
    # Create customers table
    execute_sql(f'''
        CREATE TABLE IF NOT EXISTS customer_status.customers_{tenant} (
            customer_id TEXT PRIMARY KEY,
            customer_name TEXT NOT NULL,
            current_stage TEXT,
            status_summary TEXT,
            last_updated TIMESTAMPTZ DEFAULT NOW()
        );
    ''')
    print(f"  ✓ Created customers_{tenant} table")
    
    # Create customer_milestones table
    execute_sql(f'''
        CREATE TABLE IF NOT EXISTS customer_status.customer_milestones_{tenant} (
            milestone_id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            milestone_name TEXT NOT NULL,
            status TEXT,
            completion_date TIMESTAMPTZ,
            notes TEXT
        );
    ''')
    print(f"  ✓ Created customer_milestones_{tenant} table")
    
    # Create view (simplified)
    execute_sql(f'''
        CREATE OR REPLACE VIEW customer_status.customer_status_view_{tenant} AS
        SELECT 
            c.customer_id,
            c.customer_name,
            c.current_stage as stage_name,
            CASE 
                WHEN c.current_stage = 'Discovery' THEN 1
                WHEN c.current_stage = 'Onboarding' THEN 2
                WHEN c.current_stage = 'Implementation' THEN 3
                WHEN c.current_stage = 'Testing' THEN 4
                WHEN c.current_stage = 'Go-Live' THEN 5
                ELSE 0
            END as stage_order,
            c.status_summary,
            c.last_updated
        FROM customer_status.customers_{tenant} c;
    ''')
    print(f"  ✓ Created customer_status_view_{tenant} view")
    
    # Insert sample data
    execute_sql(f'''
        INSERT INTO customer_status.customers_{tenant} (customer_id, customer_name, current_stage, status_summary)
        VALUES ('{tenant}-001', '{tenant.upper()} Corporation', 'Implementation', 'Active implementation in progress')
        ON CONFLICT (customer_id) DO NOTHING;
    ''')
    print(f"  ✓ Inserted sample data for {tenant}")

print("\n✓ Customer status setup complete!")
