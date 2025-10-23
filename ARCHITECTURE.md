# Cloudable.AI Architecture Overview

This document provides a high-level overview of the Cloudable.AI platform architecture, focusing on the dual-path document processing flow and API security.

## Dual-Path Document Processing Flow

```
┌──────────────┐            ┌───────────────┐            ┌────────────────────┐
│              │            │               │            │                    │
│  Document    │─── S3 ────▶│  S3 Helper    │────────┬──▶│  KB-Sync Trigger   │
│  Upload      │    Event   │  Lambda       │        │   │  Lambda            │
│              │            │               │        │   │                    │
└──────────────┘            └───────────────┘        │   └────────────────────┘
                                    │                │             │
                                    │                │             │
                                    │                │             │
                                    ▼                │             ▼
                            ┌───────────────┐        │    ┌────────────────────┐
                            │               │        │    │                    │
                            │  Processed    │        │    │  Bedrock           │
                            │  Document     │        │    │  Knowledge Base    │
                            │  (with        │        │    │                    │
                            │   metadata)   │        │    └────────────────────┘
                            │               │        │             │
                            └───────────────┘        │             │
                                    │                │             │
                                    │                │             │
                                    ▼                ▼             ▼
┌──────────────┐            ┌───────────────┐    ┌────────────────────┐
│              │            │               │    │                    │
│  Document    │◀───────────│  Document     │    │  AI Chat           │
│  Summary     │  Stores    │  Summarizer   │    │  (Claude Sonnet)   │
│  (S3)        │  Summary   │  Lambda       │    │                    │
│              │            │               │    └────────────────────┘
└──────────────┘            └───────────────┘             ▲
       │                                                  │
       │                                                  │
       ▼                                                  │
┌──────────────┐                                  ┌───────────────┐
│              │                                  │               │
│  Summary     │◀─────────────────────────────────│  API Gateway  │
│  Retriever   │                                  │  (with API    │
│  Lambda      │                                  │   key auth)   │
│              │                                  │               │
└──────────────┘                                  └───────────────┘
       ▲                                                  ▲
       │                                                  │
       │                                                  │
       └──────────────────────────────────────────────────┘
                              │
                              │
                              ▼
                      ┌───────────────┐
                      │               │
                      │  Client       │
                      │  Application  │
                      │               │
                      └───────────────┘
```

## API Gateway Security Architecture

```
                       ┌───────────────────────────┐
                       │                           │
                       │   Client Application      │
                       │                           │
                       └───────────────────────────┘
                                     │
                                     │ HTTPS
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│                           AWS WAF                                    │
│                                                                      │
│    (SQL Injection Protection, Rate Limiting, Common Vulnerabilities) │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│                      API Gateway REST API                            │
│                                                                      │
│  ┌────────────────┐   ┌────────────────┐    ┌────────────────────┐   │
│  │                │   │                │    │                    │   │
│  │  API Key       │◀──│  Usage Plan    │───▶│  Throttling &      │   │
│  │  Validation    │   │  (10k/day)     │    │  Quota Control     │   │
│  │                │   │                │    │                    │   │
│  └────────────────┘   └────────────────┘    └────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │
            ┌─────────────────────┬──┴───────────────┬─────────────────┐
            │                     │                  │                 │
            ▼                     ▼                  ▼                 ▼
┌────────────────────┐  ┌─────────────────┐ ┌────────────────┐ ┌───────────────┐
│                    │  │                 │ │                │ │               │
│  Chat Lambda       │  │ KB Manager      │ │ Document       │ │ Summary       │
│  (Orchestrator)    │  │ Lambda          │ │ Summarizer     │ │ Retriever     │
│                    │  │                 │ │ Lambda         │ │ Lambda        │
└────────────────────┘  └─────────────────┘ └────────────────┘ └───────────────┘
```

## Component Details

### Client-Facing Components

1. **API Gateway**:
   - REST API with API key authentication
   - Usage plans with throttling and quota limits
   - WAF integration for security

2. **Client-Facing Endpoints**:
   - `/chat` - Chat interface with Claude Sonnet
   - `/summary/{tenant_id}/{document_id}` - Summary retrieval
   - `/kb/query` - Knowledge base querying
   - `/kb/upload-url` - Presigned URL generation for uploads

### Backend Processing

1. **Document Upload Flow**:
   - Client gets presigned URL from API
   - Document uploaded directly to S3
   - S3 event triggers S3 Helper Lambda
   - S3 Helper adds metadata and creates processed version
   - Processed document triggers two parallel flows

2. **Knowledge Base Flow**:
   - KB Sync Trigger Lambda initiates ingestion
   - Bedrock Knowledge Base processes and indexes content
   - Content available for AI queries through Chat endpoint

3. **Summary Flow**:
   - Document Summarizer Lambda extracts text from PDFs
   - Claude generates executive summary
   - Summary stored in dedicated S3 bucket with metadata
   - Summary Retriever Lambda provides API access

### Security Components

1. **Authentication**:
   - API key validation for all requests
   - Usage plans to control access and rate limiting

2. **WAF Protection**:
   - SQL injection protection
   - Rate-based limiting
   - Common vulnerabilities protection

3. **Encryption**:
   - S3 server-side encryption
   - HTTPS for all API communications
   - KMS for key management

## Monitoring and Alerting

1. **CloudWatch Dashboards**:
   - API usage metrics
   - Error rates and latency
   - Security events

2. **CloudWatch Alarms**:
   - Unusual traffic patterns
   - High error rates
   - Guardrail triggers

3. **Logging**:
   - Structured logging for all Lambda functions
   - API Gateway access logs
   - S3 access logging

## Deployment

The entire architecture is deployed using Terraform, ensuring reproducibility and infrastructure as code best practices.
