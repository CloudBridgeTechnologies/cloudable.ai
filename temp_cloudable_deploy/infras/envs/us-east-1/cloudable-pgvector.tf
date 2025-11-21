# Main Terraform configuration for Cloudable.AI with pgvector support
# This file sets up the complete infrastructure for the application including RDS with pgvector

# Provider configuration
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Cloudable.AI"
      ManagedBy   = "Terraform"
    }
  }
}

# Variables
variable "region" {
  description = "AWS region to deploy to"
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID for deployment"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for database and lambda deployment"
  type        = list(string)
}

variable "tenant_ids" {
  description = "List of tenant IDs to set up pgvector tables for"
  type        = list(string)
  default     = ["acme", "globex", "t001"]
}

variable "db_name" {
  description = "Name of the database"
  default     = "cloudable"
}

variable "db_master_username" {
  description = "Master username for the database"
  default     = "dbadmin"
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for database nodes"
  default     = "db.r6g.large"
}

# RDS Aurora PostgreSQL cluster with pgvector
resource "aws_rds_cluster_parameter_group" "pgvector_params" {
  name        = "cloudable-pgvector-${var.environment}"
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

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "cloudable-db-subnet-group-${var.environment}"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for Cloudable.AI RDS cluster"
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "aurora-${var.environment}-admin-secret"
  description = "Credentials for Cloudable.AI Aurora PostgreSQL cluster"
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username             = var.db_master_username
    password             = random_password.db_password.result
    engine               = "aurora-postgresql"
    host                 = aws_rds_cluster.aurora_cluster.endpoint
    port                 = aws_rds_cluster.aurora_cluster.port
    dbClusterIdentifier  = aws_rds_cluster.aurora_cluster.cluster_identifier
  })
}

resource "aws_security_group" "db_security_group" {
  name        = "cloudable-db-sg-${var.environment}"
  description = "Security group for Cloudable.AI database"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # Adjust this to your VPC CIDR
    description = "Allow PostgreSQL traffic from within VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_kms_key" "db_encryption_key" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier        = "aurora-${var.environment}"
  engine                    = "aurora-postgresql"
  engine_version            = "14.7"
  database_name             = var.db_name
  master_username           = var.db_master_username
  master_password           = random_password.db_password.result
  backup_retention_period   = 7
  preferred_backup_window   = "03:00-05:00"
  db_subnet_group_name      = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.db_security_group.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pgvector_params.name
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.db_encryption_key.arn
  
  # Enable Data API for Bedrock Knowledge Base
  enable_http_endpoint      = true
  
  skip_final_snapshot       = var.environment != "prod"  # Skip for non-prod environments
  final_snapshot_identifier = var.environment == "prod" ? "cloudable-final-snapshot-${formatdate("YYYYMMDDhhmmss", timestamp())}" : null
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count                   = 2  # Primary and standby instance
  identifier              = "aurora-${var.environment}-${count.index}"
  cluster_identifier      = aws_rds_cluster.aurora_cluster.id
  instance_class          = var.db_instance_class
  engine                  = "aurora-postgresql"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  publicly_accessible     = false
}

# Lambda function to initialize pgvector
resource "aws_lambda_function" "pgvector_setup" {
  function_name    = "pgvector-setup-${var.environment}"
  filename         = "${path.module}/pgvector_setup.zip"
  source_code_hash = filebase64sha256("${path.module}/pgvector_setup.zip")
  
  handler          = "setup_pgvector.handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 256
  
  role             = aws_iam_role.lambda_role.arn
  
  environment {
    variables = {
      CLUSTER_ARN  = aws_rds_cluster.aurora_cluster.arn
      SECRET_ARN   = aws_secretsmanager_secret.db_credentials.arn
      DATABASE     = var.db_name
      TENANT_LIST  = jsonencode(var.tenant_ids)
      INDEX_TYPE   = "hnsw"
      ENVIRONMENT  = var.environment
    }
  }
  
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  
  depends_on = [
    aws_rds_cluster_instance.aurora_instances
  ]
}

resource "aws_security_group" "lambda_sg" {
  name        = "cloudable-lambda-sg-${var.environment}"
  description = "Security group for Cloudable.AI Lambda functions"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "cloudable-lambda-role-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "cloudable-lambda-policy-${var.environment}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement"
        ]
        Effect   = "Allow"
        Resource = aws_rds_cluster.aurora_cluster.arn
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Data source for creating the Lambda deployment package
data "archive_file" "pgvector_setup_package" {
  type        = "zip"
  output_path = "${path.module}/pgvector_setup.zip"
  
  source {
    content  = file("${path.module}/setup_pgvector.py")
    filename = "setup_pgvector.py"
  }
  
  source {
    content  = <<-EOF
      import json
      import setup_pgvector

      def handler(event, context):
          """Lambda handler for pgvector setup"""
          import os
          import json
          
          # Get parameters from environment variables
          cluster_arn = os.environ.get('CLUSTER_ARN')
          secret_arn = os.environ.get('SECRET_ARN')
          database = os.environ.get('DATABASE', 'cloudable')
          tenant_list = json.loads(os.environ.get('TENANT_LIST', '["acme", "globex"]'))
          index_type = os.environ.get('INDEX_TYPE', 'hnsw')
          region = os.environ.get('AWS_REGION', 'us-east-1')
          
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
    filename = "lambda_handler.py"
  }
}

# Lambda function invocation to set up pgvector
resource "null_resource" "invoke_pgvector_setup" {
  triggers = {
    lambda_function = aws_lambda_function.pgvector_setup.arn
    tenants         = join(",", var.tenant_ids)
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda invoke \
        --function-name ${aws_lambda_function.pgvector_setup.function_name} \
        --region ${var.region} \
        --payload '{}' \
        /tmp/pgvector_setup_output.json
    EOT
  }

  depends_on = [aws_lambda_function.pgvector_setup]
}

# Output variables
output "rds_cluster_endpoint" {
  description = "The endpoint of the RDS cluster"
  value       = aws_rds_cluster.aurora_cluster.endpoint
}

output "rds_cluster_arn" {
  description = "The ARN of the RDS cluster"
  value       = aws_rds_cluster.aurora_cluster.arn
}

output "rds_secret_arn" {
  description = "The ARN of the RDS secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "pgvector_setup_lambda" {
  description = "The ARN of the pgvector setup Lambda function"
  value       = aws_lambda_function.pgvector_setup.arn
}
