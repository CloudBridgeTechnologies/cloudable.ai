#!/bin/bash

# Script to build Lambda deployment package with dependencies

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  BUILDING LAMBDA DEPLOYMENT PACKAGE"
echo -e "==========================================================${NC}"

# Create a temporary directory for building the package
PACKAGE_DIR="lambda_package"
rm -rf $PACKAGE_DIR
mkdir -p $PACKAGE_DIR

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
pip install requests -t $PACKAGE_DIR
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install dependencies${NC}"
    exit 1
fi

# Copy Lambda function code
echo -e "${YELLOW}Copying Lambda function code...${NC}"
cp lambda_function.py $PACKAGE_DIR/
cp langfuse_integration.py $PACKAGE_DIR/

# Create deployment package
echo -e "${YELLOW}Creating deployment package...${NC}"
cd $PACKAGE_DIR
zip -r ../lambda_deployment_package.zip .
cd ..

if [ -f lambda_deployment_package.zip ]; then
    echo -e "${GREEN}Deployment package created successfully: $(pwd)/lambda_deployment_package.zip${NC}"
    echo -e "Package size: $(du -h lambda_deployment_package.zip | cut -f1)"
else
    echo -e "${RED}Failed to create deployment package${NC}"
    exit 1
fi

echo -e "\n${BLUE}=========================================================="
echo "  LAMBDA PACKAGE BUILD COMPLETED"
echo -e "==========================================================${NC}"
