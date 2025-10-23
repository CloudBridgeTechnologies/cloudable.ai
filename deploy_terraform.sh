#!/bin/bash
# Local Terraform deployment script for Cloudable.AI
set -e

# Configuration
ENV=${1:-dev}
REGION=${2:-us-east-1}
WORKING_DIR="infras/envs/us-east-1"

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cloudable.AI Terraform Deployment ===${NC}"
echo -e "Environment: ${GREEN}$ENV${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not configured properly.${NC}"
    echo -e "Please run 'aws configure' or set up environment variables:"
    echo -e "  export AWS_ACCESS_KEY_ID=your_access_key"
    echo -e "  export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo -e "  export AWS_REGION=$REGION"
    exit 1
fi

echo -e "${BLUE}AWS Identity:${NC}"
aws sts get-caller-identity

# Verify Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed.${NC}"
    echo -e "Please install Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi

# Create terraform.tfvars file
echo -e "${BLUE}Creating terraform.tfvars...${NC}"
cat > $WORKING_DIR/terraform.tfvars << EOF
env = "$ENV"
region = "$REGION"
tenants = {
  t001 = { name = "acme" }
  t002 = { name = "globex" }
}
alert_emails = ["admin@cloudable.ai"]
enable_bedrock_agents = true
EOF

echo -e "${GREEN}Created terraform.tfvars${NC}"

# Initialize terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
cd $WORKING_DIR
terraform init

# Validate terraform configuration
echo -e "${BLUE}Validating Terraform configuration...${NC}"
terraform validate

# Run terraform plan
echo -e "${BLUE}Creating Terraform plan...${NC}"
terraform plan -out=tfplan

# Ask for confirmation before applying
echo -e "${YELLOW}Review the plan above.${NC}"
read -p "Do you want to apply this plan? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Apply terraform plan
    echo -e "${BLUE}Applying Terraform plan...${NC}"
    terraform apply -auto-approve tfplan
    
    # Output important information
    echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
    echo -e "${BLUE}API Endpoint:${NC}"
    terraform output -raw secure_api_endpoint || echo "No endpoint found"
    
    echo -e "${BLUE}API Key:${NC}"
    terraform output -raw secure_api_key || echo "No API key found"
    
    # Save outputs to a file for future reference
    echo -e "${BLUE}Saving deployment outputs to deployment_outputs.json...${NC}"
    {
        echo "{"
        echo "  \"api_endpoint\": \"$(terraform output -raw secure_api_endpoint 2>/dev/null || echo "")\"," 
        echo "  \"api_key\": \"$(terraform output -raw secure_api_key 2>/dev/null || echo "")\"," 
        echo "  \"environment\": \"$ENV\"," 
        echo "  \"deployed_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""
        echo "}"
    } > ../../deployment_outputs.json
    
    echo -e "${GREEN}Deployment information saved to deployment_outputs.json${NC}"
else
    echo -e "${YELLOW}Deployment cancelled.${NC}"
fi
