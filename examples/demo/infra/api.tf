# REST API: every path goes to orders-api (proxy integration), stage "dev".
# In AWS Emulator the stage answers at https://127.0.0.1:9297/dev/<path>.

resource "aws_api_gateway_rest_api" "orders" {
  name = "${local.name}-orders"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "{proxy+}"
}

# Security: the API is not open; callers send an API key (header x-api-key).
resource "aws_api_gateway_method" "proxy" {
  rest_api_id      = aws_api_gateway_rest_api.orders.id
  resource_id      = aws_api_gateway_resource.proxy.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.this["api"].invoke_arn
}

resource "aws_lambda_permission" "api" {
  statement_id  = "apigateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["api"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orders.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  # Redeploy whenever the routes change.
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_method.proxy.api_key_required,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_integration.proxy.uri,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  deployment_id = aws_api_gateway_deployment.orders.id
  stage_name    = "dev"
}

# Reliability and cost: each key is throttled and has a daily quota.
# AWS generates the key when no value is given; AWS Emulator requires one (20+ characters),
# so Terraform generates it. It stays in the state: keep the state in an encrypted backend.
resource "random_password" "api_key" {
  length  = 40
  special = false
}

resource "aws_api_gateway_api_key" "client" {
  name  = "${local.name}-client"
  value = random_password.api_key.result
}

resource "aws_api_gateway_usage_plan" "default" {
  name = "${local.name}-default"

  api_stages {
    api_id = aws_api_gateway_rest_api.orders.id
    stage  = aws_api_gateway_stage.dev.stage_name
  }

  throttle_settings {
    rate_limit  = var.api_rate_limit
    burst_limit = var.api_rate_limit * 2
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }
}

resource "aws_api_gateway_usage_plan_key" "client" {
  key_id        = aws_api_gateway_api_key.client.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.default.id
}
