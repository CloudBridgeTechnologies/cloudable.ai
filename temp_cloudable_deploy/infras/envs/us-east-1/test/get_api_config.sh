#!/bin/bash
# Script to get API configuration from Terraform and update test files

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Getting API configuration from Terraform...${NC}"

# Change to the terraform directory
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/

# Get API endpoint and key
API_ENDPOINT=$(terraform output -raw secure_api_endpoint 2>/dev/null || echo "")
API_KEY=$(terraform output -raw secure_api_key 2>/dev/null || echo "")

if [ -z "$API_ENDPOINT" ] || [ -z "$API_KEY" ]; then
    echo -e "${YELLOW}Warning: Could not get API configuration from Terraform${NC}"
    echo "Please ensure:"
    echo "1. You are in the correct directory"
    echo "2. Terraform has been applied successfully"
    echo "3. The secure API resources exist"
    echo ""
    echo "You can manually set these values in the test files:"
    echo "API_ENDPOINT=your-api-endpoint"
    echo "API_KEY=your-api-key"
    exit 1
fi

echo -e "${GREEN}API Endpoint: $API_ENDPOINT${NC}"
echo -e "${GREEN}API Key: ${API_KEY:0:7}...${API_KEY: -5}${NC}"

# Update the Postman environment file
echo -e "${BLUE}Updating Postman environment file...${NC}"
cat > environment.json << EOF
{
  "id": "cloudable-ai-env",
  "name": "Cloudable.AI Environment",
  "values": [
    {
      "key": "api_endpoint",
      "value": "$API_ENDPOINT",
      "description": "API Gateway endpoint URL",
      "enabled": true
    },
    {
      "key": "api_key",
      "value": "$API_KEY",
      "description": "API Gateway API key for authentication",
      "enabled": true
    },
    {
      "key": "tenant_id",
      "value": "acme",
      "description": "Tenant ID for multi-tenant testing",
      "enabled": true
    },
    {
      "key": "document_id",
      "value": "test_document_id",
      "description": "Document ID for summary retrieval testing",
      "enabled": true
    },
    {
      "key": "customer_id",
      "value": "c001",
      "description": "Customer ID for API requests",
      "enabled": true
    }
  ],
  "_postman_variable_scope": "environment"
}
EOF

echo -e "${GREEN}Postman environment file updated successfully!${NC}"

# Create a simple test script with the actual values
cat > quick_test.sh << EOF
#!/bin/bash
# Quick API test with actual values

API_ENDPOINT="$API_ENDPOINT"
API_KEY="$API_KEY"

echo "Testing Chat API..."
curl -X POST "\$API_ENDPOINT/chat" \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: \$API_KEY" \\
  -d '{"tenant_id":"acme","customer_id":"c001","message":"What is the company vacation policy?"}'

echo -e "\n\nTesting KB Query API..."
curl -X POST "\$API_ENDPOINT/kb/query" \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: \$API_KEY" \\
  -d '{"tenant_id":"acme","customer_id":"c001","query":"What are the security policies?"}'

echo -e "\n\nTesting without API key (should fail)..."
curl -X POST "\$API_ENDPOINT/chat" \\
  -H "Content-Type: application/json" \\
  -d '{"tenant_id":"acme","customer_id":"c001","message":"Hello"}'
EOF

chmod +x quick_test.sh

echo -e "${GREEN}Quick test script created: quick_test.sh${NC}"
echo -e "${BLUE}You can now run: ./quick_test.sh${NC}"

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Import the postman_collection.json and environment.json into Postman"
echo "2. Run the comprehensive_local_test.sh script"
echo "3. Or run the quick_test.sh script for basic API testing"
