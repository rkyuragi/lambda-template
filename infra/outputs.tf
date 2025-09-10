output "sns_topic_arn"     { value = aws_sns_topic.alerts.arn }
output "slack_config_name" { value = aws_chatbot_slack_channel_configuration.slack.configuration_name }
output "lambda_name"       { value = aws_lambda_function.this.function_name }
output "alarm_arn"         { value = aws_cloudwatch_metric_alarm.lambda_errors.arn }

