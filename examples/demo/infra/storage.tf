# Security: private, encrypted, versioned bucket that only accepts TLS.
resource "aws_s3_bucket" "events" {
  bucket = local.bucket_name
  # Outside production, terraform destroy may empty the bucket (versions included).
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_public_access_block" "events" {
  bucket                  = aws_s3_bucket.events.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "events" {
  bucket = aws_s3_bucket.events.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "events" {
  bucket = aws_s3_bucket.events.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.events.arn, "${aws_s3_bucket.events.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.events]
}

# Security: the stream is encrypted at rest with the AWS managed key.
resource "aws_kinesis_stream" "orders" {
  name             = "${local.name}-orders"
  shard_count      = 1
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"
  # With the default 24 hours the provider calls IncreaseStreamRetentionPeriod(24),
  # which AWS Emulator refuses (AWS accepts it). Any longer period avoids that call.
  retention_period = 48
}

# Reliability: records the summary Lambda gives up on land here instead of being lost.
resource "aws_sqs_queue" "summary_dlq" {
  name                      = "${local.name}-orders-summary-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
