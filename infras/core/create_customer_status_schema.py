#!/usr/bin/env python3
"""
Script to create the customer_status schema in the RDS database
"""

import argparse
import boto3
import time
from botocore.exceptions import ClientError

def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(description='Create customer_status schema in RDS')
    parser.add_argument('--cluster-arn', required=True, help='RDS cluster ARN')
    parser.add_argument('--secret-arn', required=True, help='RDS secret ARN')
    parser.add_argument('--database', required=True, help='RDS database name')
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
        
        if response['records'][0][0].get('booleanValue', False):
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

def main():
    """Main function"""
    args = parse_args()
    
    # Initialize RDS Data API client
    rds_client = boto3.client('rds-data')
    
    print(f"Creating schema for RDS cluster: {args.cluster_arn}")
    
    # Create schema
    success = create_schema(rds_client, args.cluster_arn, args.secret_arn, args.database)
    
    if success:
        print("Schema creation completed successfully")
    else:
        print("Schema creation failed")
        exit(1)

if __name__ == '__main__':
    main()
