# OpenSearch Serverless Collection for Knowledge Base
resource "aws_opensearchserverless_collection" "kb" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}
  
  name       = "kb-${var.env}-${each.value.name}"
  type       = "VECTORSEARCH"
  
  tags = merge(local.tags, {
    Name      = "kb-${var.env}-${each.value.name}"
    Tenant    = each.value.name
    Component = "KnowledgeBase"
  })
}

# OpenSearch Security Policy
resource "aws_opensearchserverless_security_policy" "kb" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}
  
  name = "policy-${var.env}-${each.value.name}"
  type = "encryption"
  
  policy = jsonencode({
    Rules = [
      {
        Resource     = ["collection/${aws_opensearchserverless_collection.kb[each.key].id}"],
        ResourceType = "collection"
      }
    ],
    AWSOwnedKey = true
  })
}

# OpenSearch Access Policy
resource "aws_opensearchserverless_access_policy" "kb" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}
  
  name  = "access-${var.env}-${each.value.name}"
  type  = "data"
  
  policy = jsonencode({
    Rules = [
      {
        Resource = ["index/${aws_opensearchserverless_collection.kb[each.key].id}/*"],
        Permission = [
          "aoss:CreateIndex",
          "aoss:DeleteIndex",
          "aoss:UpdateIndex",
          "aoss:DescribeIndex",
          "aoss:ReadDocument", 
          "aoss:WriteDocument"
        ],
        ResourceType = "index"
      },
      {
        Resource = ["collection/${aws_opensearchserverless_collection.kb[each.key].id}"],
        Permission = [
          "aoss:ReadDocument", 
          "aoss:WriteDocument"
        ],
        ResourceType = "collection"
      }
    ],
    Principal = [
      aws_iam_role.kb_manager.arn,
      aws_iam_role.agent.arn,
      aws_iam_role.kb[each.key].arn
    ]
  })
}

# Note: IAM Roles are defined in iam-bedrock.tf
