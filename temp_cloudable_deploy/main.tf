provider "aws" {
  region = "us-east-1"
}

# Use local backend
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# VPC module
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"
  
  name = "cloudable-vpc-dev"
  cidr = "10.0.0.0/16"
  
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
  
  tags = {
    Environment = "dev"
    Project     = "cloudable"
  }
}

# RDS PostgreSQL cluster
resource "aws_rds_cluster" "postgres" {
  cluster_identifier      = "aurora-dev"
  engine                  = "aurora-postgresql"
  engine_version          = "15.3"
  availability_zones      = ["us-east-1a", "us-east-1b", "us-east-1c"]
  database_name           = "cloudable"
  master_username         = "dbadmin"
  master_password         = "ComplexPassword123!"  # Would use Secrets Manager in production
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  storage_encrypted       = true
  
  lifecycle {
    ignore_changes = [availability_zones]
  }
}

resource "aws_rds_cluster_instance" "postgres" {
  identifier           = "aurora-dev-instance-1"
  cluster_identifier   = aws_rds_cluster.postgres.id
  instance_class       = "db.t4g.medium"
  engine               = aws_rds_cluster.postgres.engine
  engine_version       = aws_rds_cluster.postgres.engine_version
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "aurora-dev-subnets"
  subnet_ids = module.vpc.private_subnets
  
  tags = {
    Name = "Aurora Subnet Group"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id      = module.vpc.vpc_id
  name        = "aurora-dev-sg"
  description = "Aurora access"
  
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
  
  tags = {
    Name = "Aurora Security Group"
  }
}

# S3 buckets for knowledge base
resource "aws_s3_bucket" "kb_bucket_acme" {
  bucket = "cloudable-kb-dev-us-east-1-acme-${formatdate("YYYYMMDDHHmmss", timestamp())}"
  force_destroy = true
  
  tags = {
    Environment = "dev"
    Tenant      = "acme"
  }
}

resource "aws_s3_bucket" "kb_bucket_globex" {
  bucket = "cloudable-kb-dev-us-east-1-globex-${formatdate("YYYYMMDDHHmmss", timestamp())}"
  force_destroy = true
  
  tags = {
    Environment = "dev"
    Tenant      = "globex"
  }
}

# Create a secret for database credentials
resource "aws_secretsmanager_secret" "db_secret" {
  name = "aurora-dev-admin-secret"
  
  tags = {
    Environment = "dev"
  }
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = aws_rds_cluster.postgres.master_username
    password = aws_rds_cluster.postgres.master_password
    host     = aws_rds_cluster.postgres.endpoint
    port     = 5432
    dbname   = "cloudable"
  })
}

# Outputs
output "rds_cluster_arn" {
  value = aws_rds_cluster.postgres.arn
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.db_secret.arn
}

output "kb_bucket_acme" {
  value = aws_s3_bucket.kb_bucket_acme.bucket
}

output "kb_bucket_globex" {
  value = aws_s3_bucket.kb_bucket_globex.bucket
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}
