# Slack 通知用 SNS
resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name
}

# Slack チャネル設定（Amazon Q Developer in chat applications）
resource "aws_chatbot_slack_channel_configuration" "slack" {
  configuration_name = "${var.project}-slack"
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  iam_role_arn       = aws_iam_role.chatbot.arn
  sns_topic_arns     = [aws_sns_topic.alerts.arn]
  logging_level      = "INFO"
}

