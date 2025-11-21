# Lambda Function Fixes for pgvector Integration

## Overview

This document describes the fixes applied to the Lambda functions to ensure proper integration with PostgreSQL pgvector extension.

## Issues Fixed

### 1. Vector Format for PostgreSQL pgvector

**Problem:** PostgreSQL pgvector expects vectors in bracket format `[1,2,3]` but the Lambda was sending them in curly brace format `{1,2,3}`.

**Solution:** 
- Updated the vector formatting in the `query_knowledge_base` function to use brackets instead of braces:
```python
# Format embedding as a string with proper PostgreSQL vector syntax
embedding_str = '[' + ','.join([str(x) for x in embedding_vector]) + ']'
```
- Modified the SQL query to use `::vector` casting for the parameter:
```sql
SELECT chunk_text, metadata, 1 - (embedding <=> :embedding::vector) AS score
FROM {table_name}
ORDER BY embedding <=> :embedding::vector
LIMIT 5;
```

### 2. RDS Data API Parameter Format

**Problem:** The Lambda function was using `arrayValue.floatValues` for vector parameters, but RDS Data API doesn't support this format properly.

**Solution:** Changed the parameter format to use `stringValue` with the vector string representation:
```python
# Execute the query with embedding as string value rather than array
response = rds_client.execute_statement(
    resourceArn=cluster_arn,
    secretArn=secret_arn,
    database=db_name,
    sql=sql_query,
    parameters=[
        {'name': 'embedding', 'value': {'stringValue': embedding_str}}
    ]
)
```

### 3. JSON Request Body Parsing

**Problem:** The Lambda function was failing to parse request bodies when they were already dictionaries instead of JSON strings.

**Solution:** Enhanced the `extract_request_details_from_rest_event` function in `rest_adapter.py` to handle both string and dictionary body formats:
```python
# Handle JSON string or dict
if isinstance(event['body'], dict):
    body = event['body']  # Already a dict, no need to parse
elif isinstance(event['body'], str):
    body = json.loads(event['body'])  # Parse JSON string
else:
    body = {'raw_content': str(event['body'])}
```

## Deployment

A deployment script `deploy_lambda_fix.sh` has been created to update the Lambda functions with these fixes. The script:

1. Packages the updated Lambda code files
2. Updates the Lambda function code
3. Verifies and updates environment variables if needed

To deploy the fixes, run:
```bash
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1
./deploy_lambda_fix.sh
```

## Testing

After deploying the fixes, test the Lambda functions using the end-to-end test script:
```bash
cd /Users/adrian/Projects/Cloudable.AI
./e2e_rds_pgvector_test.sh
```

The test script will:
1. Create a test document
2. Upload it to S3
3. Trigger document processing with pgvector
4. Query the knowledge base using vector similarity search
5. Test the chat functionality with knowledge integration

## Environment Variables

The following environment variables are required by the Lambda functions:
- `RDS_CLUSTER_ARN`: ARN of the RDS cluster
- `RDS_SECRET_ARN`: ARN of the secret containing database credentials
- `RDS_DATABASE`: Database name (default: "cloudable")

The deployment script will check for these variables and prompt to update them if needed.

## Verification

After deploying the fixes, you can verify that they're working correctly by:
1. Checking the CloudWatch logs for the Lambda functions
2. Running the end-to-end test script
3. Checking the RDS database to see if vector operations are being performed correctly

If the fixes are successful, the Lambda function should be able to:
- Generate vector embeddings
- Store them in the PostgreSQL database
- Perform vector similarity searches
- Return relevant results based on the query
