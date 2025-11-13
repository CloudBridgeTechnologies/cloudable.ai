# OpenSearch Serverless Network Policy to allow Bedrock access
resource "aws_opensearchserverless_security_policy" "bedrock_network" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}
  
  name        = "network-${var.env}-${each.value.name}"
  type        = "network"
  description = "Network policy to allow Bedrock to access OpenSearch Serverless collection"
  
  policy = jsonencode([
    {
      Description = "Bedrock access to OpenSearch collection",
      Rules = [
        {
          ResourceType = "collection",
          Resource     = ["collection/kb-${var.env}-${each.value.name}"]
        }
      ],
      AllowFromPublic = false,
      SourceServices  = ["bedrock.amazonaws.com"]
    }
  ])
}
