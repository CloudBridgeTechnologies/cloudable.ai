#!/usr/bin/env python3
"""
Setup pgvector extension and tables for Bedrock Knowledge Base on Aurora PostgreSQL
This script enables pgvector and creates the necessary tables for vector storage.
"""
import boto3
import json
import sys
import argparse

def get_secret(secret_name, region):
    """Retrieve secret from AWS Secrets Manager"""
    client = boto3.client('secretsmanager', region_name=region)
    try:
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        sys.exit(1)

def execute_sql(rds_client, cluster_arn, secret_arn, database, sql):
    """Execute SQL statement using RDS Data API"""
    try:
        response = rds_client.execute_statement(
            resourceArn=cluster_arn,
            secretArn=secret_arn,
            database=database,
            sql=sql
        )
        return response
    except Exception as e:
        print(f"Error executing SQL: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description='Setup pgvector on Aurora PostgreSQL')
    parser.add_argument('--cluster-arn', required=True, help='RDS Cluster ARN')
    parser.add_argument('--secret-arn', required=True, help='Secrets Manager ARN for DB credentials')
    parser.add_argument('--database', default='cloudable', help='Database name')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--tenants', nargs='+', default=['acme', 'globex'], help='List of tenant names')
    parser.add_argument('--index-type', choices=['ivfflat', 'hnsw'], default='hnsw', 
                        help='Vector index type: ivfflat (faster build) or hnsw (faster query)')
    args = parser.parse_args()

    rds_client = boto3.client('rds-data', region_name=args.region)

    print("Setting up pgvector extension and tables...")

    # Enable pgvector extension
    print("\n1. Enabling pgvector extension...")
    sql = "CREATE EXTENSION IF NOT EXISTS vector;"
    result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, sql)
    if result:
        print("✓ pgvector extension enabled")
    
    # Enable UUID extension if not already enabled
    print("\n2. Enabling UUID extension...")
    sql = "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
    result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, sql)
    if result:
        print("✓ UUID extension enabled")

    # Create tables for each tenant
    for tenant in args.tenants:
        print(f"\n3. Creating table for tenant: {tenant}")
        
        # Create table
        create_table_sql = f"""
        CREATE TABLE IF NOT EXISTS kb_vectors_{tenant} (
            id TEXT PRIMARY KEY,
            embedding vector(1536),
            chunk_text TEXT NOT NULL,
            metadata JSONB,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
        """
        result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, create_table_sql)
        if result:
            print(f"✓ Table kb_vectors_{tenant} created")

        # Create vector index based on chosen type
        print(f"4. Creating {args.index_type} vector index for tenant: {tenant}")
        
        if args.index_type == 'ivfflat':
        create_index_sql = f"""
        CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_embedding_idx 
        ON kb_vectors_{tenant} 
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100);
        """
        else:  # HNSW index
            create_index_sql = f"""
            CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_embedding_idx 
            ON kb_vectors_{tenant} 
            USING hnsw (embedding vector_cosine_ops)
            WITH (m = 16, ef_construction = 64);
            """
            
        result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, create_index_sql)
        if result:
            print(f"✓ {args.index_type.upper()} vector index created for {tenant}")

        # Create text search index
        print(f"5. Creating text search index for tenant: {tenant}")
        create_text_index_sql = f"""
        CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_chunk_text_gin_idx
        ON kb_vectors_{tenant}
        USING gin (to_tsvector('simple', chunk_text));
        """
        result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, create_text_index_sql)
        if result:
            print(f"✓ Text search index created for {tenant}")
            
        # Create metadata search index
        print(f"6. Creating metadata search index for tenant: {tenant}")
        create_metadata_index_sql = f"""
        CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_metadata_gin_idx
        ON kb_vectors_{tenant}
        USING gin (metadata);
        """
        result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, create_metadata_index_sql)
        if result:
            print(f"✓ Metadata search index created for {tenant}")

    # Add useful maintenance functions
    print("\n7. Creating maintenance functions...")
    
    # Function to reindex the vector indices
    reindex_function_sql = """
    CREATE OR REPLACE FUNCTION reindex_kb_vectors() RETURNS void AS $$
    DECLARE
        index_rec RECORD;
    BEGIN
        FOR index_rec IN 
            SELECT indexname FROM pg_indexes 
            WHERE indexname LIKE 'kb_vectors_%_embedding_idx'
        LOOP
            EXECUTE 'REINDEX INDEX ' || index_rec.indexname;
            RAISE NOTICE 'Reindexed %', index_rec.indexname;
        END LOOP;
    END;
    $$ LANGUAGE plpgsql;
    """
    result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, reindex_function_sql)
    if result:
        print("✓ Created vector reindex function")
        
    # Function to get vector stats
    stats_function_sql = """
    CREATE OR REPLACE FUNCTION kb_vector_stats() RETURNS TABLE (
        tenant text,
        total_vectors bigint,
        avg_text_length numeric,
        index_size text
    ) AS $$
    DECLARE
        tenant_rec RECORD;
        tenant_name text;
    BEGIN
        FOR tenant_rec IN 
            SELECT table_name
            FROM information_schema.tables
            WHERE table_name LIKE 'kb_vectors_%'
        LOOP
            tenant_name := substring(tenant_rec.table_name from 12);
            RETURN QUERY EXECUTE format(
                'SELECT %L::text as tenant, 
                 COUNT(*)::bigint as total_vectors,
                 AVG(length(chunk_text))::numeric as avg_text_length,
                 pg_size_pretty(pg_relation_size(%L || ''_embedding_idx''))::text as index_size
                 FROM %I', 
                tenant_name, 
                tenant_rec.table_name,
                tenant_rec.table_name
            );
        END LOOP;
    END;
    $$ LANGUAGE plpgsql;
    """
    result = execute_sql(rds_client, args.cluster_arn, args.secret_arn, args.database, stats_function_sql)
    if result:
        print("✓ Created vector statistics function")

    print("\n✓ Setup complete! pgvector is ready for Bedrock Knowledge Base.")
    print("\nUseful database functions:")
    print("  - SELECT * FROM kb_vector_stats();")
    print("  - SELECT reindex_kb_vectors();")

if __name__ == "__main__":
    main()

