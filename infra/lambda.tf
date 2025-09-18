data "aws_ecr_repository" "repo" {
  name = var.ecr_repository_name
}

data "aws_ecr_image" "img" {
  repository_name = data.aws_ecr_repository.repo.name
  image_tag       = var.image_tag
}

locals {
  image_uri_resolved = "${data.aws_ecr_repository.repo.repository_url}@${data.aws_ecr_image.img.image_digest}"
}

# コンテナイメージの Lambda（ダイジェスト固定）
resource "aws_lambda_function" "this" {
  function_name = var.lambda_function_name
  package_type  = "Image"
  image_uri     = local.image_uri_resolved

  role          = aws_iam_role.lambda.arn
  architectures = [var.architecture]
  timeout       = 10
  memory_size   = 1024

  environment {
    variables = {
      FORCE_ERROR   = "0"
      FORCE_TIMEOUT = "0"
      FORCE_MEMORY_LEAK = "0"
    }
  }
}

# 非同期失敗を EventBridge 既定バスへ（OnFailure -> EventBridge）
// 非同期の EventBridge 宛先（OnFailure）は不要のため削除済み
