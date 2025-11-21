#!/bin/bash

set -e

echo "Building Lambda packages..."
chmod +x build_lambda_packages.sh
./build_lambda_packages.sh

echo "Deploying infrastructure with Terraform..."
cd terraform
terraform init
terraform plan
terraform apply -auto-approve

echo "Deployment complete!"
echo "API Endpoint: $(terraform output -raw api_endpoint)"
echo "S3 Bucket: $(terraform output -raw bucket_name)"
