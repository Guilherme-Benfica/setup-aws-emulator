# Demo pipeline: Kinesis stream -> Firehose -> S3, created in AWS Emulator.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.23.0 and later read S3 bucket tags through S3 Control, which can't reach the emulator.
      version = ">= 5.0, < 6.23.0"
    }
  }
}

# Endpoint and credentials come from the AWS_* variables (awsemu env or the action).
provider "aws" {}

resource "aws_s3_bucket" "events" {
  bucket = "demo-events"
}

resource "aws_kinesis_stream" "orders" {
  name        = "demo-orders"
  shard_count = 1
  # With the default 24 hours, the provider calls IncreaseStreamRetentionPeriod(24), which
  # AWS Emulator refuses (AWS accepts it). Any longer period avoids that call failing.
  retention_period = 48
}

resource "aws_iam_role" "firehose" {
  name = "demo-firehose"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "firehose.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "firehose" {
  name = "read-stream-write-bucket"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"], Resource = aws_kinesis_stream.orders.arn },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"], Resource = [aws_s3_bucket.events.arn, "${aws_s3_bucket.events.arn}/*"] },
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "orders" {
  name        = "demo-orders-to-s3"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.orders.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = aws_s3_bucket.events.arn
    prefix             = "orders/"
    buffering_size     = 1
    buffering_interval = 0
  }
}

output "stream_name" {
  value = aws_kinesis_stream.orders.name
}

output "bucket_name" {
  value = aws_s3_bucket.events.id
}
