# Demo pipeline in AWS Emulator:
#   Kinesis stream -> Firehose -> S3 (raw orders)
#   Kinesis stream -> Lambda orders-summary -> S3 (one summary per invocation)
#   API Gateway GET /summaries -> Lambda orders-api (lists the summaries)
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.23.0 and later read S3 bucket tags through S3 Control, which can't reach the emulator.
      version = ">= 5.0, < 6.23.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
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

# Lambda functions. The role must be able to read the stream: like AWS, AWS Emulator refuses the
# event source mapping otherwise. (It does not evaluate the rest of the policy.)
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["__pycache__"]
}

resource "aws_iam_role" "lambda" {
  name = "demo-lambda"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "read-stream-use-bucket-write-logs"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListShards", "kinesis:ListStreams"], Resource = aws_kinesis_stream.orders.arn },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"], Resource = [aws_s3_bucket.events.arn, "${aws_s3_bucket.events.arn}/*"] },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
    ]
  })
}

resource "aws_lambda_function" "summary" {
  function_name    = "orders-summary"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  environment {
    variables = { DEMO_BUCKET = aws_s3_bucket.events.id }
  }
  depends_on = [aws_iam_role_policy.lambda]
}

resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn  = aws_kinesis_stream.orders.arn
  function_name     = aws_lambda_function.summary.arn
  starting_position = "TRIM_HORIZON"
  batch_size        = 1
}

resource "aws_lambda_function" "api" {
  function_name    = "orders-api"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "api.handler"
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  environment {
    variables = { DEMO_BUCKET = aws_s3_bucket.events.id }
  }
  depends_on = [aws_iam_role_policy.lambda]
}

# API Gateway REST API: every path goes to orders-api (proxy integration), stage "dev".
# In AWS Emulator the stage answers at https://127.0.0.1:9297/dev/<path>.
resource "aws_api_gateway_rest_api" "orders" {
  name = "demo-orders"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "api" {
  statement_id  = "apigateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orders.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  depends_on  = [aws_api_gateway_integration.proxy]
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  deployment_id = aws_api_gateway_deployment.orders.id
  stage_name    = "dev"
}

output "stream_name" {
  value = aws_kinesis_stream.orders.name
}

output "bucket_name" {
  value = aws_s3_bucket.events.id
}
