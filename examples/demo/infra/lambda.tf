# Two functions from the same package: orders-summary (Kinesis trigger) and orders-api (API Gateway).

data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["__pycache__"]
}

locals {
  functions = {
    summary = { name = "${local.name}-orders-summary", handler = "handler.handler" }
    api     = { name = "${local.name}-orders-api", handler = "api.handler" }
  }
}

# Operational excellence: one log group per function, created by Terraform with a retention period
# (Lambda would otherwise create it with logs kept forever).
resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.functions
  name              = "/aws/lambda/${each.value.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# Security: least privilege. Like AWS, AWS Emulator refuses the event source mapping unless the
# role can read the stream (it does not evaluate the rest of the policy, so test that on AWS).
resource "aws_iam_role_policy" "lambda" {
  name = "orders-functions"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListShards", "kinesis:ListStreams"], Resource = aws_kinesis_stream.orders.arn },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = "*", Condition = { StringEquals = { "kms:ViaService" = "kinesis.${data.aws_region.current.region}.amazonaws.com" } } },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.events.arn}/summaries/*" },
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.events.arn },
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.summary_dlq.arn },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = [for g in aws_cloudwatch_log_group.lambda : "${g.arn}:*"] },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" },
    ]
  })
}

resource "aws_lambda_function" "this" {
  for_each         = local.functions
  function_name    = each.value.name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = each.value.handler
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = { DEMO_BUCKET = aws_s3_bucket.events.id }
  }

  # Operational excellence: structured JSON logs and X-Ray traces.
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda[each.key].name
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy.lambda]
}

# Reliability: report only the failed records, split a failing batch, retry a few times,
# and send what still fails to the dead-letter queue.
# AWS Emulator delivers one record per invocation: batching, windows and event filters
# are not applied there, so test them on AWS.
resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn                   = aws_kinesis_stream.orders.arn
  function_name                      = aws_lambda_function.this["summary"].arn
  starting_position                  = "TRIM_HORIZON"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
  bisect_batch_on_function_error     = true
  maximum_retry_attempts             = 3
  maximum_record_age_in_seconds      = 3600

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.summary_dlq.arn
    }
  }
}
