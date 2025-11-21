# OpenSearch Serverless access policy DISABLED - Using RDS instead
# resource "aws_opensearchserverless_access_policy" "bedrock_kb_access" {
#   for_each = var.enable_bedrock_agents ? var.tenants : {}
# 
#   name        = "bedrock-kb-access-${var.env}-${each.value.name}"
#   type        = "data"
#   description = "Access policy specifically for Bedrock Knowledge Base"
# 
#   policy = jsonencode(
#     [
#       {
#         "Description": "Bedrock KB tenant ${each.key} access",
#         "Rules": [
#           {
#             "ResourceType": "collection",
#             "Resource": [
#               "collection/kb-${var.env}-${each.value.name}"
#             ],
#             "Permission": [
#               "aoss:*"
#             ]
#           },
#           {
#             "ResourceType": "index",
#             "Resource": [
#               "index/kb-${var.env}-${each.value.name}/*"
#             ],
#             "Permission": [
#               "aoss:ReadDocument",
#               "aoss:WriteDocument",
#               "aoss:CreateIndex",
#               "aoss:DescribeIndex",
#               "aoss:UpdateIndex"
#             ]
#           }
#         ],
#         "Principal": [
#           aws_iam_role.kb[each.key].arn
#         ]
#       }
#     ]
#   )
# }