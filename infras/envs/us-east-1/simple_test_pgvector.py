#!/usr/bin/env python3
"""
Simple test for pgvector in PostgreSQL
Tests basic vector operations without complex Lambda interactions
"""
import boto3
import json
import sys
import argparse
import numpy as np
import time
import uuid

def execute_sql(rds_client, cluster_arn, secret_arn, database, sql, params=None):
    """Execute SQL statement using RDS Data API"""
    try:
        kwargs = {
            'resourceArn': cluster_arn,
            'secretArn': secret_arn,
            'database': database,
            'sql': sql
        }
        if params:
            kwargs['parameters'] = params
            
        response = rds_client.execute_statement(**kwargs)
        return response
    except Exception as e:
        print(f"Error executing SQL: {e}")
        return None

def check_pgvector_enabled(rds_client, cluster_arn, secret_arn, database):
    """Check if pgvector extension is enabled"""
    sql = "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
    result = execute_sql(rds_client, cluster_arn, secret_arn, database, sql)
    
    if not result or not result.get('records'):
        return False
    
    version = result['records'][0][1]['stringValue']
    print(f"✓ pgvector extension enabled (version {version})")
    return True

def generate_random_vector(dim=3):
    """Generate a small random vector for testing"""
    vec = np.random.randn(dim)
    vec = vec / np.linalg.norm(vec)
    return vec.tolist()

def test_vector_operations(rds_client, cluster_arn, secret_arn, database):
    """Test basic vector operations in PostgreSQL"""
    print("\nTesting vector operations...")
    
    # Create a test table
    test_table = f"pgvector_test_{uuid.uuid4().hex[:8]}"
    create_sql = f"""
    CREATE TABLE {test_table} (
        id serial PRIMARY KEY,
        v vector(3)
    );
    """
    result = execute_sql(rds_client, cluster_arn, secret_arn, database, create_sql)
    if not result:
        print("✗ Failed to create test table")
        return False
    print(f"✓ Created test table: {test_table}")
    
    try:
        # Insert test vectors
        vectors = [generate_random_vector() for _ in range(3)]
        for i, vec in enumerate(vectors):
            # Format the vector with brackets, not braces, for PostgreSQL
            vec_str = '[' + ','.join([str(x) for x in vec]) + ']'
            insert_sql = f"INSERT INTO {test_table} (v) VALUES ('{vec_str}'::vector);"
            result = execute_sql(rds_client, cluster_arn, secret_arn, database, insert_sql)
            if not result:
                print(f"✗ Failed to insert vector {i+1}")
                return False
            print(f"✓ Inserted vector {i+1}: {vec_str}")
        
        # Test vector operations
        query_vec = vectors[0]  # Use the first vector as the query vector
        query_vec_str = '[' + ','.join([str(x) for x in query_vec]) + ']'
        
        # Test L2 distance
        l2_sql = f"SELECT id, v, v <-> '{query_vec_str}'::vector AS distance FROM {test_table} ORDER BY v <-> '{query_vec_str}'::vector LIMIT 2;"
        result = execute_sql(rds_client, cluster_arn, secret_arn, database, l2_sql)
        if not result:
            print("✗ Failed to execute L2 distance query")
            return False
        
        print("\nL2 distance results:")
        for row in result['records']:
            id_val = row[0]['longValue']
            distance = row[2]['doubleValue']
            print(f"  ID: {id_val}, Distance: {distance}")
        
        # Test cosine distance
        cosine_sql = f"SELECT id, v, v <=> '{query_vec_str}'::vector AS cosine_distance FROM {test_table} ORDER BY v <=> '{query_vec_str}'::vector LIMIT 2;"
        result = execute_sql(rds_client, cluster_arn, secret_arn, database, cosine_sql)
        if not result:
            print("✗ Failed to execute cosine distance query")
            return False
        
        print("\nCosine distance results:")
        for row in result['records']:
            id_val = row[0]['longValue']
            distance = row[2]['doubleValue']
            print(f"  ID: {id_val}, Distance: {distance}")
        
        # Test inner product
        inner_sql = f"SELECT id, v, v <#> '{query_vec_str}'::vector AS inner_product FROM {test_table} ORDER BY v <#> '{query_vec_str}'::vector LIMIT 2;"
        result = execute_sql(rds_client, cluster_arn, secret_arn, database, inner_sql)
        if not result:
            print("✗ Failed to execute inner product query")
            return False
        
        print("\nInner product results:")
        for row in result['records']:
            id_val = row[0]['longValue']
            distance = row[2]['doubleValue']
            print(f"  ID: {id_val}, Distance: {distance}")
        
        return True
    finally:
        # Clean up
        print("\nCleaning up...")
        drop_sql = f"DROP TABLE IF EXISTS {test_table};"
        execute_sql(rds_client, cluster_arn, secret_arn, database, drop_sql)
        print(f"✓ Dropped test table: {test_table}")

def main():
    parser = argparse.ArgumentParser(description='Simple test for pgvector in PostgreSQL')
    parser.add_argument('--cluster-arn', required=True, help='RDS Cluster ARN')
    parser.add_argument('--secret-arn', required=True, help='Secrets Manager ARN for DB credentials')
    parser.add_argument('--database', default='cloudable', help='Database name')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    args = parser.parse_args()

    rds_client = boto3.client('rds-data', region_name=args.region)

    print(f"Testing pgvector on database {args.database}")
    
    # Check if pgvector is enabled
    if not check_pgvector_enabled(rds_client, args.cluster_arn, args.secret_arn, args.database):
        print("✗ pgvector extension not enabled")
        sys.exit(1)
    
    # Test vector operations
    if test_vector_operations(rds_client, args.cluster_arn, args.secret_arn, args.database):
        print("\n✓ All pgvector tests passed!")
    else:
        print("\n✗ Some pgvector tests failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
