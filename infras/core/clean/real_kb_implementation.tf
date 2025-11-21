# Real KB implementation with pgvector
# This file adds the real KB implementation to the existing infrastructure

# Enable pgvector in Aurora PostgreSQL
resource "aws_rds_cluster_parameter_group" "pgvector_params" {
  name        = "cloudable-pgvector-params-${terraform.workspace}"
  family      = "aurora-postgresql14"
  description = "Parameter group for pgvector extension"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pgvector"
  }

  parameter {
    name  = "rds.allowed_extensions"
    value = "vector,uuid-ossp,pg_stat_statements"
  }
}

# Update RDS cluster with pgvector parameter group
resource "aws_rds_cluster" "aurora" {
  # This is a resource update, not creation - the cluster already exists
  count = 0  # Not creating a new cluster, just updating through aws_rds_cluster_parameter_group_association

  # This is here to show what would be configured in a real deployment
  cluster_identifier      = "aurora-dev-core-v2"
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pgvector_params.name
}

# Associate the parameter group with the existing cluster
resource "aws_rds_cluster_parameter_group_association" "pgvector_association" {
  cluster_identifier  = "aurora-dev-core-v2"
  parameter_group_name = aws_rds_cluster_parameter_group.pgvector_params.name
}

# Lambda function to set up pgvector tables
resource "aws_lambda_function" "pgvector_setup" {
  function_name    = "pgvector-setup-eu-west-1"
  filename         = "${path.module}/pgvector_setup.zip"
  source_code_hash = filebase64sha256("${path.module}/pgvector_setup.zip")
  
  handler          = "setup_pgvector_lambda.handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 256
  
  role             = aws_iam_role.lambda_role.arn
  
  environment {
    variables = {
      RDS_CLUSTER_ARN = data.aws_rds_cluster.existing_cluster.arn
      RDS_SECRET_ARN  = data.aws_secretsmanager_secret.db_secret.arn
      RDS_DATABASE    = "cloudable"
      TENANT_LIST     = jsonencode(["acme", "globex"])
      INDEX_TYPE      = "hnsw"
      ENVIRONMENT     = "dev"
      AWS_REGION      = "eu-west-1"
    }
  }
}

# Update existing kb-manager-dev-core Lambda to use the real implementation
resource "aws_lambda_function" "kb_manager_real" {
  function_name    = "kb-manager-dev-core"
  filename         = "${path.module}/kb_manager_real.zip"
  source_code_hash = filebase64sha256("${path.module}/kb_manager_real.zip")
  
  handler          = "main.handler"
  runtime          = "python3.9"
  
  # Use existing role
  role             = aws_iam_role.lambda_role.arn
  
  # Add necessary environment variables
  environment {
    variables = {
      RDS_CLUSTER_ARN = data.aws_rds_cluster.existing_cluster.arn
      RDS_SECRET_ARN  = data.aws_secretsmanager_secret.db_secret.arn
      RDS_DATABASE    = "cloudable"
      REGION          = "eu-west-1"
      ENV             = "dev"
      
      # Tenant-specific config
      BUCKET_ACME     = "cloudable-kb-dev-eu-west-1-acme-20251114095518"
      BUCKET_GLOBEX   = "cloudable-kb-dev-eu-west-1-globex-20251114095518"
      
      # Use Claude 3 Sonnet for embeddings and retrieval
      CLAUDE_MODEL_ARN = "anthropic.claude-3-sonnet-20240229-v1:0"
    }
  }
  
  # Reuse existing configurations
  reserved_concurrent_executions = null
  memory_size = 512
  timeout     = 60
}

# Data sources to reference existing resources
data "aws_rds_cluster" "existing_cluster" {
  cluster_identifier = "aurora-dev-core-v2"
}

data "aws_secretsmanager_secret" "db_secret" {
  name = "aurora-dev-admin-secret"
}

# Create a pgvector setup package
data "archive_file" "pgvector_setup_package" {
  type        = "zip"
  output_path = "${path.module}/pgvector_setup.zip"
  
  source {
    content  = file("${path.module}/setup_pgvector.py")
    filename = "setup_pgvector.py"
  }
  
  source {
    content  = <<-EOF
      #!/usr/bin/env python3
      import json
      import os
      import setup_pgvector

      def handler(event, context):
          """Lambda handler for pgvector setup"""
          # Get parameters from environment variables
          cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
          secret_arn = os.environ.get('RDS_SECRET_ARN')
          database = os.environ.get('RDS_DATABASE', 'cloudable')
          tenant_list = json.loads(os.environ.get('TENANT_LIST', '["acme", "globex"]'))
          index_type = os.environ.get('INDEX_TYPE', 'hnsw')
          region = os.environ.get('AWS_REGION', 'eu-west-1')
          
          # Set up args for the setup_pgvector.main function
          import sys
          sys.argv = [
              'setup_pgvector.py',
              '--cluster-arn', cluster_arn,
              '--secret-arn', secret_arn,
              '--database', database,
              '--region', region,
              '--index-type', index_type,
          ]
          
          # Add tenants to args
          for tenant in tenant_list:
              sys.argv.append('--tenants')
              sys.argv.append(tenant)
          
          # Run the setup
          try:
              setup_pgvector.main()
              return {
                  'statusCode': 200,
                  'body': json.dumps('PGVector setup completed successfully')
              }
          except Exception as e:
              print(f"Error setting up pgvector: {e}")
              return {
                  'statusCode': 500,
                  'body': json.dumps(f'Error setting up pgvector: {str(e)}')
              }
    EOF
    filename = "setup_pgvector_lambda.py"
  }
}
