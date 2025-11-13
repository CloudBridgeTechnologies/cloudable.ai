terraform {
  backend "s3" {
    bucket  = "cloudable-tfstate-dev-us-east-1"
    key     = "envs/us-east-1/terraform.tfstate"
    region  = "us-east-1"
    profile = "cloudable-ai"
  }
}