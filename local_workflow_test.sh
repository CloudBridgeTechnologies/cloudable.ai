#!/bin/bash
# Local workflow testing script for Cloudable.AI
# This script helps test GitHub Actions workflows locally

set -e

# Configuration
ENV="dev"
REGION="us-east-1"
TENANT_ID="t001"
PROJECT_ROOT=$(pwd)
WORKFLOWS_DIR=".github/workflows"
INFRA_DIR="infras/envs/us-east-1"

# Color configuration for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "AWS CLI is configured."
}

# Function to validate workflow files
validate_workflows() {
    log_info "Validating workflow files..."
    
    if [ ! -f "validate_workflows.py" ]; then
        log_error "validate_workflows.py not found. Please make sure it exists in the project root."
        exit 1
    fi
    
    python validate_workflows.py
    
    log_success "Workflow validation complete."
}

# Function to test S3 and DynamoDB access
test_aws_resources() {
    log_info "Testing AWS resources access..."
    
    # Test S3 access
    log_info "Testing S3 access..."
    if aws s3 ls &> /dev/null; then
        log_success "S3 access successful."
    else
        log_error "Failed to access S3. Check your AWS credentials."
        exit 1
    fi
    
    # Test DynamoDB access
    log_info "Testing DynamoDB access..."
    if aws dynamodb list-tables --region $REGION &> /dev/null; then
        log_success "DynamoDB access successful."
    else
        log_error "Failed to access DynamoDB. Check your AWS credentials."
        exit 1
    fi
}

# Function to test Terraform commands
test_terraform() {
    log_info "Testing Terraform commands..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    }
    
    cd $INFRA_DIR
    
    # Test terraform init
    log_info "Testing terraform init..."
    if terraform init -backend=false &> /dev/null; then
        log_success "Terraform init successful."
    else
        log_error "Terraform init failed. Check your Terraform configuration."
        exit 1
    fi
    
    # Test terraform validate
    log_info "Testing terraform validate..."
    terraform validate
    
    cd $PROJECT_ROOT
}

# Function to simulate AWS Resources Setup workflow
simulate_aws_setup() {
    log_info "Simulating AWS Resources Setup workflow..."
    
    # Create a test S3 bucket name
    TEST_BUCKET="cloudable-tfstate-dev-test-$(date +%s)"
    TEST_TABLE="cloudable-tf-locks-dev-test"
    
    log_info "This is a dry run. Would create:"
    echo "- S3 bucket: $TEST_BUCKET"
    echo "- DynamoDB table: $TEST_TABLE"
    
    log_info "To actually create resources, run the GitHub Actions workflow."
    log_success "AWS Resources Setup simulation complete."
}

# Function to simulate Terraform Deploy workflow
simulate_terraform_deploy() {
    log_info "Simulating Terraform Deploy workflow..."
    
    cd $INFRA_DIR
    
    # Test terraform plan
    log_info "Running terraform plan (this is a dry run)..."
    terraform plan -no-color
    
    cd $PROJECT_ROOT
    
    log_info "To actually apply changes, run the GitHub Actions workflow."
    log_success "Terraform Deploy simulation complete."
}

# Main function
main() {
    log_info "Starting local workflow testing for Cloudable.AI..."
    
    check_aws_cli
    validate_workflows
    test_aws_resources
    test_terraform
    simulate_aws_setup
    simulate_terraform_deploy
    
    log_success "All tests completed successfully!"
    log_info "You can now run the GitHub Actions workflows as described in WORKFLOW_EXECUTION_INSTRUCTIONS.md"
}

# Execute main function
main
# Local workflow testing script for Cloudable.AI
# This script helps test GitHub Actions workflows locally

set -e

# Configuration
ENV="dev"
REGION="us-east-1"
TENANT_ID="t001"
PROJECT_ROOT=$(pwd)
WORKFLOWS_DIR=".github/workflows"
INFRA_DIR="infras/envs/us-east-1"

# Color configuration for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "AWS CLI is configured."
}

# Function to validate workflow files
validate_workflows() {
    log_info "Validating workflow files..."
    
    if [ ! -f "validate_workflows.py" ]; then
        log_error "validate_workflows.py not found. Please make sure it exists in the project root."
        exit 1
    fi
    
    python validate_workflows.py
    
    log_success "Workflow validation complete."
}

# Function to test S3 and DynamoDB access
test_aws_resources() {
    log_info "Testing AWS resources access..."
    
    # Test S3 access
    log_info "Testing S3 access..."
    if aws s3 ls &> /dev/null; then
        log_success "S3 access successful."
    else
        log_error "Failed to access S3. Check your AWS credentials."
        exit 1
    fi
    
    # Test DynamoDB access
    log_info "Testing DynamoDB access..."
    if aws dynamodb list-tables --region $REGION &> /dev/null; then
        log_success "DynamoDB access successful."
    else
        log_error "Failed to access DynamoDB. Check your AWS credentials."
        exit 1
    fi
}

# Function to test Terraform commands
test_terraform() {
    log_info "Testing Terraform commands..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    }
    
    cd $INFRA_DIR
    
    # Test terraform init
    log_info "Testing terraform init..."
    if terraform init -backend=false &> /dev/null; then
        log_success "Terraform init successful."
    else
        log_error "Terraform init failed. Check your Terraform configuration."
        exit 1
    fi
    
    # Test terraform validate
    log_info "Testing terraform validate..."
    terraform validate
    
    cd $PROJECT_ROOT
}

# Function to simulate AWS Resources Setup workflow
simulate_aws_setup() {
    log_info "Simulating AWS Resources Setup workflow..."
    
    # Create a test S3 bucket name
    TEST_BUCKET="cloudable-tfstate-dev-test-$(date +%s)"
    TEST_TABLE="cloudable-tf-locks-dev-test"
    
    log_info "This is a dry run. Would create:"
    echo "- S3 bucket: $TEST_BUCKET"
    echo "- DynamoDB table: $TEST_TABLE"
    
    log_info "To actually create resources, run the GitHub Actions workflow."
    log_success "AWS Resources Setup simulation complete."
}

# Function to simulate Terraform Deploy workflow
simulate_terraform_deploy() {
    log_info "Simulating Terraform Deploy workflow..."
    
    cd $INFRA_DIR
    
    # Test terraform plan
    log_info "Running terraform plan (this is a dry run)..."
    terraform plan -no-color
    
    cd $PROJECT_ROOT
    
    log_info "To actually apply changes, run the GitHub Actions workflow."
    log_success "Terraform Deploy simulation complete."
}

# Main function
main() {
    log_info "Starting local workflow testing for Cloudable.AI..."
    
    check_aws_cli
    validate_workflows
    test_aws_resources
    test_terraform
    simulate_aws_setup
    simulate_terraform_deploy
    
    log_success "All tests completed successfully!"
    log_info "You can now run the GitHub Actions workflows as described in WORKFLOW_EXECUTION_INSTRUCTIONS.md"
}

# Execute main function
main
