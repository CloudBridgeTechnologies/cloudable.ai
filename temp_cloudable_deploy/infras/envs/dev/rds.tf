resource "random_password" "db" {
  length  = 24
  special = true
}

resource "aws_secretsmanager_secret" "db" {
  name       = "aurora-${var.env}-admin"
  kms_key_id = aws_kms_key.rds.id
  tags       = local.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db.result
  })
}

resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-${var.env}-subnets"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

resource "aws_security_group" "aurora" {
  name        = "aurora-${var.env}-sg"
  description = "Aurora access"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

resource "aws_rds_cluster" "this" {
  cluster_identifier      = "aurora-${var.env}"
  engine                  = "aurora-postgresql"
  engine_version          = var.aurora_engine_version
  master_username         = jsondecode(aws_secretsmanager_secret_version.db.secret_string)["username"]
  master_password         = jsondecode(aws_secretsmanager_secret_version.db.secret_string)["password"]
  database_name           = "cloudable"
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds.arn
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  deletion_protection     = false
  enable_http_endpoint    = true
  skip_final_snapshot     = true
  tags                    = local.tags

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4
  }
}

resource "aws_rds_cluster_instance" "this" {
  identifier          = "aurora-${var.env}-instance-1"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false
  tags                = local.tags
}

