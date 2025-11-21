#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Cleaning up repository for GitHub push...${NC}"

# Create clean directory structure
echo -e "${GREEN}Creating clean directory structure...${NC}"
rm -rf cloudable_clean
mkdir -p cloudable_clean/infras/core
mkdir -p cloudable_clean/infras/lambdas/kb_manager
mkdir -p cloudable_clean/infras/sql
mkdir -p cloudable_clean/infras/terraform
mkdir -p cloudable_clean/test_files

# Copy essential files
echo -e "${GREEN}Copying core files...${NC}"
cp infras/core/lambda_function_simple.py cloudable_clean/infras/core/
cp infras/core/setup_customer_status.py cloudable_clean/infras/core/
cp infras/core/setup_pgvector.py cloudable_clean/infras/core/
cp infras/core/setup_customer_status_tables.sql cloudable_clean/infras/core/
cp infras/core/setup_pgvector.sql cloudable_clean/infras/core/
cp infras/core/tenant_metrics.py cloudable_clean/infras/core/
cp infras/core/tenant_rbac.py cloudable_clean/infras/core/
cp infras/core/langfuse_integration.py cloudable_clean/infras/core/
cp infras/core/real_kb_implementation.tf cloudable_clean/infras/core/

# Copy Lambda function code
echo -e "${GREEN}Copying Lambda function code...${NC}"
cp infras/lambdas/kb_manager/main.py cloudable_clean/infras/lambdas/kb_manager/
cp infras/lambdas/kb_manager/rest_adapter.py cloudable_clean/infras/lambdas/kb_manager/

# Copy SQL scripts
echo -e "${GREEN}Copying SQL scripts...${NC}"
cp infras/sql/schema.sql cloudable_clean/infras/sql/
cp infras/sql/seed.sql cloudable_clean/infras/sql/

# Copy Terraform files
echo -e "${GREEN}Copying Terraform files...${NC}"
cp infras/terraform/api_gateway.tf cloudable_clean/infras/terraform/
cp infras/terraform/lambda.tf cloudable_clean/infras/terraform/
cp infras/terraform/main.tf cloudable_clean/infras/terraform/
cp infras/terraform/rds.tf cloudable_clean/infras/terraform/
cp infras/terraform/vpc.tf cloudable_clean/infras/terraform/

# Copy test files and scripts
echo -e "${GREEN}Copying test files and scripts...${NC}"
cp test_e2e_pipeline.sh cloudable_clean/
if [ -f "test_files/test_document.md" ]; then
  cp test_files/test_document.md cloudable_clean/test_files/
else
  # Create a test document if it doesn't exist
  echo -e "${YELLOW}Creating sample test document...${NC}"
  cat > cloudable_clean/test_files/test_document.md << EOF
# Cloudable.AI Test Document

## Overview
This is a test document for end-to-end pipeline testing.

## Key Information
- Cloudable.AI provides vector similarity search
- Multi-tenant architecture
- Integration with AWS Bedrock
- PostgreSQL with pgvector extension

## Testing
This document is used to verify the complete pipeline from upload to query.
EOF
fi

# Copy README and scripts
cp README.md cloudable_clean/
cp .gitignore cloudable_clean/
cp push_to_github.sh cloudable_clean/
cp prepare_for_github.sh cloudable_clean/

echo -e "${GREEN}Repository cleanup complete!${NC}"
echo -e "${YELLOW}Your cleaned repository is in the 'cloudable_clean' directory.${NC}"
echo -e "${YELLOW}Navigate there and use git to push to GitHub:${NC}"
echo -e "cd cloudable_clean"
echo -e "git init"
echo -e "git add ."
echo -e "git commit -m \"Initial commit of Cloudable.AI project\""
echo -e "git remote add origin <your-github-repo-url>"
echo -e "git push -u origin main"
