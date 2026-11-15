terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.23.0 and later read S3 bucket tags through S3 Control, which AWS Emulator does not serve.
      version = ">= 5.0, < 6.23.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

# Endpoint, Region and credentials come from the AWS_* variables (awsemu env, or the action in CI),
# so the same code runs against AWS Emulator and against a real account.
provider "aws" {
  default_tags {
    tags = local.tags
  }
}
