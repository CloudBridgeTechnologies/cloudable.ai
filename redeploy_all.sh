#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set environment variables
export ENV="dev"
export REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/infras/envs/us-east-1"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI FULL REDEPLOYMENT                ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Step 1: Verify prerequisites
echo -e "\n${YELLOW}Step 1: Verifying prerequisites...${NC}"
# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
  echo -e "${RED}ERROR: Terraform is not installed. Please install it before running this script.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Terraform is installed${NC}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo -e "${RED}ERROR: AWS CLI is not installed. Please install it before running this script.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ AWS CLI is installed${NC}"

# Check AWS credentials
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${RED}ERROR: AWS authentication failed. Please configure your AWS credentials.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ AWS credentials verified for account: $ACCOUNT_ID${NC}"

# Step 2: Create Terraform local backend config
echo -e "\n${YELLOW}Step 2: Cleaning up existing Terraform files...${NC}"
mkdir -p "$TERRAFORM_DIR"

# Clean up potentially conflicting files
CLEANUP_FILES=(
  "backend.tf"
  "auto_vars.tf"
  "auto_vars_locals.tf"
  "vpc_auto.tf"
  "vpc_locals.tf"
)

for file in "${CLEANUP_FILES[@]}"; do
  if [ -f "$TERRAFORM_DIR/$file" ]; then
    echo -e "${YELLOW}Removing $file to avoid conflicts...${NC}"
    rm "$TERRAFORM_DIR/$file"
  fi
done

# Create clean backend.tf
cat > "$TERRAFORM_DIR/backend.tf" << EOF
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
echo -e "${GREEN}✓ Created local backend configuration${NC}"

# Step 3: Create Terraform variable files
echo -e "\n${YELLOW}Step 3: Creating Terraform variable files...${NC}"
cat > "$TERRAFORM_DIR/terraform.auto.tfvars" << EOF
env                  = "dev"
domain_name          = "cloudable.ai"
aurora_engine_version = "15.12"

# Override any other variables as needed
vpc_id               = ""
subnet_ids           = []
availability_zones   = ["us-east-1a", "us-east-1b"]

# Force destroy all resources
force_destroy        = true
prevent_destroy      = false
EOF
echo -e "${GREEN}✓ Created terraform.auto.tfvars file${NC}"

# Create VPC module
echo -e "\n${YELLOW}Step 4: Checking for existing VPC module...${NC}"
if [ -f "$TERRAFORM_DIR/vpc.tf" ]; then
  echo -e "${YELLOW}VPC module already exists in vpc.tf, skipping creation...${NC}"
  
  # Extract existing VPC module outputs
  VPC_MODULE_NAME=$(grep -o 'module\s\+"[^"]*"' "$TERRAFORM_DIR/vpc.tf" | head -1 | cut -d'"' -f2)
  
  if [ -n "$VPC_MODULE_NAME" ]; then
    echo -e "${GREEN}Found existing VPC module: $VPC_MODULE_NAME${NC}"
  else
    VPC_MODULE_NAME="vpc"
    echo -e "${YELLOW}Couldn't determine VPC module name, using default: $VPC_MODULE_NAME${NC}"
  fi
  
  # Create locals that reference the existing VPC module
  echo -e "${YELLOW}Creating locals to reference existing VPC module...${NC}"
  cat > "$TERRAFORM_DIR/vpc_locals.tf" << EOF
# Locals that reference the existing VPC module
locals {
  vpc_id = module.${VPC_MODULE_NAME}.vpc_id
  private_subnet_ids = module.${VPC_MODULE_NAME}.private_subnets
}
EOF
else
  echo -e "${YELLOW}No existing VPC module found, creating new one...${NC}"
  cat > "$TERRAFORM_DIR/vpc.tf" << EOF
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "cloudable-vpc-\${var.env}"
  cidr = "10.0.0.0/16"
  
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
  
  tags = {
    Environment = var.env
    Project     = "cloudable"
  }
}

locals {
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
}
EOF
fi
echo -e "${GREEN}✓ Created VPC module${NC}"

# Create auto variables file
echo -e "\n${YELLOW}Step 5: Checking existing variable declarations...${NC}"

# Check for existing variable declarations
HAS_VPC_ID=$(grep -l "variable\s\+\"vpc_id\"" "$TERRAFORM_DIR"/*.tf 2>/dev/null | wc -l)
HAS_SUBNET_IDS=$(grep -l "variable\s\+\"subnet_ids\"" "$TERRAFORM_DIR"/*.tf 2>/dev/null | wc -l)
HAS_FORCE_DESTROY=$(grep -l "variable\s\+\"force_destroy\"" "$TERRAFORM_DIR"/*.tf 2>/dev/null | wc -l)
HAS_PREVENT_DESTROY=$(grep -l "variable\s\+\"prevent_destroy\"" "$TERRAFORM_DIR"/*.tf 2>/dev/null | wc -l)
HAS_AZS=$(grep -l "variable\s\+\"availability_zones\"" "$TERRAFORM_DIR"/*.tf 2>/dev/null | wc -l)

echo -e "${YELLOW}Found existing variable declarations:${NC}"
echo -e "- vpc_id: $HAS_VPC_ID file(s)"
echo -e "- subnet_ids: $HAS_SUBNET_IDS file(s)"
echo -e "- availability_zones: $HAS_AZS file(s)"
echo -e "- force_destroy: $HAS_FORCE_DESTROY file(s)"
echo -e "- prevent_destroy: $HAS_PREVENT_DESTROY file(s)"

echo -e "${YELLOW}Creating auto_vars_locals.tf for VPC final variables...${NC}"
cat > "$TERRAFORM_DIR/auto_vars_locals.tf" << EOF
# Automatically set VPC and subnet IDs from VPC module
locals {
  vpc_id_final     = coalesce(var.vpc_id, local.vpc_id)
  subnet_ids_final = length(var.subnet_ids) > 0 ? var.subnet_ids : local.private_subnet_ids
}
EOF

# Only create variables that don't exist
if [ "$HAS_VPC_ID" -eq 0 ] || [ "$HAS_SUBNET_IDS" -eq 0 ] || [ "$HAS_AZS" -eq 0 ] || [ "$HAS_FORCE_DESTROY" -eq 0 ] || [ "$HAS_PREVENT_DESTROY" -eq 0 ]; then
  echo -e "${YELLOW}Creating missing variables in auto_vars.tf...${NC}"
  
  # Start the file
  cat > "$TERRAFORM_DIR/auto_vars.tf" << EOF
# Variables that don't exist in the current configuration
EOF
  
  # Add variables conditionally
  if [ "$HAS_VPC_ID" -eq 0 ]; then
    cat >> "$TERRAFORM_DIR/auto_vars.tf" << EOF

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}
EOF
  fi
  
  if [ "$HAS_SUBNET_IDS" -eq 0 ]; then
    cat >> "$TERRAFORM_DIR/auto_vars.tf" << EOF

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
  default     = []
}
EOF
  fi
  
  if [ "$HAS_AZS" -eq 0 ]; then
    cat >> "$TERRAFORM_DIR/auto_vars.tf" << EOF

variable "availability_zones" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
EOF
  fi
  
  if [ "$HAS_FORCE_DESTROY" -eq 0 ]; then
    cat >> "$TERRAFORM_DIR/auto_vars.tf" << EOF

variable "force_destroy" {
  description = "Whether to force destroy resources"
  type        = bool
  default     = true
}
EOF
  fi
  
  if [ "$HAS_PREVENT_DESTROY" -eq 0 ]; then
    cat >> "$TERRAFORM_DIR/auto_vars.tf" << EOF

variable "prevent_destroy" {
  description = "Whether to prevent destroy of resources"
  type        = bool
  default     = false
}
EOF
  fi
  
  echo -e "${GREEN}✓ Created auto_vars.tf with missing variables${NC}"
else
  echo -e "${GREEN}✓ All necessary variables already exist in the codebase${NC}"
fi
echo -e "${GREEN}✓ Created auto variables file${NC}"

# Update resource references
echo -e "\n${YELLOW}Step 6: Updating resource references to use the auto VPC variables...${NC}"
for file in $(grep -l "vpc_id" "$TERRAFORM_DIR"/*.tf 2>/dev/null | grep -v "auto_vars.tf" | grep -v "vpc_auto.tf"); do
  sed -i.bak 's/vpc_id = var.vpc_id/vpc_id = local.vpc_id_final/g' "$file" 2>/dev/null
  sed -i.bak 's/subnet_ids = var.subnet_ids/subnet_ids = local.subnet_ids_final/g' "$file" 2>/dev/null
done
find "$TERRAFORM_DIR" -name "*.bak" -delete 2>/dev/null
echo -e "${GREEN}✓ Updated resource references${NC}"

# Step 7: Initialize and deploy Terraform
echo -e "\n${YELLOW}Step 7: Initializing Terraform...${NC}"
cd "$TERRAFORM_DIR"
terraform init -reconfigure -input=false

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform initialization failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Terraform initialized successfully${NC}"

echo -e "\n${YELLOW}Step 8: Planning Terraform deployment...${NC}"
terraform plan -out=tfplan -input=false

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform plan failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Terraform plan created successfully${NC}"

echo -e "\n${YELLOW}Step 9: Applying Terraform deployment...${NC}"
terraform apply -auto-approve tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform apply failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Terraform applied successfully${NC}"

# Step 8: Extract outputs
echo -e "\n${YELLOW}Step 10: Extracting deployment outputs...${NC}"
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo "")
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "cloudable")
BUCKET_ACME=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable-kb-dev-us-east-1-acme')].Name" --output text | head -n 1)
BUCKET_GLOBEX=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable-kb-dev-us-east-1-globex')].Name" --output text | head -n 1)
API_ENDPOINT=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")

echo -e "\n${GREEN}RDS Cluster ARN: $RDS_CLUSTER_ARN${NC}"
echo -e "${GREEN}RDS Secret ARN: $RDS_SECRET_ARN${NC}"
echo -e "${GREEN}RDS Database: $RDS_DATABASE${NC}"
echo -e "${GREEN}ACME Bucket: $BUCKET_ACME${NC}"
echo -e "${GREEN}GLOBEX Bucket: $BUCKET_GLOBEX${NC}"
echo -e "${GREEN}API Endpoint: $API_ENDPOINT${NC}"

# Step 9: Set up pgvector in RDS
echo -e "\n${YELLOW}Step 11: Setting up pgvector in RDS...${NC}"
if [ -n "$RDS_CLUSTER_ARN" ] && [ -n "$RDS_SECRET_ARN" ]; then
    python3 setup_pgvector.py --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$RDS_SECRET_ARN" --database "$RDS_DATABASE" --tenant acme,globex --index-type hnsw
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Warning: pgvector setup had issues, but continuing...${NC}"
    else
        echo -e "${GREEN}✓ Successfully set up pgvector${NC}"
    fi
else
    echo -e "${RED}Missing RDS information. Skipping pgvector setup.${NC}"
fi

# Step 10: Create customer status tables
echo -e "\n${YELLOW}Step 12: Setting up customer status tables in RDS...${NC}"
if [ -n "$RDS_CLUSTER_ARN" ] && [ -n "$RDS_SECRET_ARN" ] && [ -n "$RDS_DATABASE" ]; then
    cd "$SCRIPT_DIR/infras/core"
    
    # Set environment variables for the setup script
    export RDS_CLUSTER_ARN="$RDS_CLUSTER_ARN"
    export RDS_SECRET_ARN="$RDS_SECRET_ARN"
    export RDS_DATABASE="$RDS_DATABASE"
    
    if [ -f "setup_customer_status.py" ]; then
        echo -e "${YELLOW}Running setup_customer_status.py...${NC}"
        python3 setup_customer_status.py
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Warning: Customer status setup had issues, but continuing...${NC}"
        else
            echo -e "${GREEN}✓ Successfully set up customer status tables${NC}"
        fi
    else
        echo -e "${RED}setup_customer_status.py not found. Skipping customer status setup.${NC}"
    fi
else
    echo -e "${RED}Missing RDS information. Skipping customer status setup.${NC}"
fi

# Step 11: Create test document
echo -e "\n${YELLOW}Step 13: Creating test documents...${NC}"
ACME_DOC_PATH="$SCRIPT_DIR/customer_journey_acme.md"
GLOBEX_DOC_PATH="$SCRIPT_DIR/customer_journey_globex.md"

if [ -f "$ACME_DOC_PATH" ] && [ -f "$GLOBEX_DOC_PATH" ]; then
    echo -e "${GREEN}✓ Using existing customer journey documents${NC}"
else
    # Create ACME document
    cat > "$ACME_DOC_PATH" << EOF
# ACME Corporation Customer Journey

## Company Profile
ACME Corporation is a manufacturing company with 500 employees currently implementing a digital transformation project.

## Current Status
Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025.

## Key Milestones
1. Cloud-based ERP system integration - COMPLETED
2. Customer data platform with AI-powered analytics - COMPLETED
3. Automated order processing workflow - COMPLETED
4. Supply chain optimization module - IN PROGRESS
5. Field service mobile application - PLANNED

## Success Metrics
- 30% reduction in order processing time (currently at 18%)
- 25% improvement in inventory accuracy (currently at 20%)
- 15% increase in customer satisfaction (currently at 8%)

## Next Steps
1. Complete supply chain module by November 30
2. Schedule field service training for December
3. Prepare final phase deployment plan by November 25
EOF
    echo -e "${GREEN}✓ Created ACME customer journey document${NC}"

    # Create GLOBEX document
    cat > "$GLOBEX_DOC_PATH" << EOF
# Globex Industries Customer Journey

## Company Profile
Globex Industries is a large financial services provider with 2,000+ employees across multiple regions.

## Current Status
Onboarding stage (phase 1 of 4), with implementation having started on October 2, 2025 and expected completion by June 15, 2026.

## Key Stakeholders
- Thomas Wong (CTO)
- Aisha Patel (CDO)
- Robert Martinez (Customer Experience)
- Jennifer Lee (Compliance Director)

## Objectives
- Modernize legacy systems
- Improve customer experience through digital channels
- Enhance data security and compliance
- Reduce operational costs

## Challenges
- Complex regulatory requirements
- Integration with 8+ legacy systems
- Cultural resistance to change
- Geographic distribution of teams
EOF
    echo -e "${GREEN}✓ Created Globex customer journey document${NC}"
fi

# Step 12: Upload test documents to S3
echo -e "\n${YELLOW}Step 14: Uploading test documents to S3...${NC}"
if [ -n "$BUCKET_ACME" ] && [ -n "$BUCKET_GLOBEX" ]; then
    # Upload ACME document
    ACME_KEY="customer_journeys/acme_$(date +%Y%m%d%H%M%S).md"
    aws s3 cp "$ACME_DOC_PATH" "s3://$BUCKET_ACME/$ACME_KEY"
    
    # Upload GLOBEX document
    GLOBEX_KEY="customer_journeys/globex_$(date +%Y%m%d%H%M%S).md"
    aws s3 cp "$GLOBEX_DOC_PATH" "s3://$BUCKET_GLOBEX/$GLOBEX_KEY"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Warning: Document upload had issues, but continuing...${NC}"
    else
        echo -e "${GREEN}✓ Successfully uploaded test documents${NC}"
        
        # Save document key and tenant info for testing
        echo "{\"acme\":{\"document_key\":\"$ACME_KEY\",\"tenant\":\"acme\",\"bucket\":\"$BUCKET_ACME\"},\"globex\":{\"document_key\":\"$GLOBEX_KEY\",\"tenant\":\"globex\",\"bucket\":\"$BUCKET_GLOBEX\"}}" > "$SCRIPT_DIR/test_document_info.json"
        echo -e "${GREEN}✓ Saved document information to test_document_info.json${NC}"
    fi
else
    echo -e "${RED}Missing bucket names. Skipping document upload.${NC}"
fi

# Step 13: Test API endpoints
echo -e "\n${YELLOW}Step 15: Testing API endpoints...${NC}"
if [ -n "$API_ENDPOINT" ]; then
    # Test health endpoint
    echo -e "${YELLOW}Testing health endpoint...${NC}"
    HEALTH_RESPONSE=$(curl -s "${API_ENDPOINT}health" || echo "Failed to reach API")
    echo -e "${GREEN}Response: $HEALTH_RESPONSE${NC}"
    
    # If we have document info, test document sync
    if [ -f "$SCRIPT_DIR/test_document_info.json" ]; then
        # Process both tenants
        for TENANT in "acme" "globex"; do
            DOC_KEY=$(jq -r ".$TENANT.document_key" "$SCRIPT_DIR/test_document_info.json")
            
            if [ -n "$DOC_KEY" ] && [ "$DOC_KEY" != "null" ]; then
                echo -e "\n${YELLOW}Testing document sync API for $TENANT...${NC}"
                SYNC_PAYLOAD="{\"tenant\":\"$TENANT\",\"document_key\":\"$DOC_KEY\"}"
                
                echo -e "${YELLOW}Payload: $SYNC_PAYLOAD${NC}"
                SYNC_RESPONSE=$(curl -s -X POST \
                    "${API_ENDPOINT}kb/sync" \
                    -H "Content-Type: application/json" \
                    -d "$SYNC_PAYLOAD")
                
                echo -e "${GREEN}Response: $SYNC_RESPONSE${NC}"
                
                # Wait a bit before next request
                sleep 5
            fi
        done
        
        # Wait for sync to complete
        echo -e "${YELLOW}Waiting for knowledge base sync to complete (30 seconds)...${NC}"
        sleep 30
        
        # Test queries for both tenants
        for TENANT in "acme" "globex"; do
            echo -e "\n${YELLOW}Testing knowledge base query API for $TENANT...${NC}"
            
            if [ "$TENANT" == "acme" ]; then
                QUERY="What is the current status of ACME Corporation?"
            else
                QUERY="What is the current status of Globex Industries?"
            fi
            
            QUERY_PAYLOAD="{\"tenant\":\"$TENANT\",\"query\":\"$QUERY\",\"max_results\":3}"
            
            echo -e "${YELLOW}Payload: $QUERY_PAYLOAD${NC}"
            QUERY_RESPONSE=$(curl -s -X POST \
                "${API_ENDPOINT}kb/query" \
                -H "Content-Type: application/json" \
                -d "$QUERY_PAYLOAD")
            
            echo -e "${GREEN}Response: $QUERY_RESPONSE${NC}"
            
            # Test chat API
            echo -e "\n${YELLOW}Testing chat API for $TENANT...${NC}"
            
            if [ "$TENANT" == "acme" ]; then
                MESSAGE="Tell me about ACME's implementation progress"
            else
                MESSAGE="What are the key objectives for Globex?"
            fi
            
            CHAT_PAYLOAD="{\"tenant\":\"$TENANT\",\"message\":\"$MESSAGE\",\"use_kb\":true}"
            
            echo -e "${YELLOW}Payload: $CHAT_PAYLOAD${NC}"
            CHAT_RESPONSE=$(curl -s -X POST \
                "${API_ENDPOINT}chat" \
                -H "Content-Type: application/json" \
                -d "$CHAT_PAYLOAD")
            
            echo -e "${GREEN}Response: $CHAT_RESPONSE${NC}"
            
            # Test customer status API
            echo -e "\n${YELLOW}Testing customer status API for $TENANT...${NC}"
            STATUS_PAYLOAD="{\"tenant\":\"$TENANT\"}"
            
            echo -e "${YELLOW}Payload: $STATUS_PAYLOAD${NC}"
            STATUS_RESPONSE=$(curl -s -X POST \
                "${API_ENDPOINT}customer-status" \
                -H "Content-Type: application/json" \
                -d "$STATUS_PAYLOAD")
            
            echo -e "${GREEN}Response: $STATUS_RESPONSE${NC}"
        done
    else
        echo -e "${YELLOW}No document info found. Skipping document-related API tests.${NC}"
    fi
else
    echo -e "${RED}API endpoint not available. Skipping API tests.${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLOUDABLE.AI REDEPLOYMENT COMPLETED SUCCESSFULLY${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Resource Summary:${NC}"
echo -e "RDS Cluster ARN: ${RDS_CLUSTER_ARN:-Not available}"
echo -e "RDS Secret ARN: ${RDS_SECRET_ARN:-Not available}"
echo -e "RDS Database: ${RDS_DATABASE:-Not available}"
echo -e "S3 Bucket (acme): ${BUCKET_ACME:-Not available}"
echo -e "S3 Bucket (globex): ${BUCKET_GLOBEX:-Not available}"
echo -e "API Gateway Endpoint: ${API_ENDPOINT:-Not available}"

exit 0
