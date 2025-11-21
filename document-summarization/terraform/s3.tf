resource "aws_s3_bucket" "documents" {
  bucket = local.bucket_name
  
  tags = {
    Name = "Document Summarization Bucket"
  }
}

resource "aws_s3_bucket_notification" "document_upload" {
  bucket = aws_s3_bucket.documents.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.summarizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

output "bucket_name" {
  value = aws_s3_bucket.documents.id
}
