# Slack 通知用 SNS
resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name
}

# EventBridge から SNS へ Publish できるようにトピックポリシーを付与
resource "aws_sns_topic_policy" "alerts_policy" {
  arn    = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      // EventBridge 経由の配信は廃止のため許可を除去
      {
        Sid      = "AllowCloudWatchToPublish",
        Effect   = "Allow",
        Principal = { Service = "cloudwatch.amazonaws.com" },
        Action   = ["SNS:Publish"],
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid       = "AllowChatbotToSubscribe",
        Effect    = "Allow",
        Principal = { Service = "chatbot.amazonaws.com" },
        Action    = ["SNS:Subscribe"],
        Resource  = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# Slack チャネル設定（Amazon Q Developer in chat applications）
resource "aws_chatbot_slack_channel_configuration" "slack" {
  count               = var.manage_chatbot ? 1 : 0
  configuration_name = "${var.project}-slack"
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id
  iam_role_arn       = aws_iam_role.chatbot.arn
  sns_topic_arns     = [aws_sns_topic.alerts.arn]
  logging_level      = "INFO"
}
