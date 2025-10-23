# AWS API Knowledge Base Testing Guide

This document outlines the pure API-based approach for testing and interacting with the Amazon Bedrock Knowledge Base feature in Cloudable.AI.

## Overview

The solution uses only AWS SDK APIs (via boto3) to interact with the knowledge base, following best practices for AWS service integration. The implementation avoids custom or direct approaches in favor of official AWS APIs.

## Key AWS APIs Used

1. **Amazon S3 API**
   - `put_object`: Upload documents to S3 with appropriate metadata

2. **Bedrock Agent API**
   - `get_knowledge_base`: Retrieve knowledge base configuration
   - `list_data_sources`: List available data sources in a knowledge base
   - `start_ingestion_job`: Initiate knowledge base ingestion
   - `get_ingestion_job`: Check ingestion status

3. **Bedrock Agent Runtime API**
   - `retrieve`: Query the knowledge base for relevant information

## Test Flow

The `aws_api_kb_test.py` script implements a comprehensive flow for testing knowledge base functionality:

1. **Configuration**: Retrieve bucket name, knowledge base ID, and data source ID from Terraform outputs
2. **Document Upload**: Upload test document (PDF) to S3 using the S3 API
3. **Ingestion**: Start an ingestion job using the Bedrock Agent API (handled gracefully if the storage configuration has issues)
4. **Status Monitoring**: Check ingestion status with the Bedrock Agent API
5. **Querying**: Run test queries against the knowledge base using the Bedrock Agent Runtime API

## Usage

```bash
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/kb
python3 aws_api_kb_test.py
```

## API Error Handling

The script incorporates robust error handling for various AWS API errors:

1. **Validation Exceptions**: Handled gracefully, allowing tests to proceed with existing knowledge base content
2. **Permission Errors**: Detailed error messages to help diagnose IAM issues
3. **Configuration Errors**: Identifies issues with knowledge base storage configuration

## Best Practices Implemented

1. **API-First Approach**: Uses only official AWS APIs instead of custom implementations
2. **Graceful Degradation**: Continues testing even if some steps fail
3. **Informative Outputs**: Clear, color-coded output to help diagnose issues
4. **Resource Discovery**: Uses APIs to discover resources rather than hard-coding
5. **Single Responsibility**: Each method handles one specific API interaction

## Knowledge Base Configuration Issues

If you encounter the error: `The knowledge base storage configuration provided is invalid`, this indicates an issue with the OpenSearch Serverless configuration. The script is designed to handle this gracefully and continue with testing against existing content.

## Future Enhancements

1. Implement integration with CloudWatch Logs API for log analysis
2. Add support for custom metadata field mapping via Bedrock API
3. Incorporate IAM policy testing via AWS API
4. Implement cross-region testing capabilities

---

*Note: This approach replaces previous non-API methods and custom implementations with a standardized AWS API approach.*
