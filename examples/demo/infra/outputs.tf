# The tests read these names instead of repeating them in code.
output "bucket_name" {
  value = aws_s3_bucket.events.id
}

output "stream_name" {
  value = aws_kinesis_stream.orders.name
}

output "dlq_url" {
  value = aws_sqs_queue.summary_dlq.url
}

output "api_path" {
  description = "Stage path to append to the endpoint (AWS_ENDPOINT_URL on AWS Emulator)."
  value       = "/${aws_api_gateway_stage.dev.stage_name}"
}

output "api_key" {
  value     = aws_api_gateway_api_key.client.value
  sensitive = true
}
