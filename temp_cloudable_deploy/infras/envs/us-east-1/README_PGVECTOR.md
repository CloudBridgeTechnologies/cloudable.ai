# PGVector Setup for Cloudable.AI

This directory contains scripts for setting up and testing pgvector with PostgreSQL for vector similarity search in Cloudable.AI.

## Overview

Cloudable.AI has migrated from OpenSearch Serverless to PostgreSQL with pgvector for vector storage and similarity search. This provides several benefits:

1. **Cost efficiency**: Uses existing RDS infrastructure rather than a dedicated vector database
2. **Simplified architecture**: Centralized data storage in a single database system
3. **Integrated querying**: Allows for hybrid search combining vector and traditional SQL queries
4. **Easier maintenance**: Leverages existing PostgreSQL expertise and tooling

## Scripts

The following scripts are provided:

1. **setup_pgvector.py**: Main script that sets up pgvector extension and tables
2. **setup_pgvector.sh**: Wrapper script to easily run setup_pgvector.py
3. **test_pgvector.py**: Test script for validating pgvector functionality
4. **test_pgvector.sh**: Wrapper script for running the test script

## Setup Instructions

### Prerequisites

- AWS CLI installed and configured
- Python 3.6+ with boto3 and numpy
- Access to the RDS PostgreSQL cluster
- Required IAM permissions:
  - RDS Data API access
  - Secrets Manager access

### Running the Setup Script

1. Execute the wrapper script with appropriate parameters:

```bash
chmod +x setup_pgvector.sh
./setup_pgvector.sh --region us-east-1 --tenants acme,globex,t001 --index-type hnsw
```

The script will:

1. Discover AWS resources automatically (or prompt if needed)
2. Enable the pgvector extension in PostgreSQL
3. Create vector tables for each tenant
4. Create optimized indexes for vector and text search
5. Set up maintenance functions

### Command-line Options

#### For setup_pgvector.sh:

- `--region`: AWS region (default: us-east-1)
- `--database`: Database name (default: cloudable)
- `--tenants`: Comma-separated list of tenant names (default: acme,globex,t001)
- `--index-type`: Type of vector index to create (options: ivfflat, hnsw; default: hnsw)

## Testing

After setup, verify the implementation using the test script:

```bash
chmod +x test_pgvector.sh
./test_pgvector.sh --tenant acme --insert --count 20
```

The test script will:

1. Insert test vectors if the `--insert` flag is provided
2. Run vector similarity searches
3. Perform hybrid text and vector searches
4. Display table statistics

### Command-line Options

#### For test_pgvector.sh:

- `--region`: AWS region (default: us-east-1)
- `--database`: Database name (default: cloudable)
- `--tenant`: Tenant name to test with (default: acme)
- `--insert`: Flag to insert test vectors
- `--count`: Number of test vectors to insert (default: 10)
- `--search-term`: Text search term for hybrid search (default: random)

## Vector Table Schema

```sql
CREATE TABLE IF NOT EXISTS kb_vectors_{tenant} (
    id TEXT PRIMARY KEY,
    embedding vector(1536),
    chunk_text TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Vector similarity index (HNSW)
CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_embedding_idx 
ON kb_vectors_{tenant} 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Text search index
CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_chunk_text_gin_idx
ON kb_vectors_{tenant}
USING gin (to_tsvector('simple', chunk_text));

-- Metadata search index
CREATE INDEX IF NOT EXISTS kb_vectors_{tenant}_metadata_gin_idx
ON kb_vectors_{tenant}
USING gin (metadata);
```

## Maintenance Functions

The setup script creates two helpful maintenance functions:

1. **reindex_kb_vectors()**: Rebuilds all vector indexes to improve performance
   ```sql
   SELECT reindex_kb_vectors();
   ```

2. **kb_vector_stats()**: Returns statistics about vector tables for all tenants
   ```sql
   SELECT * FROM kb_vector_stats();
   ```

## Performance Considerations

- **HNSW vs. IVF-Flat**: HNSW provides faster queries but slower index building, while IVF-Flat offers a balance
- **Index parameters**:
  - HNSW: Adjust `m` (connections per node) and `ef_construction` (search width during build) for different trade-offs
  - IVF-Flat: Adjust `lists` parameter (number of partitions) for different trade-offs
- **Memory**: Vector indexes can be memory-intensive, especially with large datasets

## Related Files

- `infras/lambdas/kb_manager/main.py`: Contains logic for interacting with pgvector from Lambda functions
- `docs/MIGRATION_RDS_PGVECTOR.md`: Detailed documentation on the migration from OpenSearch to pgvector
- `e2e_rds_pgvector_test.sh`: End-to-end test script for the complete workflow
