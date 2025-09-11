# Lambda 実行ロール
resource "aws_iam_role" "lambda" {
  name               = "${var.project}-lambda-exec"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda の非同期失敗を EventBridge 既定バスへ PutEvents するための権限
// EventBridge への PutEvents 権限は不要のため削除済み

# Slack 連携（Amazon Q Developer / 旧 AWS Chatbot）のチャネルロール
// Chatbot 用のロールは不要のため削除済み
