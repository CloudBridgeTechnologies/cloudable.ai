# Langfuse Integration for Cloudable.AI

This document explains how Langfuse observability has been integrated into the Cloudable.AI platform to provide comprehensive monitoring and tracing of LLM operations across the application.

## Overview

Langfuse is a powerful observability platform designed specifically for LLM-powered applications. It enables:
- Tracing of complex LLM interactions across multiple components
- Monitoring of prompt/response quality, latency, and cost
- Evaluation of LLM performance
- Detailed analytics on usage patterns

The integration in Cloudable.AI covers all key AI/LLM touchpoints:
1. Knowledge Base queries
2. Chat interactions
3. Bedrock API calls for summarization
4. Customer status generation

## Components

### 1. Langfuse Integration Module

The core integration module (`langfuse_integration.py`) provides:
- A wrapper around the Langfuse client SDK
- Mock client implementation for local development
- Functions for tracing different types of LLM interactions
- Automatic fallbacks for reliability

### 2. KB Query Integration

For knowledge base queries, we track:
- Query text
- Results returned with metadata
- Vector search performance
- Cross-tenant queries and isolation enforcement

### 3. Chat Integration  

For chat interactions, we track:
- User messages
- AI responses
- Source documents used
- Estimated token usage
- Chat session metrics

### 4. Bedrock Summarization Integration

For AWS Bedrock API calls, we track:
- Prompts sent to Bedrock
- Responses received
- Model used and purpose
- Performance metrics

### 5. Customer Status Integration

For customer status queries, we track:
- Customer information retrieval
- RDS queries performance
- Status summarization operations
- Tenant isolation enforcement

## Deployment

To deploy the Langfuse integration:

1. Run the deployment script:
   ```bash
   cd infras/core
   ./deploy_with_langfuse.sh
   ```

2. Configure Langfuse API keys:
   - Create an account at https://cloud.langfuse.com
   - Obtain your API keys from Settings > API Keys
   - Update Lambda environment variables with your keys

3. Test the integration:
   ```bash
   ./test_langfuse_integration.sh
   ```

4. Check the Langfuse dashboard to confirm traces are being recorded

## Test Cases

The test script (`test_langfuse_integration.sh`) includes diverse queries for both KB and customer status APIs:

### KB Query Test Cases
- Implementation status queries
- Success metrics queries
- Next steps and roadmap queries
- Digital transformation objectives
- Stakeholder identification
- Timeline and scheduling queries

### Chat Test Cases
- Implementation progress conversations
- Success metrics discussions
- Risk assessment conversations
- Stakeholder role clarifications
- Timeline and planning discussions

### Customer Status Test Cases
- Full customer list retrieval
- Specific customer status queries
- Milestone tracking
- Implementation stage verification

### Security Test Cases
- Cross-tenant isolation validation
- Access control verification

## Monitoring in Production

In a production environment, the Langfuse dashboard enables:

1. **Real-time monitoring**
   - Track current usage and performance
   - Get alerts on anomalous behavior

2. **Analytics**
   - User engagement patterns
   - Most common queries
   - Response quality metrics

3. **Feedback loops**
   - Identify areas for improvement
   - Track performance over time

4. **Cost optimization**
   - Token usage monitoring
   - Model efficiency tracking

## Next Steps

1. **Feedback collection**: Implement user feedback collection to correlate with traces
2. **Custom evaluation**: Create custom evaluation metrics for tenant-specific requirements
3. **A/B testing**: Use Langfuse to compare performance of different prompts or models
4. **Dashboard integration**: Integrate Langfuse metrics into customer-facing dashboards

---

For more information on Langfuse, visit [Langfuse Documentation](https://langfuse.com/docs)
