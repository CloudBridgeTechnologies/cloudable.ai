data "archive_file" "db_actions_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/db_actions"
  output_path = "${path.module}/db-actions.zip"
}

resource "aws_iam_role" "db_actions" {
  name               = "db-actions-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "db_actions" {
  role = aws_iam_role.db_actions.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.db.arn },
      { Effect = "Allow", Action = ["rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement", "rds-data:BeginTransaction", "rds-data:RollbackTransaction", "rds-data:CommitTransaction"], Resource = aws_rds_cluster.this.arn },
      { Effect = "Allow", Action = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"], Resource = "*" }
    ]
  })
}

resource "aws_lambda_function" "db_actions" {
  function_name = "db-actions-${var.env}"
  role          = aws_iam_role.db_actions.arn
  filename      = data.archive_file.db_actions_zip.output_path
  source_code_hash = data.archive_file.db_actions_zip.output_base64sha256
  handler       = "main.handler"
  runtime       = "python3.12"
  timeout       = 15
  environment {
    variables = {
      DB_CLUSTER_ARN = aws_rds_cluster.this.arn
      DB_SECRET_ARN  = aws_secretsmanager_secret.db.arn
      DB_NAME        = "cloudable"
    }
  }
  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.aurora.id]
  }
  tags = local.tags
}

resource "aws_lambda_permission" "allow_bedrock_invoke_db_actions" {
  statement_id  = "AllowBedrockInvokeDbActions"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_actions.arn
  principal     = "bedrock.amazonaws.com"
}

