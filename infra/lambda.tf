# コンテナイメージの Lambda
resource "aws_lambda_function" "this" {
  function_name = var.lambda_function_name
  package_type  = "Image"
  image_uri     = var.image_uri

  role          = aws_iam_role.lambda.arn
  architectures = [var.architecture]
  timeout       = 10
  memory_size   = 1024

  environment {
    variables = {
      FORCE_ERROR   = "0"
      FORCE_TIMEOUT = "0"
    }
  }
}

# 非同期失敗を EventBridge 既定バスへ（OnFailure -> EventBridge）
resource "aws_lambda_function_event_invoke_config" "async" {
  function_name = aws_lambda_function.this.function_name
  destination_config {
    on_failure { destination = local.default_bus_arn }
  }
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600
}

