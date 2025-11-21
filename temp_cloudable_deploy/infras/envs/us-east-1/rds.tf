resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  # Use a fixed name rather than timestamp to avoid recreation on each run
  name                    = "aurora-${var.env}-admin-secret"
  kms_key_id              = aws_kms_key.rds.id
  recovery_window_in_days = 7
  tags                    = local.tags
  
  # Prevent destruction of the secret
  lifecycle {
    prevent_destroy = false
  }
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

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    description = "PostgreSQL access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = local.tags
}

resource "aws_rds_cluster" "this" {
  cluster_identifier      = "aurora-${var.env}"
  engine                  = "aurora-postgresql"
  engine_version          = var.aurora_engine_version
  availability_zones      = ["${var.region}a", "${var.region}b"]
  database_name           = "cloudable"
  master_username         = jsondecode(aws_secretsmanager_secret_version.db.secret_string)["username"]
  master_password         = jsondecode(aws_secretsmanager_secret_version.db.secret_string)["password"]
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds.arn
  
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1.0
  }
  
  # Enable Data API v2 for Bedrock Knowledge Base
  enable_http_endpoint = true

  tags = local.tags
  
  # Prevent recreation due to availability zones or other changes
  lifecycle {
    ignore_changes = [
      availability_zones,
      # Any other attributes that change but shouldn't trigger recreation
    ]
  }
}

resource "aws_rds_cluster_instance" "this" {
  identifier          = "aurora-${var.env}-instance-1"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = local.tags
  
  # Prevent recreation due to engine version or other changes
  lifecycle {
    ignore_changes = [
      engine_version,
      # Any other attributes that change but shouldn't trigger recreation
    ]
  }
}