# Firehose copies every raw order from the stream to S3 (orders/), and failures to errors/.

resource "aws_iam_role" "firehose" {
  name = "${local.name}-firehose"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "firehose.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# Security: least privilege, every statement scoped to the resources it needs.
resource "aws_iam_role_policy" "firehose" {
  name = "read-stream-write-bucket-logs"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"], Resource = aws_kinesis_stream.orders.arn },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = "*", Condition = { StringEquals = { "kms:ViaService" = "kinesis.${data.aws_region.current.region}.amazonaws.com" } } },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"], Resource = [aws_s3_bucket.events.arn, "${aws_s3_bucket.events.arn}/*"] },
      { Effect = "Allow", Action = ["logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.firehose.arn}:*" },
    ]
  })
}

# Operational excellence: delivery errors are logged, with a retention period.
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.name}-orders-to-s3"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "orders" {
  name        = "${local.name}-orders-to-s3"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.orders.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.events.arn
    prefix              = "orders/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"
    buffering_size      = 1
    buffering_interval  = var.firehose_buffer_seconds

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }

  depends_on = [aws_iam_role_policy.firehose]
}
