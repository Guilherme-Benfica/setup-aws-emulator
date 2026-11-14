terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.23.0 and later read S3 bucket tags through S3 Control, whose requests
      # go to <account-id>.127.0.0.1 and can't reach AWS Emulator.
      version = ">= 5.0, < 6.23.0"
    }
  }
}

# No endpoints or credentials here: the provider reads the AWS_* variables
# that setup-aws-emulator exports, the same way the AWS CLI and SDKs do.
provider "aws" {}

variable "name" {
  description = "Prefix for the resources created in the emulator."
  type        = string
  default     = "tf-emulator-demo"
}

resource "aws_s3_bucket" "notes" {
  bucket = "${var.name}-notes"
}

resource "aws_s3_object" "hello" {
  bucket  = aws_s3_bucket.notes.id
  key     = "hello.txt"
  content = "hello from terraform on AWS Emulator"
}

resource "aws_dynamodb_table" "notes" {
  name         = "${var.name}-notes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.notes.id
}

output "table_name" {
  value = aws_dynamodb_table.notes.name
}
