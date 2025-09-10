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

variable "image_uri" {
  type = string # Makefile の print-image-uri で取得・設定
}

# ECR（任意：Terraform で管理する場合）
variable "ecr_repository_name" {
  type    = string
  default = "lambda-sample"
}

# Slack (Amazon Q Developer in chat applications)
variable "slack_workspace_id" {
  type = string # 例: "T0ABCDEF"
}

variable "slack_channel_id" {
  type = string # 例: "C0GHJKLMN"
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
