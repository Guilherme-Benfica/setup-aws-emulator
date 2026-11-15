# Demo pipeline, organized by the AWS Well-Architected pillars:
#   Kinesis stream -> Firehose -> S3            raw orders          (firehose.tf)
#   Kinesis stream -> Lambda orders-summary -> S3   one summary per batch (lambda.tf)
#   API Gateway GET /summaries -> Lambda orders-api, with an API key     (api.tf)
#   Storage, encryption and access rules                                 (storage.tf)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name = var.project

  # Operational excellence: every resource carries the same tags (provider default_tags).
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # S3 bucket names are global: the account ID keeps this one unique on a real account too.
  bucket_name = "${local.name}-events-${data.aws_caller_identity.current.account_id}"
}
