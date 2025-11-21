# Terraform configuration to update Lambda function for pgvector compatibility

# Local variables
locals {
  kb_manager_function_name = "kb-manager-dev"
  lambda_source_dir        = "${path.module}/../../lambdas/kb_manager"
  lambda_zip_file          = "${path.module}/lambda_package.zip"
  lambda_handler           = "main.handler"
  lambda_runtime           = "python3.12"
  
  # Environment variables needed for the Lambda function
  lambda_environment_variables = {
    RDS_CLUSTER_ARN = aws_rds_cluster.aurora_cluster.arn
    RDS_SECRET_ARN  = aws_secretsmanager_secret.aurora_secret.arn
    RDS_DATABASE    = "cloudable"
    
    # Preserve existing environment variables
    KB_ID_T001      = data.aws_lambda_function.kb_manager.environment[0].variables["KB_ID_T001"]
    DS_ID_T001      = data.aws_lambda_function.kb_manager.environment[0].variables["DS_ID_T001"]
    BUCKET_T001     = data.aws_lambda_function.kb_manager.environment[0].variables["BUCKET_T001"]
    KB_ID_T002      = data.aws_lambda_function.kb_manager.environment[0].variables["KB_ID_T002"]
    DS_ID_T002      = data.aws_lambda_function.kb_manager.environment[0].variables["DS_ID_T002"]
    BUCKET_T002     = data.aws_lambda_function.kb_manager.environment[0].variables["BUCKET_T002"]
    S3_KMS_KEY_ARN  = data.aws_lambda_function.kb_manager.environment[0].variables["S3_KMS_KEY_ARN"]
    CLAUDE_MODEL_ARN = data.aws_lambda_function.kb_manager.environment[0].variables["CLAUDE_MODEL_ARN"]
    ENV             = "dev"
    REGION          = "us-east-1"
  }
}

# Get existing Lambda function details
data "aws_lambda_function" "kb_manager" {
  function_name = local.kb_manager_function_name
}

# Data source for the Aurora RDS cluster
data "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier = "aurora-dev"
}

# Data source for the Secrets Manager secret
data "aws_secretsmanager_secret" "aurora_secret" {
  name = "aurora-dev-admin-secret"
}

# Create a Lambda deployment package from source directory
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = local.lambda_source_dir
  output_path = local.lambda_zip_file
  
  # Create pgvector_fix.py file to indicate the fix was applied
  dynamic "source" {
    for_each = [1]
    content {
      content = <<-EOF
        """
        This file indicates that the pgvector fix has been applied to the Lambda function.
        Fix applied: ${timestamp()}
        
        Changes made:
        1. Updated vector format for pgvector compatibility (using brackets instead of braces)
        2. Fixed JSON parsing in rest_adapter to handle both string and dict formats
        3. Changed vector parameter format for RDS Data API compatibility
        """
        
        # Version of the fix
        PGVECTOR_FIX_VERSION = '1.0.0'
      EOF
      filename = "pgvector_fix.py"
    }
  }
}

# Update the Lambda function
resource "aws_lambda_function" "kb_manager_update" {
  function_name    = local.kb_manager_function_name
  filename         = local.lambda_zip_file
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  # Keep existing configuration
  role             = data.aws_lambda_function.kb_manager.role
  handler          = local.lambda_handler
  runtime          = local.lambda_runtime
  memory_size      = data.aws_lambda_function.kb_manager.memory_size
  timeout          = data.aws_lambda_function.kb_manager.timeout
  
  # Update environment variables to include RDS connection parameters
  environment {
    variables = local.lambda_environment_variables
  }
  
  # Copy existing function tags
  tags = data.aws_lambda_function.kb_manager.tags
}

# Output for verification
output "lambda_update_status" {
  value = "Lambda function ${aws_lambda_function.kb_manager_update.function_name} updated with pgvector compatibility fixes"
}

output "lambda_version" {
  value = aws_lambda_function.kb_manager_update.version
}

output "lambda_last_modified" {
  value = aws_lambda_function.kb_manager_update.last_modified
}
