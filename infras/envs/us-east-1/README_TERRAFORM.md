# Cloudable.AI Terraform Deployment

This guide covers the complete deployment of the Cloudable.AI platform with RDS PostgreSQL and pgvector support.

## Overview

The Terraform configuration sets up a complete, production-ready Cloudable.AI environment including:

1. **Aurora PostgreSQL** cluster with pgvector extension
2. **Lambda functions** for KB management with pgvector compatibility
3. **S3 buckets** for tenant document storage
4. **Bedrock knowledge bases** configured with RDS pgvector storage
5. **IAM roles and policies** with least privilege access
6. **CloudWatch logs and metrics** for monitoring and alerting
7. **Security groups** for network isolation
8. **KMS keys** for encryption at rest

## Prerequisites

Before deployment, ensure you have:

- **AWS CLI** installed and configured
- **Terraform** v1.0.0+ installed
- An existing **VPC** and **subnets** in your target AWS account
- Appropriate **AWS permissions** to create the resources

## Deployment Steps

### 1. Preparation

Set up your AWS credentials:

```bash
aws configure
```

### 2. Review Configuration Files

Review and edit the following files if needed:

- `cloudable-pgvector.tf` - Main infrastructure 
- `kb-lambda.tf` - Lambda function with pgvector fixes
- `setup_pgvector.py` - pgvector initialization script

### 3. Automated Deployment

The easiest way to deploy is using the provided script:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will:
1. Check prerequisites
2. Get VPC and subnet information
3. Create terraform.tfvars file
4. Initialize and validate Terraform
5. Plan and apply the deployment
6. Run end-to-end tests
7. Display output information

### 4. Manual Deployment

If you prefer to deploy manually:

1. Create a `terraform.tfvars` file:

```hcl
region      = "us-east-1"
environment = "dev"
vpc_id      = "vpc-12345678"
subnet_ids  = ["subnet-12345678", "subnet-87654321"]
tenant_ids  = ["acme", "globex", "t001"]
db_name     = "cloudable"
```

2. Initialize Terraform:

```bash
terraform init
```

3. Plan the deployment:

```bash
terraform plan -out=cloudable.tfplan
```

4. Apply the plan:

```bash
terraform apply cloudable.tfplan
```

## Verification

After deployment:

1. Check that the RDS cluster is available:

```bash
aws rds describe-db-clusters --db-cluster-identifier aurora-dev
```

2. Check that the Lambda functions are deployed:

```bash
aws lambda get-function --function-name kb-manager-dev
```

3. Run the end-to-end test:

```bash
./e2e_rds_pgvector_test.sh
```

## Configuration Details

### PostgreSQL with pgvector

The deployment configures:

- pgvector extension enabled in RDS
- tenant-specific vector tables
- HNSW vector indexes for efficient similarity search
- Text search indexes for hybrid search capabilities
- Metadata search indexes for filtering

### Lambda Functions

The KB Manager Lambda function includes:

- Vector format fixes for pgvector compatibility (brackets instead of braces)
- RDS Data API parameter handling
- JSON parsing improvements
- Error logging and monitoring

## Security Considerations

The deployment includes several security best practices:

- **Least privilege IAM policies**
- **VPC isolation** for Lambda and RDS
- **KMS encryption** for S3 and RDS
- **Secret rotation** for database credentials
- **CloudWatch Logs** with encryption

## Monitoring and Alerting

CloudWatch metrics are set up for:

- **Vector query duration**
- **Query result counts**
- **Lambda execution time**
- **Error rates**

## Clean Up

To remove all resources:

```bash
terraform destroy
```

## Troubleshooting

If you encounter issues:

1. **Lambda deployment fails**:
   - Check Lambda logs in CloudWatch
   - Verify IAM permissions

2. **RDS initialization fails**:
   - Check that pgvector extension is supported in your RDS version
   - Verify RDS parameter group settings

3. **Vector search not working**:
   - Check the format of vectors in your code (should use brackets [1,2,3])
   - Verify that the Lambda function is using the correct RDS endpoints

4. **End-to-end test fails**:
   - Check CloudWatch logs for the KB Manager Lambda
   - Verify S3 bucket permissions
   - Check that the RDS cluster is accessible from the Lambda function

## Advanced Configuration

For advanced scenarios, you can:

- Adjust the RDS instance size in the tfvars
- Change the pgvector index type from HNSW to IVF-Flat
- Modify the vector dimensions (default: 1536)
- Add CloudFront distributions for frontend assets
