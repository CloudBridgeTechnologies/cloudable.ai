#!/usr/bin/env python3
"""
This script sets up the customer status tracking tables in the RDS database.
It creates tenant-specific tables and inserts sample data for testing.
"""

import argparse
import boto3
import datetime
import json
import os
import time
import uuid
from typing import Dict, List, Any, Optional

# Configure argument parser
parser = argparse.ArgumentParser(description='Set up customer status tracking tables in RDS')
parser.add_argument('--cluster-arn', required=True, help='RDS Cluster ARN')
parser.add_argument('--secret-arn', required=True, help='Secrets Manager ARN for RDS credentials')
parser.add_argument('--database', required=True, help='Database name')
parser.add_argument('--tenants', required=True, help='Comma-separated list of tenant IDs')
parser.add_argument('--sql-file', required=False, default='setup_customer_status_tables.sql',
                    help='SQL file with table definitions')

args = parser.parse_args()

# Initialize RDS Data API client - extract region from cluster ARN or use eu-west-1
import re
region_match = re.search(r':rds:([^:]+):', args.cluster_arn)
region = region_match.group(1) if region_match else 'eu-west-1'
rds_client = boto3.client('rds-data', region_name=region)

# Read SQL script
with open(args.sql_file, 'r') as file:
    sql_script = file.read()

# Function to execute SQL statement using RDS Data API
def execute_statement(sql: str, parameters: List[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Execute an SQL statement using the RDS Data API
    """
    try:
        response = rds_client.execute_statement(
            resourceArn=args.cluster_arn,
            secretArn=args.secret_arn,
            database=args.database,
            sql=sql,
            parameters=parameters or []
        )
        return response
    except Exception as e:
        print(f"Error executing SQL: {e}")
        print(f"SQL: {sql}")
        if parameters:
            print(f"Parameters: {parameters}")
        raise

# Function to insert sample customer data
def insert_sample_customers(tenant_id: str):
    """
    Insert sample customers for a specific tenant
    """
    # Sample customer data
    customers = []
    
    if tenant_id == 'acme':
        customers = [
            {
                'id': str(uuid.uuid4()),
                'name': 'ACME Manufacturing',
                'stage_id': 3,  # Implementation
                'start_date': '2025-09-15',
                'projected_date': '2025-12-10',
                'health_status': 'on_track',
                'progress': 42.5
            },
            {
                'id': str(uuid.uuid4()),
                'name': 'ACME Distribution',
                'stage_id': 2,  # Planning
                'start_date': '2025-10-01',
                'projected_date': '2026-03-15',
                'health_status': 'at_risk',
                'progress': 18.0
            }
        ]
        
        milestones = [
            {
                'customer_index': 0,
                'name': 'ERP Integration Complete',
                'description': 'Integration with SAP ERP system',
                'planned_date': '2025-10-30',
                'status': 'completed'
            },
            {
                'customer_index': 0,
                'name': 'User Training Phase 1',
                'description': 'Train administrators and power users',
                'planned_date': '2025-11-15',
                'status': 'in_progress'
            },
            {
                'customer_index': 0,
                'name': 'Supply Chain Module Deployment',
                'description': 'Deploy and configure supply chain modules',
                'planned_date': '2025-11-30',
                'status': 'pending'
            },
            {
                'customer_index': 1,
                'name': 'Requirements Gathering',
                'description': 'Document detailed requirements',
                'planned_date': '2025-10-15',
                'status': 'in_progress'
            }
        ]
        
    elif tenant_id == 'globex':
        customers = [
            {
                'id': str(uuid.uuid4()),
                'name': 'Globex Financial Services',
                'stage_id': 1,  # Discovery
                'start_date': '2025-10-01',
                'projected_date': '2026-06-15',
                'health_status': 'on_track',
                'progress': 12.0
            },
            {
                'id': str(uuid.uuid4()),
                'name': 'Globex Insurance',
                'stage_id': 4,  # Integration
                'start_date': '2025-08-01',
                'projected_date': '2025-12-20',
                'health_status': 'delayed',
                'progress': 65.0
            }
        ]
        
        milestones = [
            {
                'customer_index': 0,
                'name': 'Stakeholder Interviews',
                'description': 'Interview department leaders',
                'planned_date': '2025-10-20',
                'status': 'in_progress'
            },
            {
                'customer_index': 0,
                'name': 'Technical Assessment',
                'description': 'Evaluate current systems',
                'planned_date': '2025-11-05',
                'status': 'pending'
            },
            {
                'customer_index': 1,
                'name': 'CRM Integration',
                'description': 'Integrate with Salesforce',
                'planned_date': '2025-10-15',
                'status': 'completed'
            },
            {
                'customer_index': 1,
                'name': 'API Gateway Setup',
                'description': 'Configure secure API endpoints',
                'planned_date': '2025-10-30',
                'status': 'in_progress'
            },
            {
                'customer_index': 1,
                'name': 'Legacy System Migration',
                'description': 'Migrate data from legacy systems',
                'planned_date': '2025-11-15',
                'status': 'at_risk'
            }
        ]
    
    # Insert customers
    for customer in customers:
        # Convert UUID string to UUID type for PostgreSQL
        customer_id_param = {"name": "customer_id", "value": {"stringValue": customer['id']}}
        
        # Call the insert_sample_customer function
        execute_statement(
            f"SELECT customer_status.insert_sample_customer('{tenant_id}', :customer_id, :name, :stage_id, :start_date, :projected_date, :health_status, :progress);",
            [
                customer_id_param,
                {"name": "name", "value": {"stringValue": customer['name']}},
                {"name": "stage_id", "value": {"longValue": customer['stage_id']}},
                {"name": "start_date", "value": {"stringValue": customer['start_date']}},
                {"name": "projected_date", "value": {"stringValue": customer['projected_date']}},
                {"name": "health_status", "value": {"stringValue": customer['health_status']}},
                {"name": "progress", "value": {"doubleValue": customer['progress']}}
            ]
        )
        print(f"Inserted customer: {customer['name']} for tenant {tenant_id}")
    
    # Insert milestones
    for milestone in milestones:
        customer = customers[milestone['customer_index']]
        customer_id_param = {"name": "customer_id", "value": {"stringValue": customer['id']}}
        
        # Call the add_milestone function
        execute_statement(
            f"SELECT customer_status.add_milestone('{tenant_id}', :customer_id, :name, :description, :planned_date, :status);",
            [
                customer_id_param,
                {"name": "name", "value": {"stringValue": milestone['name']}},
                {"name": "description", "value": {"stringValue": milestone['description']}},
                {"name": "planned_date", "value": {"stringValue": milestone['planned_date']}},
                {"name": "status", "value": {"stringValue": milestone['status']}}
            ]
        )
        print(f"Added milestone: {milestone['name']} for {customer['name']}")
    
    return len(customers)

# Main execution
def main():
    # Split tenant list
    tenant_list = [t.strip() for t in args.tenants.split(',')]
    
    print(f"Setting up customer status tracking for tenants: {tenant_list}")
    
    # Execute the SQL script to create functions
    for statement in sql_script.split(';'):
        if statement.strip():
            execute_statement(statement)
    print("Created database functions for customer status tracking")
    
    # Set up tables for each tenant
    for tenant in tenant_list:
        print(f"\nSetting up tables for tenant: {tenant}")
        
        # Create tables for this tenant
        execute_statement(f"SELECT customer_status.create_tenant_tables('{tenant}');")
        print(f"Created tables for tenant: {tenant}")
        
        # Seed implementation stages
        execute_statement(f"SELECT customer_status.seed_implementation_stages('{tenant}');")
        print(f"Seeded implementation stages for tenant: {tenant}")
        
        # Create status view
        execute_statement(f"SELECT customer_status.create_status_view('{tenant}');")
        print(f"Created status view for tenant: {tenant}")
        
        # Insert sample customers with milestones
        customer_count = insert_sample_customers(tenant)
        print(f"Inserted {customer_count} sample customers for tenant: {tenant}")
    
    print("\nCustomer status tracking setup complete!")
    
if __name__ == "__main__":
    main()
