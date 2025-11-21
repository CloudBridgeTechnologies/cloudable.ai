#!/usr/bin/env python3
"""
Test PGVector functionality with RDS PostgreSQL
This script tests vector similarity search on the configured database.
"""
import boto3
import json
import sys
import argparse
import numpy as np
import time

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

def generate_random_embedding(dim=1536):
    """Generate a random embedding vector and normalize it"""
    embedding = np.random.randn(dim)
    embedding = embedding / np.linalg.norm(embedding)  # Normalize to unit vector
    return embedding.tolist()

def insert_test_vectors(rds_client, cluster_arn, secret_arn, database, tenant, count=10):
    """Insert test vectors into the database"""
    print(f"Inserting {count} test vectors for tenant {tenant}...")
    
    # First, check the data type of the ID column
    schema_sql = f"""
    SELECT column_name, data_type, udt_name
    FROM information_schema.columns
    WHERE table_name = 'kb_vectors_{tenant}'
    AND column_name = 'id';
    """
    
    schema_result = execute_sql(rds_client, cluster_arn, secret_arn, database, schema_sql)
    if not schema_result or not schema_result.get('records'):
        print("  ✗ Could not determine ID column type")
        return
    
    id_type = schema_result['records'][0][1]['stringValue'].lower()
    print(f"  ℹ ID column type: {id_type}")
    
    # Proceed with insertions
    for i in range(count):
        embedding = generate_random_embedding()
        
        # Create ID based on column type
        if 'uuid' in id_type:
            # Generate a proper UUID
            import uuid
            doc_id = str(uuid.uuid4())
            id_param = {'name': 'id', 'value': {'stringValue': doc_id}}
            id_sql = 'uuid(:id)'
        else:
            # Use string ID
            doc_id = f"test-doc-{i}"
            id_param = {'name': 'id', 'value': {'stringValue': doc_id}}
            id_sql = ':id'
        
        text = f"This is test document {i} with some random content for vector similarity testing."
        metadata = json.dumps({
            "source": "test_pgvector.py",
            "category": "test",
            "document_id": f"doc-{i}",
            "timestamp": time.time()
        })
        
        # Convert embedding to a string representation for PostgreSQL array constructor
        embedding_str = '{' + ','.join([str(x) for x in embedding]) + '}'
        
        # Insert vector with the correct ID type
        sql = f"""
        INSERT INTO kb_vectors_{tenant} (id, embedding, chunk_text, metadata)
        VALUES ({id_sql}, :embedding::vector, :text, :metadata::jsonb)
        ON CONFLICT (id) DO UPDATE SET
          embedding = :embedding::vector,
          chunk_text = :text,
          metadata = :metadata::jsonb;
        """
        
        params = [
            id_param,
            {'name': 'embedding', 'value': {'stringValue': embedding_str}},
            {'name': 'text', 'value': {'stringValue': text}},
            {'name': 'metadata', 'value': {'stringValue': metadata}}
        ]
        
        result = execute_sql(rds_client, cluster_arn, secret_arn, database, sql, params)
        if result:
            print(f"  ✓ Inserted vector {i+1}/{count}")
        else:
            print(f"  ✗ Failed to insert vector {i+1}/{count}")
    
    print("Insertion complete!")

def test_vector_search(rds_client, cluster_arn, secret_arn, database, tenant):
    """Test vector similarity search"""
    print(f"\nTesting vector similarity search for tenant {tenant}...")
    
    # Generate a test query vector
    query_vector = generate_random_embedding()
    
    # Convert to string representation for PostgreSQL
    embedding_str = '{' + ','.join([str(x) for x in query_vector]) + '}'
    
    # Perform vector search
    search_sql = f"""
    SELECT id, chunk_text, 1 - (embedding <=> :embedding::vector) AS cosine_similarity
    FROM kb_vectors_{tenant}
    ORDER BY embedding <=> :embedding::vector
    LIMIT 5;
    """
    
    params = [
        {'name': 'embedding', 'value': {'stringValue': embedding_str}}
    ]
    
    start_time = time.time()
    result = execute_sql(rds_client, cluster_arn, secret_arn, database, search_sql, params)
    end_time = time.time()
    
    if not result:
        print("  ✗ Vector search failed")
        return
    
    print(f"  ✓ Vector search successful (took {(end_time - start_time)*1000:.2f}ms)")
    print("\nSearch results:")
    print("-" * 80)
    print(f"{'ID':<15} | {'Similarity':<10} | Text")
    print("-" * 80)
    
    for record in result.get('records', []):
        doc_id = record[0]['stringValue']
        text = record[1]['stringValue']
        similarity = float(record[2]['doubleValue'])
        print(f"{doc_id:<15} | {similarity:.6f} | {text[:50]}...")
    
    print("-" * 80)

def test_hybrid_search(rds_client, cluster_arn, secret_arn, database, tenant, search_term="random"):
    """Test hybrid search (vector + text)"""
    print(f"\nTesting hybrid search for tenant {tenant} with term '{search_term}'...")
    
    # Generate a test query vector
    query_vector = generate_random_embedding()
    
    # Convert to string representation for PostgreSQL
    embedding_str = '{' + ','.join([str(x) for x in query_vector]) + '}'
    
    # Perform hybrid search
    hybrid_sql = f"""
    SELECT id, chunk_text, 
           1 - (embedding <=> :embedding::vector) AS vector_similarity,
           ts_rank_cd(to_tsvector('simple', chunk_text), plainto_tsquery('simple', :search_term)) AS text_rank,
           (1 - (embedding <=> :embedding::vector)) * 0.7 + 
           ts_rank_cd(to_tsvector('simple', chunk_text), plainto_tsquery('simple', :search_term)) * 0.3 AS hybrid_score
    FROM kb_vectors_{tenant}
    WHERE to_tsvector('simple', chunk_text) @@ plainto_tsquery('simple', :search_term)
    ORDER BY hybrid_score DESC
    LIMIT 5;
    """
    
    params = [
        {'name': 'embedding', 'value': {'stringValue': embedding_str}},
        {'name': 'search_term', 'value': {'stringValue': search_term}}
    ]
    
    start_time = time.time()
    result = execute_sql(rds_client, cluster_arn, secret_arn, database, hybrid_sql, params)
    end_time = time.time()
    
    if not result or not result.get('records'):
        print("  ✗ Hybrid search returned no results")
        return
    
    print(f"  ✓ Hybrid search successful (took {(end_time - start_time)*1000:.2f}ms)")
    print("\nHybrid search results:")
    print("-" * 100)
    print(f"{'ID':<15} | {'Vector Sim':<10} | {'Text Rank':<10} | {'Hybrid Score':<12} | Text")
    print("-" * 100)
    
    for record in result.get('records', []):
        doc_id = record[0]['stringValue']
        text = record[1]['stringValue']
        vector_sim = float(record[2]['doubleValue'])
        text_rank = float(record[3]['doubleValue'])
        hybrid_score = float(record[4]['doubleValue'])
        print(f"{doc_id:<15} | {vector_sim:.6f} | {text_rank:.6f} | {hybrid_score:.6f} | {text[:40]}...")
    
    print("-" * 100)

def get_table_stats(rds_client, cluster_arn, secret_arn, database, tenant):
    """Get statistics about the vector table"""
    print(f"\nGetting table statistics for kb_vectors_{tenant}...")
    
    stats_sql = f"""
    SELECT 
      (SELECT COUNT(*) FROM kb_vectors_{tenant}) as vector_count,
      (SELECT COALESCE(AVG(LENGTH(chunk_text)), 0) FROM kb_vectors_{tenant}) as avg_text_length,
      pg_size_pretty(pg_relation_size('kb_vectors_{tenant}')) as table_size,
      pg_size_pretty(pg_relation_size('kb_vectors_{tenant}_embedding_idx')) as index_size;
    """
    
    result = execute_sql(rds_client, cluster_arn, secret_arn, database, stats_sql)
    
    if not result:
        print("  ✗ Failed to get table statistics")
        return
    
    # Handle different possible data types safely
    vector_count = int(result['records'][0][0].get('longValue', 0))
    
    # Handle case where avg_text_len might be null or a different type
    avg_field = result['records'][0][1]
    if 'doubleValue' in avg_field:
        avg_text_len = float(avg_field['doubleValue'])
    elif 'longValue' in avg_field:
        avg_text_len = float(avg_field['longValue'])
    else:
        avg_text_len = 0.0
        
    table_size = result['records'][0][2]['stringValue']
    index_size = result['records'][0][3]['stringValue']
    
    print("\nTable Statistics:")
    print("-" * 60)
    print(f"Total vectors:       {vector_count}")
    print(f"Avg text length:     {avg_text_len:.2f} chars")
    print(f"Table size:          {table_size}")
    print(f"Vector index size:   {index_size}")
    print("-" * 60)

def main():
    parser = argparse.ArgumentParser(description='Test pgvector with RDS PostgreSQL')
    parser.add_argument('--cluster-arn', required=True, help='RDS Cluster ARN')
    parser.add_argument('--secret-arn', required=True, help='Secrets Manager ARN for DB credentials')
    parser.add_argument('--database', default='cloudable', help='Database name')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--tenant', default='acme', help='Tenant to test with')
    parser.add_argument('--insert', action='store_true', help='Insert test vectors')
    parser.add_argument('--count', type=int, default=10, help='Number of test vectors to insert')
    parser.add_argument('--search-term', default='random', help='Text search term for hybrid search')
    args = parser.parse_args()

    rds_client = boto3.client('rds-data', region_name=args.region)

    print(f"Testing pgvector on database {args.database}, tenant {args.tenant}")
    
    # Get table stats before insertion
    get_table_stats(rds_client, args.cluster_arn, args.secret_arn, args.database, args.tenant)
    
    # Insert test vectors if requested
    if args.insert:
        insert_test_vectors(rds_client, args.cluster_arn, args.secret_arn, args.database, args.tenant, args.count)
        # Get updated stats
        get_table_stats(rds_client, args.cluster_arn, args.secret_arn, args.database, args.tenant)
    
    # Test vector similarity search
    test_vector_search(rds_client, args.cluster_arn, args.secret_arn, args.database, args.tenant)
    
    # Test hybrid search
    test_hybrid_search(rds_client, args.cluster_arn, args.secret_arn, args.database, args.tenant, args.search_term)
    
    print("\nTesting complete!")

if __name__ == "__main__":
    main()
