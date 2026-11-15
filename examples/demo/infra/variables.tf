variable "project" {
  description = "Prefix for every resource name."
  type        = string
  default     = "demo"
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps the Lambda and Firehose logs."
  type        = number
  default     = 14
}

variable "firehose_buffer_seconds" {
  description = "Firehose buffer interval. 0 delivers right away, which suits tests; use 60 to 900 in production."
  type        = number
  default     = 0
}

variable "api_rate_limit" {
  description = "Steady-state requests per second allowed per API key."
  type        = number
  default     = 10
}
