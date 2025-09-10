以下は、**Terraform 化**と**Slack メッセージ整形**まで落とし込んだ、エラー／タイムアウト検知の通知テンプレート一式です。
通知は **Amazon Q Developer in chat applications（旧 AWS Chatbot）** を用いて Slack に配信します（2025/02/19 改称。Terraform リソース名は従来どおり `aws_chatbot_slack_channel_configuration`）｡ ([AWS Documentation][1], [Terraform Registry][2])

> 失敗の検知は2系統です
> ① **CloudWatch アラーム**（`AWS/Lambda:Errors`）→ **EventBridge**（Input Transformer で整形）→ **SNS** → **Amazon Q Developer** → **Slack**。
> ② **非同期呼び出しの失敗詳細**（Destinations `OnFailure` → EventBridge）→ **SNS** → **Amazon Q Developer** → **Slack**。
> `Errors` は**タイムアウトを含む**ため、①だけでも「エラー＋タイムアウト」を確実に検知できます。②を併用すると、非同期失敗の **RequestId** やエラーメッセージなどを**詳細整形**して届けられます。 ([AWS Documentation][3])

---

## 1) リポジトリ構成（テンプレート）

```
.
├── app/
│   ├── lambda_function.py
│   └── requirements.txt
├── Dockerfile
├── Makefile
└── infra/
    ├── providers.tf
    ├── variables.tf
    ├── locals.tf
    ├── iam.tf
    ├── ecr.tf
    ├── lambda.tf
    ├── sns_chatbot.tf
    ├── alarms_and_events.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

---

## 2) Lambda（Python 3.12+, コンテナイメージ）

### `app/lambda_function.py`

```python
import json, logging, os, time
log = logging.getLogger()
log.setLevel(logging.INFO)

def handler(event, context):
    if os.getenv("FORCE_TIMEOUT") == "1":
        while True:
            time.sleep(1)  # タイムアウトを誘発（テスト用）
    if os.getenv("FORCE_ERROR") == "1":
        raise RuntimeError("FORCED_ERROR: 意図的にエラーを発生")

    log.info({"event": event, "request_id": context.aws_request_id})
    return {"statusCode": 200, "body": json.dumps({"ok": True})}
```

### `Dockerfile`

```dockerfile
# AWS 提供の Python 3.12 ベースイメージ（AL2023 / RIC 同梱）
FROM public.ecr.aws/lambda/python:3.12

# 依存インストール
COPY app/requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
RUN pip install -r ${LAMBDA_TASK_ROOT}/requirements.txt

# コード配置
COPY app/ ${LAMBDA_TASK_ROOT}/

# ハンドラ指定
CMD ["lambda_function.handler"]
```

> AWS 公式の **Python 3.12** コンテナベースで Lambda をデプロイできます（RIC 同梱）。 ([AWS Documentation][4], [gallery.ecr.aws][5], [Amazon Web Services, Inc.][6])

### `Makefile`（任意：ローカルでビルド＆プッシュ）

```makefile
REGION ?= ap-northeast-1
ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text)
REPO ?= lambda-sample
TAG ?= v1
IMAGE_URI := $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(REPO):$(TAG)

build:
\tdocker buildx build --platform linux/arm64 --provenance=false -t $(IMAGE_URI) .

push:
\taws ecr describe-repositories --repository-names $(REPO) --region $(REGION) >/dev/null 2>&1 || \
\t  aws ecr create-repository --repository-name $(REPO) --image-scanning-configuration scanOnPush=true --region $(REGION)
\taws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
\tdocker push $(IMAGE_URI)

print-image-uri:
\t@echo $(IMAGE_URI)
```

---

## 3) Terraform（Slack 通知＆整形込み）

> **前提**：Terraform v1.6+ / AWS Provider v6.5+。Slack ワークスペースの**初回認可**を Amazon Q Developer コンソールで実施し、`SlackWorkspaceId`/`SlackChannelId` を取得してください。 ([AWS Documentation][7])

### `infra/providers.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.5" }
  }
}
provider "aws" {
  region = var.region
}
data "aws_caller_identity" "current" {}
```

### `infra/variables.tf`

```hcl
variable "project" { type = string, default = "lambda-alerts" }
variable "region"  { type = string, default = "ap-northeast-1" }

# Lambda
variable "lambda_function_name" { type = string, default = "lambda-sample-image" }
variable "architecture"         { type = string, default = "arm64" } # x86_64 も可
variable "image_uri"            { type = string }  # Makefile の print-image-uri で取得・設定

# ECR（任意：Terraform で管理する場合）
variable "ecr_repository_name" { type = string, default = "lambda-sample" }

# Slack (Amazon Q Developer in chat applications)
variable "slack_workspace_id" { type = string }  # 例: "T0ABCDEF"
variable "slack_channel_id"   { type = string }  # 例: "C0GHJKLMN"

# SNS
variable "sns_topic_name" { type = string, default = "lambda-alerts" }

# アラーム閾値
variable "alarm_period"              { type = number, default = 60 }
variable "alarm_evaluation_periods"  { type = number, default = 1 }
variable "error_rate_threshold_percent" { type = number, default = 5 }
```

### `infra/locals.tf`

```hcl
locals {
  account_id      = data.aws_caller_identity.current.account_id
  default_bus_arn = "arn:aws:events:${var.region}:${local.account_id}:event-bus/default"
}
```

### `infra/ecr.tf`（任意）

```hcl
resource "aws_ecr_repository" "this" {
  name = var.ecr_repository_name
  image_scanning_configuration { scan_on_push = true }
}
```

### `infra/iam.tf`

```hcl
# Lambda 実行ロール
resource "aws_iam_role" "lambda" {
  name               = "${var.project}-lambda-exec"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="lambda.amazonaws.com" }, Action="sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Slack 連携（Amazon Q Developer in chat applications / 旧 AWS Chatbot）のチャネルロール
resource "aws_iam_role" "chatbot" {
  name               = "${var.project}-chatbot-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="chatbot.amazonaws.com" }, Action="sts:AssumeRole" }]
  })
}
# 通知用途の最小権限（CloudWatch 読み取り等）。必要に応じて見直し
resource "aws_iam_role_policy_attachment" "chatbot_cw_readonly" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
resource "aws_iam_role_policy_attachment" "chatbot_readonly" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

> Slack チャネル設定は **ユーザー定義 IAM ロール**を Assume します（信頼先= `chatbot.amazonaws.com`）。ワークスペース／チャンネル ID 取得やプロパティは公式仕様をご参照ください。 ([AWS Documentation][7])

### `infra/lambda.tf`

```hcl
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
  maximum_retry_attempts      = 2
  maximum_event_age_in_seconds = 21600
}
```

> Destinations の **OnFailure** を **EventBridge** に送ると、`source: "lambda"`, `detail-type: "Lambda Function Invocation Result - Failure"` のイベントが飛びます。 ([AWS Documentation][8])

### `infra/sns_chatbot.tf`

```hcl
# Slack 通知用 SNS
resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name
}

# Slack チャネル設定（Amazon Q Developer in chat applications）
resource "aws_chatbot_slack_channel_configuration" "slack" {
  configuration_name = "${var.project}-slack"
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  iam_role_arn       = aws_iam_role.chatbot.arn
  sns_topic_arns     = [aws_sns_topic.alerts.arn]
  logging_level      = "INFO"
}
```

> Amazon Q Developer は **SNS トピック**にひも付けて通知を配信します（Terraform リソースは従来名）。 ([AWS Documentation][9], [Terraform Registry][2])

### `infra/alarms_and_events.tf`

```hcl
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
    "source"      : ["aws.cloudwatch"],
    "detail-type" : ["CloudWatch Alarm State Change"],
    "resources"   : [aws_cloudwatch_metric_alarm.lambda_errors.arn],
    "detail"      : { "state": { "value": ["ALARM"] } }
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
    # Slack の整形（太字/絵文字/コンソールリンク）
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
    "source"      : ["lambda"],
    "detail-type" : ["Lambda Function Invocation Result - Failure"],
    "detail"      : {
      "requestContext": {
        "functionArn": [
          { "prefix": "arn:aws:lambda:${var.region}:${local.account_id}:function:${var.lambda_function_name}" }
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
      namespace  = "AWS/Lambda"
      metric_name= "Errors"
      period     = var.alarm_period
      stat       = "Sum"
      dimensions = { FunctionName = var.lambda_function_name }
    }
  }
  metric_query {
    id = "invocations"
    metric {
      namespace  = "AWS/Lambda"
      metric_name= "Invocations"
      period     = var.alarm_period
      stat       = "Sum"
      dimensions = { FunctionName = var.lambda_function_name }
    }
  }
}
```

* **アラーム→EventBridge**：CloudWatch のアラーム状態変化は EventBridge にイベントとして発行されます。 ([AWS Documentation][10])
* **Input Transformer**：イベントから必要項目を **JSONPath で抽出**し、**文字列テンプレート**で Slack 用に整形しています（複数行／リンク／絵文字対応）。 ([AWS Documentation][11])
* **`Errors` メトリクス**は**タイムアウト等のランタイムエラーも含む**ため、Timeout も検知可能です。 ([AWS Documentation][3])
* **非同期失敗イベント**の `detail` 構造・`detail-type` は公式仕様です。 ([AWS Documentation][8])

### `infra/outputs.tf`

```hcl
output "sns_topic_arn"     { value = aws_sns_topic.alerts.arn }
output "slack_config_name" { value = aws_chatbot_slack_channel_configuration.slack.configuration_name }
output "lambda_name"       { value = aws_lambda_function.this.function_name }
output "alarm_arn"         { value = aws_cloudwatch_metric_alarm.lambda_errors.arn }
```

### `infra/terraform.tfvars.example`

```hcl
region              = "ap-northeast-1"
lambda_function_name= "lambda-sample-image"
image_uri           = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/lambda-sample:v1"

slack_workspace_id  = "T0ABCDEF"
slack_channel_id    = "C0GHJKLMN"

sns_topic_name = "lambda-alerts"
```

---

## 4) 運用・デプロイ手順（例）

1. **コンテナイメージをビルド＆プッシュ**

   ```bash
   cd ./ && make build push REGION=ap-northeast-1 REPO=lambda-sample TAG=v1
   make print-image-uri
   ```

   得られた `IMAGE_URI` を `infra/terraform.tfvars` の `image_uri` に設定。

2. **Terraform 適用**

   ```bash
   cd infra
   terraform init
   terraform apply -auto-approve
   ```

3. **Slack 連携の事前準備**
   初回のみ、Amazon Q Developer in chat applications コンソールでワークスペースを認可し、`SlackWorkspaceId` と `SlackChannelId` を取得します。Terraform の値に設定すると、SNS トピックがチャネル構成に関連付けられ、通知が届きます。 ([AWS Documentation][7])

4. **動作確認**

   * 正常系: `aws lambda invoke --function-name <name> out.json`
   * エラー: Lambda 環境変数 `FORCE_ERROR=1` を設定して実行 → **アラーム** → Slack。
   * タイムアウト: `FORCE_TIMEOUT=1` とし timeout を短めに → **アラーム** → Slack。
   * 非同期失敗: 非同期呼び出し（`InvocationType=Event` など）でエラー → **詳細メッセージ**が Slack へ。

---

## 5) Slack メッセージ例（実際の通知イメージ）

* **アラーム経由（Errors >= 1）**

  ```
  🔔 Lambda失敗アラーム
  アラーム: lambda-sample-image-Errors
  状態: ALARM
  理由: Threshold Crossed: ...
  時刻: 2025-09-10T00:12:34Z
  リージョン: ap-northeast-1 / アカウント: 123456789012
  CloudWatch アラームを開く（リンク）
  ```

* **非同期失敗イベント（詳細）**

  ```
  ❌ Lambda非同期失敗
  関数: arn:aws:lambda:ap-northeast-1:123456789012:function:lambda-sample-image
  RequestId: 1234abcd-...
  条件: RetriesExhausted / 試行回数: 3
  エラー: Unhandled (200)
  メッセージ: Process exited before completing request
  時刻: 2025-09-10T00:15:22Z (ap-northeast-1)
  ```

> 上記は **EventBridge Input Transformer** で生成しています。テンプレートは JSON 文字列で、Slack の装飾（太字、改行、絵文字、リンク）をそのまま埋め込み可能です。 ([AWS Documentation][11])

---

## 6) 設計メモ／補足

* **なぜアラーム→EventBridge 経由なのか**
  CloudWatch アラームに SNS アクションを直接ぶら下げるとメッセージ整形ができません。**アラーム状態変化イベント**を EventBridge で受け、**Input Transformer** で整形して SNS→Slack に流すと、読みやすい通知を作れます。 ([AWS Documentation][10])
* **タイムアウト検知**
  Lambda の `Errors` は\*\*コード例外＋ランタイム例外（タイムアウト等）\*\*をカウントします。よって Timeout も ①で検知します。 ([AWS Documentation][3])
* **非同期の詳細**
  `detail.requestContext.requestId`、`responseContext.functionError`、`responsePayload.errorMessage` 等を使って**原因究明に有用な情報**を Slack に載せています。イベントの構造は公式仕様です。 ([AWS Documentation][8])
* **ErrorRate アラーム**
  トラフィックに応じた相対監視が可能（Metric Math）。 ([AWS Documentation][12])
* **Amazon Q Developer（旧 AWS Chatbot）**
  サービス名は 2025/02 に改称されましたが、**SNS 連携／Terraform リソース名は従来どおり**です。 ([AWS Documentation][1])

---

### 参考（一次情報）

* **EventBridge Input Transformer**（文字列テンプレート／ JSONPath） ([AWS Documentation][11])
* **CloudWatch → EventBridge（アラーム状態変更イベント）** ([AWS Documentation][10])
* **Lambda Destinations（非同期失敗 → EventBridge）** ([AWS Documentation][8])
* **Lambda `Errors` の定義（タイムアウト含む）** ([AWS Documentation][3])
* **Python 3.12 のコンテナデプロイ**（AWS 提供ベースイメージ） ([AWS Documentation][4], [gallery.ecr.aws][5])
* **Amazon Q Developer in chat applications 仕様／Slack 連携**（CFN/ガイド） ([AWS Documentation][7])

---

## 7) そのまま使うための最小 TODO

1. `Makefile` でイメージを **build/push** → `print-image-uri` を `infra/terraform.tfvars` の `image_uri` に反映。
2. Amazon Q Developer（旧 AWS Chatbot）でワークスペースを**初回認可**し、`slack_workspace_id`/`slack_channel_id` を設定。 ([AWS Documentation][7])
3. `terraform apply`。

---

必要であれば、**Composite Alarm** 化（ノイズ低減）、**DLQ/SQS** 経由の運用、**Slack でのインタラクティブ操作（Guardrail 設計）** まで拡張したテンプレートもお作りします。Python ランタイムを **3.12/3.13** や **arm64/x86\_64** で切り替える変数化も対応可能です。

[1]: https://docs.aws.amazon.com/chatbot/latest/adminguide/service-rename.html?utm_source=chatgpt.com "Amazon Q Developer in chat applications rename"
[2]: https://registry.terraform.io/providers/hashicorp/aws/6.5.0/docs/resources/chatbot_slack_channel_configuration?utm_source=chatgpt.com "aws_chatbot_slack_channel_co..."
[3]: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html?utm_source=chatgpt.com "Types of metrics for Lambda functions"
[4]: https://docs.aws.amazon.com/lambda/latest/dg/python-image.html?utm_source=chatgpt.com "Deploy Python Lambda functions with container images"
[5]: https://gallery.ecr.aws/lambda/python?utm_source=chatgpt.com "AWS Lambda/python - Amazon ECR Public Gallery"
[6]: https://aws.amazon.com/blogs/compute/python-3-12-runtime-now-available-in-aws-lambda/?utm_source=chatgpt.com "Python 3.12 runtime now available in AWS Lambda"
[7]: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-chatbot-slackchannelconfiguration.html "AWS::Chatbot::SlackChannelConfiguration - AWS CloudFormation"
[8]: https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html "Capturing records of Lambda asynchronous invocations - AWS Lambda"
[9]: https://docs.aws.amazon.com/chatbot/latest/adminguide/what-is.html?utm_source=chatgpt.com "Amazon Q Developer in chat applications - AWS Documentation"
[10]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-and-eventbridge.html "Alarm events and EventBridge - Amazon CloudWatch"
[11]: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-transform-target-input.html "Amazon EventBridge input transformation - Amazon EventBridge"
[12]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/using-metric-math.html?utm_source=chatgpt.com "Using math expressions with CloudWatch metrics"
