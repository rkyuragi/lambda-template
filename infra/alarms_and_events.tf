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
}

# アラーム状態遷移（ALARM）のイベントをキャッチ
resource "aws_cloudwatch_event_rule" "cw_alarm_state_alarm" {
  name         = "${var.project}-cw-alarm-state"
  description  = "CloudWatch Alarm State Change (ALARM only)"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"],
    detail-type = ["CloudWatch Alarm State Change"],
    resources   = [aws_cloudwatch_metric_alarm.lambda_errors.arn],
    detail      = { state = { value = ["ALARM"] } }
  })
}

# Slack へ整形して通知（SNS ターゲット＋Input Transformer）
resource "aws_cloudwatch_event_target" "cw_alarm_to_sns" {
  rule = aws_cloudwatch_event_rule.cw_alarm_state_alarm.name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      alarmName = "$.detail.alarmName"
      newState  = "$.detail.state.value"
      reason    = "$.detail.state.reason"
      time      = "$.time"
      region    = "$.region"
      account   = "$.account"
    }
    input_template = "\"*:rotating_light: Lambda失敗アラーム :rotating_light:*\\n*アラーム*: <alarmName>\\n*状態*: <newState>\\n*理由*: <reason>\\n*時刻*: <time>\\n*リージョン*: <region> / *アカウント*: <account>\\n<https://console.aws.amazon.com/cloudwatch/home?region=<region>#alarmsV2:alarm/<alarmName>|CloudWatch アラームを開く>\""
  }
}

##############################################################
# 2) 非同期失敗イベント（詳細ペイロード） -> Slack 整形通知
##############################################################
resource "aws_cloudwatch_event_rule" "lambda_async_failure" {
  name        = "${var.project}-lambda-async-failure"
  description = "Lambda Destinations OnFailure（非同期失敗）"
  event_pattern = jsonencode({
    source      = ["lambda"],
    detail-type = ["Lambda Function Invocation Result - Failure"],
    detail      = {
      requestContext = {
        functionArn = [
          { prefix = "arn:aws:lambda:${var.region}:${local.account_id}:function:${var.lambda_function_name}" }
        ]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_async_failure_to_sns" {
  rule = aws_cloudwatch_event_rule.lambda_async_failure.name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      fnArn        = "$.detail.requestContext.functionArn"
      reqId        = "$.detail.requestContext.requestId"
      cond         = "$.detail.requestContext.condition"
      retries      = "$.detail.requestContext.approximateInvokeCount"
      status       = "$.detail.responseContext.statusCode"
      errorType    = "$.detail.responseContext.functionError"
      errorMessage = "$.detail.responsePayload.errorMessage"
      ts           = "$.time"
      region       = "$.region"
    }
    input_template = "\"*:x: Lambda非同期失敗*\\n*関数*: <fnArn>\\n*RequestId*: <reqId>\\n*条件*: <cond> / *試行回数*: <retries>\\n*エラー*: <errorType> (<status>)\\n*メッセージ*: <errorMessage>\\n*時刻*: <ts> (<region>)\""
  }
}

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
    expression  = "100 * (errors / MAX([invocations,1]))"
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

