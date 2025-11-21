#!/bin/bash
# Master script to run all tests for Cloudable.AI

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Cloudable.AI Complete Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"

# Make all scripts executable
echo -e "${BLUE}Making scripts executable...${NC}"
chmod +x *.sh
chmod +x ../tools/kb/*.py

# Step 1: Get API configuration
echo -e "${BLUE}Step 1: Getting API configuration...${NC}"
./get_api_config.sh

# Step 2: Run quick API tests
echo -e "${BLUE}Step 2: Running quick API tests...${NC}"
./quick_test.sh

# Step 3: Run comprehensive tests
echo -e "${BLUE}Step 3: Running comprehensive tests...${NC}"
./comprehensive_local_test.sh

echo ""
echo -e "${GREEN}All tests completed!${NC}"
echo ""
echo -e "${BLUE}Available test files:${NC}"
echo "1. comprehensive_local_test.sh - Full test suite"
echo "2. quick_test.sh - Basic API tests"
echo "3. test_with_pdf.sh <pdf-file> - Test with specific PDF"
echo "4. postman_collection.json - Postman collection"
echo "5. environment.json - Postman environment"
echo ""
echo -e "${YELLOW}To test with your Bedrock PDF:${NC}"
echo "./test_with_pdf.sh /path/to/your/bedrock-pdf.pdf"
echo ""
echo -e "${YELLOW}To use Postman:${NC}"
echo "1. Import postman_collection.json"
echo "2. Import environment.json"
echo "3. Select the environment"
echo "4. Run the collection"
