terraform {
  backend "local" {
    # Using local backend initially for GitHub Actions workflow testing
    # To switch back to S3 backend:
    # 1. Uncomment the S3 backend configuration
    # 2. Comment out the local backend
    # 3. Run `terraform init -reconfigure`
    path = "terraform.tfstate"
  }
  
  # backend "s3" {
  #   bucket         = "cloudable-tfstate-dev-951296734820"
  #   key            = "envs/us-east-1/terraform.tfstate"
  #   region         = "us-east-1"  # Changed to match other resources
  #   dynamodb_table = "cloudable-dev-tf-locks"
  #   encrypt        = true
  # }
}

