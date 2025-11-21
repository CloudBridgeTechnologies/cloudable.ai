# Additional permissions for summary_retriever Lambda function to access timestamp-based bucket names
resource "aws_iam_role_policy" "summary_retriever_timestamp_buckets" {
  name   = "summary-retriever-timestamp-buckets-${var.env}"
  role   = aws_iam_role.summary_retriever.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject", 
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Resource = [
          "arn:aws:s3:::cloudable-summaries-${var.env}-${var.region}-*",
          "arn:aws:s3:::cloudable-summaries-${var.env}-${var.region}-*/*"
        ]
      }
    ]
  })
}
