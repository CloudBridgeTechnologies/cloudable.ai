# OpenSearch Serverless Collection for Knowledge Base
resource "aws_opensearchserverless_collection" "kb" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}

  name = "kb-${var.env}-${each.value.name}"
  type = "VECTORSEARCH"

  tags = merge(local.tags, {
    Name      = "kb-${var.env}-${each.value.name}"
    Tenant    = each.value.name
    Component = "KnowledgeBase"
  })

  # Ensure security and access policies are created before the collection
  depends_on = [
    aws_opensearchserverless_security_policy.kb,
    aws_opensearchserverless_access_policy.kb,
    aws_opensearchserverless_security_policy.bedrock_network
  ]
}

# OpenSearch Security Policy
resource "aws_opensearchserverless_security_policy" "kb" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}

  name = "policy-${var.env}-${each.value.name}"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        # Target by collection name so this can be created before the collection
        Resource     = ["collection/kb-${var.env}-${each.value.name}"],
        ResourceType = "collection"
      }
    ],
    AWSOwnedKey = true
  })
}

# OpenSearch Access Policy
resource "aws_opensearchserverless_access_policy" "kb" {
  for_each = var.enable_bedrock_agents ? var.tenants : {}

  name = "access-${var.env}-${each.value.name}"
  type = "data"

  policy = jsonencode([
    {
      Description = "Access policy for ${each.value.name} tenant knowledge base",
      Rules = [
        {
          # Index permissions
          Resource = ["index/kb-${var.env}-${each.value.name}/*"],
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
          # Collection permissions
          Resource = ["collection/kb-${var.env}-${each.value.name}"],
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems", 
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ],
          ResourceType = "collection"
        }
      ],
      Principal = [
        aws_iam_role.kb_manager.arn,
        aws_iam_role.agent.arn,
        aws_iam_role.kb[each.key].arn
      ]
    }
  ])
}

# Note: IAM Roles are defined in iam-bedrock.tf

