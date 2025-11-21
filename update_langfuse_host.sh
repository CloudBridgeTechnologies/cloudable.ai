#!/bin/bash

# Script to update the Langfuse host environment variable

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

echo "Updating Lambda function configuration..."

# Get the current function configuration
FUNCTION_CONFIG=$(aws lambda get-function-configuration --function-name kb-manager-dev-core)

# Extract the current environment variables
ENV_VARS=$(echo "$FUNCTION_CONFIG" | jq -r '.Environment.Variables')

# Update the Langfuse host
UPDATED_ENV=$(echo "$ENV_VARS" | jq '. + {
    "LANGFUSE_HOST": "https://eu.cloud.langfuse.com",
    "LANGFUSE_PROJECT_ID": "cmhz8tqhk00duad07xptpuo06",
    "LANGFUSE_ORG_ID": "cmhz8tcqz00dpad07ee341p57"
}')

# Create a temporary file with the updated configuration
cat > /tmp/env_update.json << EOF
{
  "Environment": {
    "Variables": $UPDATED_ENV
  }
}
EOF

# Update the Lambda function configuration
aws lambda update-function-configuration \
  --function-name kb-manager-dev-core \
  --cli-input-json file:///tmp/env_update.json

if [ $? -eq 0 ]; then
  echo "Lambda environment variables updated successfully"
else
  echo "Failed to update Lambda environment variables"
  exit 1
fi

# Clean up
rm /tmp/env_update.json

echo "Langfuse host updated to https://eu.cloud.langfuse.com"
echo "Langfuse project ID set to cmhz8tqhk00duad07xptpuo06"
echo "Langfuse organization ID set to cmhz8tcqz00dpad07ee341p57"
