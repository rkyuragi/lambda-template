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

# Slack (Amazon Q Developer in chat applications)
variable "slack_channel_id" {
  type = string # 例: "C0GHJKLMN"
}

variable "slack_team_id" {
  type = string # 例: "T0ABCDEF"（Workspace/Team ID）
}

variable "manage_chatbot" {
  type    = bool
  default = true # 既存チャネル設定がある場合は false にして手動で SNS を追加 or import
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

