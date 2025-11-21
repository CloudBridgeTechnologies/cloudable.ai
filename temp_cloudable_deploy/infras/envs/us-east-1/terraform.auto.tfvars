env = "dev"
domain_name = "cloudable.ai"
aurora_engine_version = "15.12"

# VPC Configuration - We'll use the existing VPC module but ensure these values are set
vpc_cidr = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# Deployment flags
force_destroy = true
prevent_destroy = false
