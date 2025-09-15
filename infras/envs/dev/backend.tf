terraform {
  backend "s3" {
    bucket         = "cloudable-tfstate-dev-951296734820"
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "cloudable-dev-tf-locks"
    encrypt        = true
  }
}

