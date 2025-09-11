# SNS トピック（Slack Webhook 経由通知の起点）
resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name
}

# CloudWatch から SNS へ Publish できるようにトピックポリシーを付与
resource "aws_sns_topic_policy" "alerts_policy" {
  arn    = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowCloudWatchToPublish",
        Effect   = "Allow",
        Principal = { Service = "cloudwatch.amazonaws.com" },
        Action   = ["SNS:Publish"],
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}
