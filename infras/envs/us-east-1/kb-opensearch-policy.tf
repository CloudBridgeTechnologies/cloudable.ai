# Add OpenSearch policy attachment to KB manager role
resource "aws_iam_role_policy_attachment" "kb_manager_opensearch_attachment" {
  role       = aws_iam_role.kb_manager.name
  policy_arn = aws_iam_policy.kb_manager_opensearch.arn
}
