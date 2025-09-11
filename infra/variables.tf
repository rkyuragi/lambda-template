variable "project" {
  type    = string
  default = "lambda-alerts"
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

# Lambda
variable "lambda_function_name" {
  type    = string
  default = "lambda-sample-image"
}

variable "architecture" {
  type    = string
  default = "arm64" # x86_64 も可
}

variable "image_tag" {
  type    = string
  default = "v1"
}

# ECR（任意：Terraform で管理する場合）
variable "ecr_repository_name" {
  type    = string
  default = "lambda-sample"
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
  description = "Slack Incoming Webhook URL (do not commit real values)"
}

# SNS
variable "sns_topic_name" {
  type    = string
  default = "lambda-alerts"
}

# アラーム閾値
variable "alarm_period" {
  type    = number
  default = 60
}

variable "alarm_evaluation_periods" {
  type    = number
  default = 1
}

variable "error_rate_threshold_percent" {
  type    = number
  default = 5
}
