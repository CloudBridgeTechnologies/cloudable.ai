terraform {
  backend "s3" {
    bucket         = "cloudable-tfstate-dev-975049969923"
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "cloudable-dev-tf-locks"
    encrypt        = true
  }
}

