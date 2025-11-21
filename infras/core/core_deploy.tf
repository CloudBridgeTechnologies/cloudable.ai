provider "aws" {
  region = "eu-west-1"
}

# Use local backend
terraform {
  backend "local" {
    path = "terraform.tfstate.core"
  }
}

# Use existing VPC - DO NOT CREATE OR DESTROY
# The VPC vpc-095b26e71fd22e225 is in use by the RDS cluster
# We reference it directly to prevent Terraform from trying to manage it
locals {
  vpc_id = "vpc-095b26e71fd22e225" # Existing VPC in eu-west-1 with RDS cluster - DO NOT DELETE
}

data "aws_subnets" "private" {
  count = 1
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  tags = {
    Name = "*private*"
  }
}

# Create subnets if needed
resource "aws_subnet" "private" {
  count = 2
  
  vpc_id            = "vpc-095b26e71fd22e225" # Hardcoded VPC ID
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = "eu-west-1${["a", "b"][count.index]}"
  
  tags = {
    Name = "cloudable-private-${count.index + 1}"
    Type = "private"
  }
}

# Create security group for RDS
resource "aws_security_group" "rds" {
  name        = "aurora-dev-sg-core"
  description = "Security group for Aurora RDS"
  vpc_id      = "vpc-095b26e71fd22e225" # Hardcoded VPC ID
  
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = {
    Name = "cloudable-aurora-sg"
  }
}

# Create subnet group for RDS
resource "aws_db_subnet_group" "aurora" {
  name_prefix = "cloudable-db-sg-"
  subnet_ids  = aws_subnet.private[*].id
  
  tags = {
    Name = "Cloudable DB Subnet Group"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Check if the RDS Secret already exists
# Create the secret for RDS credentials
resource "aws_secretsmanager_secret" "db_secret" {
  name        = "aurora-dev-admin-secret"
  description = "Aurora PostgreSQL admin credentials"
  
  tags = {
    Name        = "aurora-dev-admin-secret"
    Environment = "dev"
  }
}

# Create Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "aurora-dev-core-v2"
  engine                  = "aurora-postgresql"
  engine_version          = "15.12"
  database_name           = "cloudable"
  master_username         = "dbadmin"
  master_password         = "ComplexPassword123!"  # Would use random password in production
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  storage_encrypted       = true
  
  lifecycle {
    ignore_changes = [availability_zones]
  }
  
  skip_final_snapshot = true
  enable_http_endpoint = true
  
  engine_mode = "provisioned"
  
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1.0
  }
  
  tags = {
    Name        = "cloudable-aurora-cluster"
    Environment = "dev"
  }
}

# Create cluster instance
resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier           = "aurora-dev-instance-1-v3"
  cluster_identifier   = aws_rds_cluster.aurora.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.aurora.engine
  engine_version       = aws_rds_cluster.aurora.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  
  tags = {
    Name        = "cloudable-aurora-instance"
    Environment = "dev"
  }
}

# Update the secret with the RDS credentials
resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora.master_username
    password = aws_rds_cluster.aurora.master_password
    host     = aws_rds_cluster.aurora.endpoint
    port     = 5432
    dbname   = aws_rds_cluster.aurora.database_name
  })
}

# Define a basic Lambda function for the KB manager
resource "aws_iam_role" "lambda_role" {
  name = "kb-manager-role-core"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_rds" {
  name = "lambda_rds_access"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "secretsmanager:GetSecretValue",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Use the simplified Lambda function package
resource "local_file" "enhanced_lambda_zip" {
  filename = "${path.module}/lambda_function.zip"
  source   = "${path.module}/lambda_function_simple.zip"
}

# Reference the enhanced Lambda function for backward compatibility
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function_original.zip"
  
  source {
    content  = <<-EOF
    import json
    import os
    import boto3
    
    def handler(event, context):
        # Get the HTTP method and path
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        # For API Gateway proxy integrations
        if 'requestContext' in event and 'http' in event['requestContext']:
            http_method = event['requestContext']['http']['method']
            path = event['requestContext']['http']['path']
        
        # Process based on path
        if http_method == 'GET' and path.endswith('/health'):
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"message": "Cloudable.AI KB Manager API is operational"})
            }
        
        # Extract request body
        body = {}
        if 'body' in event:
            if isinstance(event['body'], str):
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    pass
            elif isinstance(event['body'], dict):
                body = event['body']
        
        # Handle KB sync endpoint
        if http_method == 'POST' and path.endswith('/kb/sync'):
            tenant = body.get('tenant', '')
            document_key = body.get('document_key', '')
            
            if not tenant or not document_key:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and document_key"})
                }
            
            # In a real implementation, this would trigger processing of the document
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "message": "Document sync initiated",
                    "tenant": tenant,
                    "document_key": document_key
                })
            }
        
        # Handle KB query endpoint
        if http_method == 'POST' and path.endswith('/kb/query'):
            tenant = body.get('tenant', '')
            query = body.get('query', '')
            max_results = body.get('max_results', 3)
            
            if not tenant or not query:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and query"})
                }
            
            # In a real implementation, this would query the vector database
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "results": [
                        {
                            "text": "Cloudable.AI provides vector similarity search using pgvector.",
                            "metadata": {"source": "test_document.md", "page": 1},
                            "score": 0.95
                        },
                        {
                            "text": "The technical stack includes AWS Lambda, RDS PostgreSQL, S3, Bedrock, and API Gateway.",
                            "metadata": {"source": "test_document.md", "page": 1},
                            "score": 0.92
                        }
                    ],
                    "query": query
                })
            }
        
        # Handle chat endpoint
        if http_method == 'POST' and path.endswith('/chat'):
            tenant = body.get('tenant', '')
            message = body.get('message', '')
            use_kb = body.get('use_kb', True)
            
            if not tenant or not message:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({"error": "Missing required parameters: tenant and message"})
                }
            
            # In a real implementation, this would interact with a language model
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    "response": "Cloudable.AI is a knowledge base system that supports vector similarity search, multi-tenant architecture, document processing, and integration with AWS Bedrock for embeddings.",
                    "source_documents": [] if not use_kb else [
                        {"text": "Cloudable.AI Test Document", "metadata": {"source": "test_document.md"}}
                    ]
                })
            }
        
        # Default response for unsupported paths
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": "Not Found"})
        }
    EOF
    filename = "lambda_function.py"
  }
}

# Create the Lambda function
resource "aws_lambda_function" "kb_manager" {
  function_name    = "kb-manager-dev-core"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function_simple.handler"
  runtime          = "python3.9"
  filename         = "${path.module}/lambda_function_simple.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_function_simple.zip")
  
  environment {
    variables = {
      RDS_CLUSTER_ARN = aws_rds_cluster.aurora.arn
      RDS_SECRET_ARN  = aws_secretsmanager_secret.db_secret.arn
      RDS_DATABASE    = aws_rds_cluster.aurora.database_name
      # AWS_REGION is automatically set by Lambda based on deployment region (eu-west-1)
    }
  }
  
  tags = {
    Environment = "dev"
  }
}

# Create an API Gateway
resource "aws_apigatewayv2_api" "kb_api" {
  name          = "cloudable-kb-api-core"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["*"]
  }
}

# Create a stage
resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.kb_api.id
  name        = "dev"
  auto_deploy = true
}

# Create API integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.kb_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.kb_manager.invoke_arn
  integration_method = "POST"
}

# Create route for health check
resource "aws_apigatewayv2_route" "health_route" {
  api_id    = aws_apigatewayv2_api.kb_api.id
  route_key = "GET /api/health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create route for upload URL
resource "aws_apigatewayv2_route" "upload_url_route" {
  api_id    = aws_apigatewayv2_api.kb_api.id
  route_key = "POST /api/upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create route for KB sync
resource "aws_apigatewayv2_route" "kb_sync_route" {
  api_id    = aws_apigatewayv2_api.kb_api.id
  route_key = "POST /api/kb/sync"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create route for KB query
resource "aws_apigatewayv2_route" "kb_query_route" {
  api_id    = aws_apigatewayv2_api.kb_api.id
  route_key = "POST /api/kb/query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create route for chat
resource "aws_apigatewayv2_route" "chat_route" {
  api_id    = aws_apigatewayv2_api.kb_api.id
  route_key = "POST /api/chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create route for customer status
resource "aws_apigatewayv2_route" "customer_status_route" {
  api_id    = aws_apigatewayv2_api.kb_api.id
  route_key = "POST /api/customer-status"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Grant API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.kb_api.execution_arn}/*/*"
}

# Output important values
output "rds_cluster_arn" {
  description = "ARN of the RDS cluster"
  value       = aws_rds_cluster.aurora.arn
}

output "rds_cluster_endpoint" {
  description = "Endpoint of the RDS cluster"
  value       = aws_rds_cluster.aurora.endpoint
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_apigatewayv2_stage.dev.invoke_url}"
}
