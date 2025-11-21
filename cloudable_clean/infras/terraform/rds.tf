###############################################
# RDS Aurora PostgreSQL Cluster
###############################################

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier      = "aurora-dev-core-v2"
  engine                  = "aurora-postgresql"
  engine_version          = "15.12"
  database_name           = "cloudable"
  master_username         = "dbadmin"
  master_password         = "ComplexPassword123!"  # Would use random password in production
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.aurora_subnet_group.name
  storage_encrypted       = true
  
  lifecycle {
    ignore_changes = [availability_zones]
  }
  
  skip_final_snapshot = true
  enable_http_endpoint = true
  
  engine_mode = "provisioned" # Changed to provisioned for serverlessv2_scaling_configuration
  
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1.0
  }
  
  tags = {
    Name        = "cloudable-aurora-cluster"
    Environment = "dev"
    Project     = "Cloudable.AI"
  }
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier           = "aurora-dev-instance-1-v3"
  cluster_identifier   = aws_rds_cluster.aurora_cluster.id
  instance_class       = "db.serverless" # Using serverless for Data API support
  engine               = aws_rds_cluster.aurora_cluster.engine
  engine_version       = aws_rds_cluster.aurora_cluster.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora_subnet_group.name
  
  tags = {
    Name        = "cloudable-aurora-instance"
    Environment = "dev"
    Project     = "Cloudable.AI"
  }
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id
  
  tags = {
    Name = "Aurora DB subnet group"
  }
}

resource "aws_secretsmanager_secret" "aurora_secret" {
  name = "aurora-dev-admin-secret"
  description = "Secret for Aurora PostgreSQL cluster"
  
  tags = {
    Name        = "aurora-secret"
    Environment = "dev"
    Project     = "Cloudable.AI"
  }
}

resource "aws_secretsmanager_secret_version" "aurora_secret_version" {
  secret_id = aws_secretsmanager_secret.aurora_secret.id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora_cluster.master_username
    password = aws_rds_cluster.aurora_cluster.master_password
    engine   = "postgres"
    host     = aws_rds_cluster.aurora_cluster.endpoint
    port     = aws_rds_cluster.aurora_cluster.port
    dbname   = aws_rds_cluster.aurora_cluster.database_name
  })
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Allow database traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-security-group"
  }
}
