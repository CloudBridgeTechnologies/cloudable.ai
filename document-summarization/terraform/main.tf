terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.20"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "eu-west-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  bucket_name = "documents-bucket-summarization-${random_id.bucket_suffix.hex}"
}
