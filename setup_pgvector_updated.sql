-- Setup pgvector extension and tables for Bedrock Knowledge Base
-- Run this script on your Aurora PostgreSQL cluster

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create table for t001 tenant
CREATE TABLE IF NOT EXISTS kb_vectors_t001 (
    id UUID PRIMARY KEY,  -- Use UUID for Bedrock compatibility
    embedding vector(1536),  -- Dimension for Amazon Titan embeddings
    chunk_text TEXT NOT NULL,
    metadata JSONB
);

-- Create HNSW index for vector similarity search
CREATE INDEX IF NOT EXISTS kb_vectors_t001_embedding_idx
ON kb_vectors_t001
USING hnsw (embedding vector_cosine_ops);  -- HNSW is better than ivfflat for this case

-- Create GIN index for text search
CREATE INDEX IF NOT EXISTS kb_vectors_t001_chunk_text_gin_idx
ON kb_vectors_t001
USING gin (to_tsvector('simple', chunk_text));

-- Create table for t002 tenant
CREATE TABLE IF NOT EXISTS kb_vectors_t002 (
    id UUID PRIMARY KEY,  -- Use UUID for Bedrock compatibility
    embedding vector(1536),  -- Dimension for Amazon Titan embeddings
    chunk_text TEXT NOT NULL,
    metadata JSONB
);

-- Create HNSW index for vector similarity search
CREATE INDEX IF NOT EXISTS kb_vectors_t002_embedding_idx
ON kb_vectors_t002
USING hnsw (embedding vector_cosine_ops);  -- HNSW is better than ivfflat for this case

-- Create GIN index for text search
CREATE INDEX IF NOT EXISTS kb_vectors_t002_chunk_text_gin_idx
ON kb_vectors_t002
USING gin (to_tsvector('simple', chunk_text));

-- Grant necessary permissions
GRANT ALL ON TABLE kb_vectors_t001 TO dbadmin;
GRANT ALL ON TABLE kb_vectors_t002 TO dbadmin;


