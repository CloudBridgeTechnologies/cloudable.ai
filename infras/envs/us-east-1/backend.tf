terraform {
  # Local backend configuration - this will store state locally
  # Uncomment the S3 backend configuration below when ready to use remote state
  
  /*
  backend "s3" {
    bucket         = "cloudable-tfstate-dev"  # Replace with your bucket name
    key            = "envs/us-east-1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudable-tf-locks-dev"
    encrypt        = true
  }
  */
}