-- Setup pgvector extension and tables for Bedrock Knowledge Base
-- Run this script on your Aurora PostgreSQL cluster

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create table for acme tenant
CREATE TABLE IF NOT EXISTS kb_vectors_acme (
    id TEXT PRIMARY KEY,
    embedding vector(1536),  -- Dimension for Amazon Titan embeddings
    chunk_text TEXT NOT NULL,
    metadata JSONB
);

-- Create index for vector similarity search
CREATE INDEX IF NOT EXISTS kb_vectors_acme_embedding_idx 
ON kb_vectors_acme 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Create table for globex tenant
CREATE TABLE IF NOT EXISTS kb_vectors_globex (
    id TEXT PRIMARY KEY,
    embedding vector(1536),  -- Dimension for Amazon Titan embeddings
    chunk_text TEXT NOT NULL,
    metadata JSONB
);

-- Create index for vector similarity search
CREATE INDEX IF NOT EXISTS kb_vectors_globex_embedding_idx 
ON kb_vectors_globex 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Grant necessary permissions (adjust as needed)
GRANT ALL ON TABLE kb_vectors_acme TO dbadmin;
GRANT ALL ON TABLE kb_vectors_globex TO dbadmin;

