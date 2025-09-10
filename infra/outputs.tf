output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }

output "slack_config_name" {
  value = var.manage_chatbot ? aws_chatbot_slack_channel_configuration.slack[0].configuration_name : null
}

output "lambda_name" { value = aws_lambda_function.this.function_name }
output "alarm_arn"   { value = aws_cloudwatch_metric_alarm.lambda_errors.arn }
