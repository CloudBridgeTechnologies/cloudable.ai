###############################################
# Main Terraform Configuration
###############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.20"
    }
  }
  
  # Using local backend for simplicity
  # In production, would use S3 backend with DynamoDB for state locking
  backend "local" {
    path = "terraform.tfstate"
  }
  
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Cloudable.AI"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.kb_manager.function_name
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "${aws_apigatewayv2_api.cloudable_api.api_endpoint}/${aws_apigatewayv2_stage.dev.name}"
}

output "rds_cluster_endpoint" {
  description = "Endpoint of the RDS cluster"
  value       = aws_rds_cluster.aurora_cluster.endpoint
}

output "rds_cluster_arn" {
  description = "ARN of the RDS cluster"
  value       = aws_rds_cluster.aurora_cluster.arn
}

output "rds_secret_arn" {
  description = "ARN of the RDS secret"
  value       = aws_secretsmanager_secret.aurora_secret.arn
}
