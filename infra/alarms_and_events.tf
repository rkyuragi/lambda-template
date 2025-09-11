############################################
# 1) Lambda Errors アラーム（Timeout を含む）
############################################
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.lambda_function_name}-Errors"
  alarm_description   = "Lambda Errors >= 1（Timeout含む）"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = { FunctionName = var.lambda_function_name }

  # CloudWatch アラームから直接 SNS へ通知
  alarm_actions = [aws_sns_topic.alerts.arn]
}


// 非同期失敗（EventBridge 経由）通知は削除済み

##############################################################
# （任意）ErrorRate アラーム（Metric Math）
##############################################################
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${var.lambda_function_name}-ErrorRatePct"
  alarm_description   = "Lambda ErrorRate > ${var.error_rate_threshold_percent}%"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_threshold_percent
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "IF(invocations > 0, 100 * (errors / invocations), 0)"
    label       = "ErrorRate(%)"
    return_data = true
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = var.alarm_period
      stat        = "Sum"
      dimensions  = { FunctionName = var.lambda_function_name }
    }
  }
  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = var.alarm_period
      stat        = "Sum"
      dimensions  = { FunctionName = var.lambda_function_name }
    }
  }
}
