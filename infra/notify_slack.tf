###############################################################################
# SNS -> Lambda -> Slack Webhook 通知
###############################################################################

resource "aws_iam_role" "notify_slack" {
  name               = "${var.project}-notify-slack-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "notify_slack_basic" {
  role       = aws_iam_role.notify_slack.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "notify_slack_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/notify_slack"
  output_path = "${path.module}/.terraform/build/notify_slack.zip"
}

resource "aws_lambda_function" "notify_slack" {
  function_name = "${var.project}-notify-slack"
  role          = aws_iam_role.notify_slack.arn
  filename      = data.archive_file.notify_slack_zip.output_path
  source_code_hash = data.archive_file.notify_slack_zip.output_base64sha256
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
}

resource "aws_lambda_permission" "sns_invoke_notify" {
  statement_id  = "AllowSnsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify_slack.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "alerts_to_lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notify_slack.arn
}

