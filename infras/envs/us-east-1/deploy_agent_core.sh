#!/bin/bash
# Agent Core Deployment Script
# This script deploys the Agent Core infrastructure and validates the deployment

set -e

# Configuration
ENV="dev"
REGION="us-east-1"
TENANT_ID="t001"
LOG_FILE="agent_core_deployment_$(date +%Y%m%d_%H%M%S).log"

# Color configuration for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if Terraform is installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI."
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    log_success "All prerequisites are met."
}

# Function to check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "AWS credentials are configured."
}

# Function to create Lambda package for Langfuse layer
create_langfuse_layer() {
    log_info "Creating Langfuse Lambda layer..."
    
    LAYER_DIR="layers"
    LANGFUSE_LAYER_DIR="${LAYER_DIR}/langfuse"
    
    mkdir -p "${LANGFUSE_LAYER_DIR}/python"
    cd "${LANGFUSE_LAYER_DIR}/python"
    
    log_info "Installing Langfuse Python package..."
    pip install langfuse -t .
    
    cd ../..
    
    log_info "Creating Langfuse layer ZIP file..."
    zip -r langfuse_layer.zip langfuse/
    
    cd ..
    
    log_success "Langfuse layer created successfully."
}

# Function to deploy Terraform resources
deploy_terraform() {
    log_info "Initializing Terraform..."
    terraform init
    
    log_info "Validating Terraform configuration..."
    terraform validate
    
    log_info "Planning Terraform deployment..."
    terraform plan -out=agent_core.tfplan
    
    log_info "Applying Terraform configuration..."
    terraform apply -auto-approve agent_core.tfplan
    
    log_success "Terraform deployment completed successfully."
}

# Function to update Lambda functions with latest code
update_lambda_functions() {
    log_info "Updating Lambda functions..."
    
    # Create directories for Lambda packages
    LAMBDA_DIR="../../lambdas"
    
    # Update orchestrator Lambda
    log_info "Packaging orchestrator Lambda..."
    ORCHESTRATOR_DIR="${LAMBDA_DIR}/orchestrator"
    ORCHESTRATOR_ZIP="orchestrator.zip"
    
    cd "${ORCHESTRATOR_DIR}" || exit 1
    zip -r "../../envs/${REGION}/${ORCHESTRATOR_ZIP}" ./*.py
    cd "../../envs/${REGION}" || exit 1
    
    log_info "Updating orchestrator Lambda function..."
    aws lambda update-function-code \
        --function-name "orchestrator-${ENV}" \
        --zip-file "fileb://${ORCHESTRATOR_ZIP}" \
        --region "${REGION}"
    
    log_success "Lambda functions updated successfully."
}

# Function to deploy CloudWatch dashboard
deploy_cloudwatch_dashboard() {
    log_info "Deploying CloudWatch dashboard..."
    
    DASHBOARD_NAME="agent-core-dashboard-${ENV}"
    DASHBOARD_FILE="cloudable_monitoring_dashboard.json"
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${DASHBOARD_FILE}" \
        --region "${REGION}"
    
    log_success "CloudWatch dashboard deployed successfully."
}

# Function to set up SSM parameters for Langfuse
setup_langfuse_params() {
    log_info "Setting up Langfuse SSM parameters..."
    
    # Check if parameters already exist
    if aws ssm get-parameter --name "/cloudable/${ENV}/langfuse/public-key" &> /dev/null; then
        log_warning "Langfuse SSM parameters already exist. Skipping..."
    else
        log_info "Please enter your Langfuse credentials:"
        read -p "Langfuse Public Key: " LANGFUSE_PUBLIC_KEY
        read -p "Langfuse Host (default: https://cloud.langfuse.com): " LANGFUSE_HOST
        LANGFUSE_HOST=${LANGFUSE_HOST:-"https://cloud.langfuse.com"}
        read -s -p "Langfuse Secret Key: " LANGFUSE_SECRET_KEY
        echo
        
        # Create SSM parameters
        aws ssm put-parameter \
            --name "/cloudable/${ENV}/langfuse/public-key" \
            --value "${LANGFUSE_PUBLIC_KEY}" \
            --type "String" \
            --region "${REGION}"
            
        aws ssm put-parameter \
            --name "/cloudable/${ENV}/langfuse/host" \
            --value "${LANGFUSE_HOST}" \
            --type "String" \
            --region "${REGION}"
            
        aws ssm put-parameter \
            --name "/cloudable/${ENV}/langfuse/secret-key" \
            --value "${LANGFUSE_SECRET_KEY}" \
            --type "SecureString" \
            --region "${REGION}"
        
        log_success "Langfuse SSM parameters created successfully."
    fi
}

# Function to set up agent alias ARN in SSM
setup_agent_alias_arn() {
    log_info "Setting up agent alias ARN in SSM..."
    
    # Get the agent ID and alias ID from Terraform outputs
    AGENT_ID=$(terraform output -raw agent_id 2>/dev/null || echo "")
    ALIAS_ID=$(terraform output -raw agent_alias_id 2>/dev/null || echo "")
    
    if [[ -z "${AGENT_ID}" || -z "${ALIAS_ID}" ]]; then
        log_warning "Agent ID or Alias ID not found in Terraform outputs."
        log_info "Please enter your agent information manually:"
        read -p "Agent ID: " AGENT_ID
        read -p "Agent Alias ID: " ALIAS_ID
    fi
    
    # Construct the agent alias ARN
    AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
    AGENT_ALIAS_ARN="arn:aws:bedrock:${REGION}:${AWS_ACCOUNT}:agent-alias/${AGENT_ID}/${ALIAS_ID}"
    
    # Create or update SSM parameter
    aws ssm put-parameter \
        --name "/cloudable/${ENV}/agent/${TENANT_ID}/alias_arn" \
        --value "${AGENT_ALIAS_ARN}" \
        --type "String" \
        --overwrite \
        --region "${REGION}"
    
    log_success "Agent alias ARN set up successfully in SSM: ${AGENT_ALIAS_ARN}"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    python3 validate_agent_core.py --tenant-id "${TENANT_ID}" --env "${ENV}"
    VALIDATION_RESULT=$?
    
    if [ $VALIDATION_RESULT -eq 0 ]; then
        log_success "Validation tests completed successfully."
    else
        log_error "Validation tests failed."
        return 1
    fi
}

# Function to test API endpoint
test_api_endpoint() {
    log_info "Testing API endpoint..."
    
    # Get API Gateway ID and API Key
    API_ID=$(terraform output -raw api_gateway_id 2>/dev/null || echo "")
    API_KEY=$(terraform output -raw api_key 2>/dev/null || echo "")
    
    if [[ -z "${API_ID}" || -z "${API_KEY}" ]]; then
        log_warning "API ID or API Key not found in Terraform outputs."
        read -p "API Gateway ID: " API_ID
        read -p "API Key: " API_KEY
    fi
    
    # Test chat endpoint
    API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENV}/chat"
    log_info "Testing chat endpoint: ${API_ENDPOINT}"
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${API_KEY}" \
        -d "{\"tenant_id\":\"${TENANT_ID}\",\"customer_id\":\"test_user\",\"message\":\"What is my journey status?\"}" \
        "${API_ENDPOINT}")
    
    echo "${RESPONSE}" | jq . || echo "${RESPONSE}"
    
    if [[ "${RESPONSE}" == *"answer"* ]]; then
        log_success "API test completed successfully."
    else
        log_error "API test failed."
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting Agent Core deployment at $(date)"
    
    check_prerequisites
    check_aws_credentials
    
    # Create Langfuse layer
    create_langfuse_layer
    
    # Deploy Terraform resources
    deploy_terraform
    
    # Update Lambda functions
    update_lambda_functions
    
    # Deploy CloudWatch dashboard
    deploy_cloudwatch_dashboard
    
    # Set up Langfuse parameters
    setup_langfuse_params
    
    # Set up agent alias ARN
    setup_agent_alias_arn
    
    # Run validation tests
    run_validation_tests
    
    # Test API endpoint
    test_api_endpoint
    
    log_success "Agent Core deployment completed successfully at $(date)"
}

# Execute main function
main
# Agent Core Deployment Script
# This script deploys the Agent Core infrastructure and validates the deployment

set -e

# Configuration
ENV="dev"
REGION="us-east-1"
TENANT_ID="t001"
LOG_FILE="agent_core_deployment_$(date +%Y%m%d_%H%M%S).log"

# Color configuration for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if Terraform is installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI."
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    log_success "All prerequisites are met."
}

# Function to check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "AWS credentials are configured."
}

# Function to create Lambda package for Langfuse layer
create_langfuse_layer() {
    log_info "Creating Langfuse Lambda layer..."
    
    LAYER_DIR="layers"
    LANGFUSE_LAYER_DIR="${LAYER_DIR}/langfuse"
    
    mkdir -p "${LANGFUSE_LAYER_DIR}/python"
    cd "${LANGFUSE_LAYER_DIR}/python"
    
    log_info "Installing Langfuse Python package..."
    pip install langfuse -t .
    
    cd ../..
    
    log_info "Creating Langfuse layer ZIP file..."
    zip -r langfuse_layer.zip langfuse/
    
    cd ..
    
    log_success "Langfuse layer created successfully."
}

# Function to deploy Terraform resources
deploy_terraform() {
    log_info "Initializing Terraform..."
    terraform init
    
    log_info "Validating Terraform configuration..."
    terraform validate
    
    log_info "Planning Terraform deployment..."
    terraform plan -out=agent_core.tfplan
    
    log_info "Applying Terraform configuration..."
    terraform apply -auto-approve agent_core.tfplan
    
    log_success "Terraform deployment completed successfully."
}

# Function to update Lambda functions with latest code
update_lambda_functions() {
    log_info "Updating Lambda functions..."
    
    # Create directories for Lambda packages
    LAMBDA_DIR="../../lambdas"
    
    # Update orchestrator Lambda
    log_info "Packaging orchestrator Lambda..."
    ORCHESTRATOR_DIR="${LAMBDA_DIR}/orchestrator"
    ORCHESTRATOR_ZIP="orchestrator.zip"
    
    cd "${ORCHESTRATOR_DIR}" || exit 1
    zip -r "../../envs/${REGION}/${ORCHESTRATOR_ZIP}" ./*.py
    cd "../../envs/${REGION}" || exit 1
    
    log_info "Updating orchestrator Lambda function..."
    aws lambda update-function-code \
        --function-name "orchestrator-${ENV}" \
        --zip-file "fileb://${ORCHESTRATOR_ZIP}" \
        --region "${REGION}"
    
    log_success "Lambda functions updated successfully."
}

# Function to deploy CloudWatch dashboard
deploy_cloudwatch_dashboard() {
    log_info "Deploying CloudWatch dashboard..."
    
    DASHBOARD_NAME="agent-core-dashboard-${ENV}"
    DASHBOARD_FILE="cloudable_monitoring_dashboard.json"
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${DASHBOARD_FILE}" \
        --region "${REGION}"
    
    log_success "CloudWatch dashboard deployed successfully."
}

# Function to set up SSM parameters for Langfuse
setup_langfuse_params() {
    log_info "Setting up Langfuse SSM parameters..."
    
    # Check if parameters already exist
    if aws ssm get-parameter --name "/cloudable/${ENV}/langfuse/public-key" &> /dev/null; then
        log_warning "Langfuse SSM parameters already exist. Skipping..."
    else
        log_info "Please enter your Langfuse credentials:"
        read -p "Langfuse Public Key: " LANGFUSE_PUBLIC_KEY
        read -p "Langfuse Host (default: https://cloud.langfuse.com): " LANGFUSE_HOST
        LANGFUSE_HOST=${LANGFUSE_HOST:-"https://cloud.langfuse.com"}
        read -s -p "Langfuse Secret Key: " LANGFUSE_SECRET_KEY
        echo
        
        # Create SSM parameters
        aws ssm put-parameter \
            --name "/cloudable/${ENV}/langfuse/public-key" \
            --value "${LANGFUSE_PUBLIC_KEY}" \
            --type "String" \
            --region "${REGION}"
            
        aws ssm put-parameter \
            --name "/cloudable/${ENV}/langfuse/host" \
            --value "${LANGFUSE_HOST}" \
            --type "String" \
            --region "${REGION}"
            
        aws ssm put-parameter \
            --name "/cloudable/${ENV}/langfuse/secret-key" \
            --value "${LANGFUSE_SECRET_KEY}" \
            --type "SecureString" \
            --region "${REGION}"
        
        log_success "Langfuse SSM parameters created successfully."
    fi
}

# Function to set up agent alias ARN in SSM
setup_agent_alias_arn() {
    log_info "Setting up agent alias ARN in SSM..."
    
    # Get the agent ID and alias ID from Terraform outputs
    AGENT_ID=$(terraform output -raw agent_id 2>/dev/null || echo "")
    ALIAS_ID=$(terraform output -raw agent_alias_id 2>/dev/null || echo "")
    
    if [[ -z "${AGENT_ID}" || -z "${ALIAS_ID}" ]]; then
        log_warning "Agent ID or Alias ID not found in Terraform outputs."
        log_info "Please enter your agent information manually:"
        read -p "Agent ID: " AGENT_ID
        read -p "Agent Alias ID: " ALIAS_ID
    fi
    
    # Construct the agent alias ARN
    AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
    AGENT_ALIAS_ARN="arn:aws:bedrock:${REGION}:${AWS_ACCOUNT}:agent-alias/${AGENT_ID}/${ALIAS_ID}"
    
    # Create or update SSM parameter
    aws ssm put-parameter \
        --name "/cloudable/${ENV}/agent/${TENANT_ID}/alias_arn" \
        --value "${AGENT_ALIAS_ARN}" \
        --type "String" \
        --overwrite \
        --region "${REGION}"
    
    log_success "Agent alias ARN set up successfully in SSM: ${AGENT_ALIAS_ARN}"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    python3 validate_agent_core.py --tenant-id "${TENANT_ID}" --env "${ENV}"
    VALIDATION_RESULT=$?
    
    if [ $VALIDATION_RESULT -eq 0 ]; then
        log_success "Validation tests completed successfully."
    else
        log_error "Validation tests failed."
        return 1
    fi
}

# Function to test API endpoint
test_api_endpoint() {
    log_info "Testing API endpoint..."
    
    # Get API Gateway ID and API Key
    API_ID=$(terraform output -raw api_gateway_id 2>/dev/null || echo "")
    API_KEY=$(terraform output -raw api_key 2>/dev/null || echo "")
    
    if [[ -z "${API_ID}" || -z "${API_KEY}" ]]; then
        log_warning "API ID or API Key not found in Terraform outputs."
        read -p "API Gateway ID: " API_ID
        read -p "API Key: " API_KEY
    fi
    
    # Test chat endpoint
    API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENV}/chat"
    log_info "Testing chat endpoint: ${API_ENDPOINT}"
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${API_KEY}" \
        -d "{\"tenant_id\":\"${TENANT_ID}\",\"customer_id\":\"test_user\",\"message\":\"What is my journey status?\"}" \
        "${API_ENDPOINT}")
    
    echo "${RESPONSE}" | jq . || echo "${RESPONSE}"
    
    if [[ "${RESPONSE}" == *"answer"* ]]; then
        log_success "API test completed successfully."
    else
        log_error "API test failed."
        return 1
    fi
}

# Main deployment function
main() {
    log_info "Starting Agent Core deployment at $(date)"
    
    check_prerequisites
    check_aws_credentials
    
    # Create Langfuse layer
    create_langfuse_layer
    
    # Deploy Terraform resources
    deploy_terraform
    
    # Update Lambda functions
    update_lambda_functions
    
    # Deploy CloudWatch dashboard
    deploy_cloudwatch_dashboard
    
    # Set up Langfuse parameters
    setup_langfuse_params
    
    # Set up agent alias ARN
    setup_agent_alias_arn
    
    # Run validation tests
    run_validation_tests
    
    # Test API endpoint
    test_api_endpoint
    
    log_success "Agent Core deployment completed successfully at $(date)"
}

# Execute main function
main
