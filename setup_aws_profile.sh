#!/bin/bash
# Set up AWS profile for Cloudable.AI project
# This script helps configure AWS CLI profile for local Terraform deployment

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cloudable.AI AWS Profile Setup ===${NC}"

# Ask for AWS credentials
echo -e "${BLUE}Please enter your AWS credentials for the Cloudable.AI project:${NC}"
read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

# Create/update profile
PROFILE_NAME="cloudable"
echo -e "${BLUE}Setting up AWS profile '$PROFILE_NAME'...${NC}"

aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile $PROFILE_NAME
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile $PROFILE_NAME
aws configure set region "$AWS_REGION" --profile $PROFILE_NAME
aws configure set output "json" --profile $PROFILE_NAME

echo -e "${GREEN}AWS profile '$PROFILE_NAME' configured successfully.${NC}"

# Create helper script to set environment variables
cat > set_aws_env.sh << EOF
#!/bin/bash
# Source this file to set AWS environment variables
# Usage: source set_aws_env.sh

export AWS_PROFILE=$PROFILE_NAME
export AWS_REGION=$AWS_REGION
export TF_VAR_region=$AWS_REGION

echo "AWS environment variables set for profile: $PROFILE_NAME"
echo "AWS_PROFILE=$AWS_PROFILE"
echo "AWS_REGION=$AWS_REGION"
EOF

chmod +x set_aws_env.sh

echo -e "${BLUE}Created set_aws_env.sh script to set environment variables.${NC}"
echo -e "${YELLOW}Run the following command before deploying:${NC}"
echo -e "  source set_aws_env.sh"

# Verify AWS credentials work
echo -e "${BLUE}Verifying AWS credentials...${NC}"
if aws sts get-caller-identity --profile $PROFILE_NAME &> /dev/null; then
    echo -e "${GREEN}AWS credentials verified successfully!${NC}"
    aws sts get-caller-identity --profile $PROFILE_NAME
else
    echo -e "${RED}Failed to verify AWS credentials. Please check your inputs and try again.${NC}"
fi
# Set up AWS profile for Cloudable.AI project
# This script helps configure AWS CLI profile for local Terraform deployment

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cloudable.AI AWS Profile Setup ===${NC}"

# Ask for AWS credentials
echo -e "${BLUE}Please enter your AWS credentials for the Cloudable.AI project:${NC}"
read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

# Create/update profile
PROFILE_NAME="cloudable"
echo -e "${BLUE}Setting up AWS profile '$PROFILE_NAME'...${NC}"

aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile $PROFILE_NAME
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile $PROFILE_NAME
aws configure set region "$AWS_REGION" --profile $PROFILE_NAME
aws configure set output "json" --profile $PROFILE_NAME

echo -e "${GREEN}AWS profile '$PROFILE_NAME' configured successfully.${NC}"

# Create helper script to set environment variables
cat > set_aws_env.sh << EOF
#!/bin/bash
# Source this file to set AWS environment variables
# Usage: source set_aws_env.sh

export AWS_PROFILE=$PROFILE_NAME
export AWS_REGION=$AWS_REGION
export TF_VAR_region=$AWS_REGION

echo "AWS environment variables set for profile: $PROFILE_NAME"
echo "AWS_PROFILE=$AWS_PROFILE"
echo "AWS_REGION=$AWS_REGION"
EOF

chmod +x set_aws_env.sh

echo -e "${BLUE}Created set_aws_env.sh script to set environment variables.${NC}"
echo -e "${YELLOW}Run the following command before deploying:${NC}"
echo -e "  source set_aws_env.sh"

# Verify AWS credentials work
echo -e "${BLUE}Verifying AWS credentials...${NC}"
if aws sts get-caller-identity --profile $PROFILE_NAME &> /dev/null; then
    echo -e "${GREEN}AWS credentials verified successfully!${NC}"
    aws sts get-caller-identity --profile $PROFILE_NAME
else
    echo -e "${RED}Failed to verify AWS credentials. Please check your inputs and try again.${NC}"
fi
