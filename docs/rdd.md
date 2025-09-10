以下は、**Python 3.12 以上を用いたコンテナイメージ（Docker）デプロイの AWS Lambda** と、**Lambda がエラー／タイムアウトで失敗した際に Slack へ通知**するための、最新情報を踏まえた設計書です。
（注：2025年現在、AWS Chatbot は **Amazon Q Developer in chat applications** に改称されています。以下では機能名の混乱を避けるため、新名称を基本に記載します。）([AWS Documentation][1])

---

## 0. 目的・要件

* **目的**：

  * Python 3.12 以上で実装した Lambda 関数を **コンテナイメージ（Docker）** としてデプロイする。
  * \*\*Lambda 自体が失敗（エラー／タイムアウト）\*\*した場合に **Slack に通知**する。

* **非機能要件（抜粋）**：

  * 再現性の高いビルド（Dockerfile をソース管理）。
  * 失敗検知は同期／非同期いずれの呼び出しでも確実に検知（CloudWatch メトリクスベース）。
  * 可能なら ARM64（Graviton）でのコスト最適化。([Amazon Web Services, Inc.][2])

---

## 1. 全体アーキテクチャ

```
[Developer(M1 Mac)] -- docker buildx --> [ECR Private Repository]
                                           |
                                           v
                                      [AWS Lambda (Image)]
                                           |
                             +-------------+-------------+
                             |                           |
                      [CloudWatch Metrics]         (オプション/非同期)
                             |                           |
                     [CloudWatch Alarms]          [Lambda Destinations: OnFailure -> EventBridge]
                             |                           | 
                             v                           v
                         [SNS Topic]               [EventBridge Rule (Failure)]
                             \_______________________/      |
                                      |                     |
                               [Amazon Q Developer in chat applications]
                                      |
                                   [Slack]
```

* **ベースライン通知**：CloudWatch の **Errors** メトリクスに対するアラーム → SNS → Amazon Q Developer（旧 AWS Chatbot）→ Slack。これにより**同期／非同期問わず**失敗を検知可能（Timeout も `Errors` にカウント）。([AWS Documentation][3])
* **詳細な失敗ペイロード（任意/非同期時）**：非同期呼び出しで **Lambda Destinations（OnFailure）→ EventBridge** を有効化し、該当イベント（`detail-type: "Lambda Function Invocation Result - Failure"`）を SNS → Slack にルーティング。失敗イベントの詳細 JSON を活用できます。([AWS Documentation][4])

---

## 2. 使用サービスと最新トピック

* **AWS Lambda（コンテナイメージ対応）**

  * Python 3.12/3.13 の **公式ベースイメージ**が提供（AL2023 ベース）。`public.ecr.aws/lambda/python:3.12` など。Docker Buildx は `--provenance=false` 指定が必要。([AWS Documentation][5])
  * **コンテナサイズ上限**：展開後（uncompressed）**10GB**。([AWS Documentation][6])
  * **アーキテクチャ**：x86\_64 / **arm64**（Graviton）に対応。arm64 は**最大 34% の価格性能向上**。([AWS Documentation][7], [Amazon Web Services, Inc.][2], [Serverless Land][8])
* **Amazon ECR**：コンテナイメージの保管庫。ECR と Lambda のリージョンは一致させる必要あり。([AWS Documentation][9])
* **Amazon CloudWatch（メトリクス／アラーム）**：`Errors` は\*\*コード例外／ランタイム例外（タイムアウト含む）\*\*をカウント。1 分粒度。([AWS Documentation][3])
* **Amazon SNS**：通知のファンアウト。
* **Amazon Q Developer in chat applications（旧 AWS Chatbot）**：Slack 連携の公式経路（SNS 購読）。コンソールまたは CloudFormation で設定。([AWS Documentation][10])
* **Amazon EventBridge（任意/非同期）**：`Lambda Function Invocation Result - Failure` イベントで失敗詳細を配信。([AWS Documentation][4])

---

## 3. リポジトリ構成（例）

```
lambda-sample/
├── app/
│   ├── lambda_function.py
│   └── requirements.txt
├── Dockerfile
└── iam/
    └── trust-policy.json
```

---

## 4. Lambda コード（Python 3.12）

`app/lambda_function.py`

```python
import json
import logging
import os
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    # デモ用の挙動切替（環境変数で制御）
    if os.getenv("FORCE_TIMEOUT") == "1":
        # Lambda のタイムアウトに達するまでスリープ（テスト用途）
        # 実際のタイムアウト時間は関数設定の timeout に依存
        while True:
            time.sleep(1)

    if os.getenv("FORCE_ERROR") == "1":
        raise RuntimeError("FORCED_ERROR: 意図的な失敗を発生させました")

    logger.info({"event": event, "request_id": context.aws_request_id})
    return {
        "statusCode": 200,
        "body": json.dumps({"message": "OK", "req": context.aws_request_id})
    }
```

---

## 5. Dockerfile（公式ベースイメージ・最小構成）

`Dockerfile`

```dockerfile
# Python 3.12 公式 Lambda ベースイメージ（AL2023）
FROM public.ecr.aws/lambda/python:3.12

# 依存ライブラリ
COPY app/requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
# pip で Lambda のタスクルートへインストール
RUN pip install -r ${LAMBDA_TASK_ROOT}/requirements.txt

# アプリ本体
COPY app/ ${LAMBDA_TASK_ROOT}/

# ハンドラを指定
CMD [ "lambda_function.handler" ]
```

> 参考：AWS 公式ドキュメントの Python ベースイメージと Dockerfile 例、および `--provenance=false` の注意事項。([AWS Documentation][5])

> **M1/ARM Mac 対応**：`docker buildx` の `--platform linux/arm64` を指定すれば Graviton 向けにビルド可能（Lambda 側の `Architectures=arm64` と揃える）。([AWS Documentation][5], [Amazon Web Services, Inc.][11])

（オプション）**uv を使う場合**：
`RUN pip install ...` を `RUN uv pip install --system -r ${LAMBDA_TASK_ROOT}/requirements.txt` に置換しても動作します（uv は pip 互換の引数をサポート）。

---

## 6. ビルド & デプロイ手順（CLI）

### 6.1 ECR リポジトリの作成とログイン

```bash
AWS_REGION=ap-northeast-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO=lambda-sample

aws ecr create-repository --repository-name ${REPO} --image-scanning-configuration scanOnPush=true --region ${AWS_REGION}

aws ecr get-login-password --region ${AWS_REGION} \
| docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

([AWS Documentation][12])

### 6.2 コンテナビルド & プッシュ（M1/ARM の例）

```bash
IMAGE_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO}:v1

docker buildx build --platform linux/arm64 --provenance=false -t ${IMAGE_URI} .
docker push ${IMAGE_URI}
```

([AWS Documentation][5])

### 6.3 Lambda 関数作成（コンテナイメージ）

```bash
ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/lambda-basic-exec-role

aws lambda create-function \
  --function-name lambda-sample-image \
  --package-type Image \
  --code ImageUri=${IMAGE_URI} \
  --role ${ROLE_ARN} \
  --architectures arm64 \
  --timeout 10 \
  --memory-size 1024 \
  --region ${AWS_REGION}
```

> コンテナ画像パッケージでは `--package-type Image` を指定し、`handler` や `runtime` は不要です。ECR と Lambda は**同一リージョン**であること。([AWS Documentation][13])

---

## 7. IAM（最小構成）

### 7.1 実行ロール（信頼ポリシー）

`iam/trust-policy.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

ロール作成と基本ポリシー付与：

```bash
aws iam create-role \
  --role-name lambda-basic-exec-role \
  --assume-role-policy-document file://iam/trust-policy.json

aws iam attach-role-policy \
  --role-name lambda-basic-exec-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

（CloudWatch Logs 出力に必要）

---

## 8. 監視・通知（Slack 連携）

### 8.1 ベースライン：CloudWatch アラーム → SNS → Slack

1. **SNS トピック**作成：

```bash
TOPIC_ARN=$(aws sns create-topic --name lambda-alerts --query TopicArn --output text --region ${AWS_REGION})
```

2. **CloudWatch アラーム**（Errors ≥ 1 を 1 分で検知）：

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "LambdaErrors-lambda-sample-image" \
  --alarm-description "lambda-sample-image でエラー（Timeout含む）が発生" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=lambda-sample-image \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions ${TOPIC_ARN} \
  --region ${AWS_REGION}
```

> **Errors** メトリクスは\*\*コード例外とランタイム例外（タイムアウト等）\*\*を含みます（＝タイムアウトも検知）。([AWS Documentation][3])

（任意）**エラー率**で監視する場合（Metric Math）：

* `ErrorRate = 100 * (SUM(Errors) / MAX([SUM(Invocations), 1]))` のような数式でアラームを定義。([AWS Documentation][14])

3. **Slack 連携（Amazon Q Developer in chat applications）**

   * 管理コンソールで **Slack ワークスペースとチャンネルを連携**し、**SNS トピック（上記 `lambda-alerts`）を購読**に追加。([AWS Documentation][1])
   * 動作確認はコンソールの **「テスト通知」** から実施可能。([AWS Documentation][15])

> 旧称 AWS Chatbot ですが、現在は **Amazon Q Developer in chat applications** に統合されています。SNS 連携のアーキテクチャは継続。([AWS Documentation][10])

### 8.2（任意）非同期の詳細通知：Destinations → EventBridge → SNS → Slack

* Lambda を **非同期**で呼ぶワークロードがある場合、**OnFailure** で **EventBridge（既定バス）** を宛先に設定すると、失敗時に **`detail-type: "Lambda Function Invocation Result - Failure"`** のイベントが発火。このイベントを EventBridge ルールで **SNS トピック**に転送し、Slack 通知に使えます。([AWS Documentation][4])

**OnFailure 設定（例）**：

```bash
DEFAULT_BUS_ARN=arn:aws:events:${AWS_REGION}:${ACCOUNT_ID}:event-bus/default

aws lambda update-function-event-invoke-config \
  --function-name lambda-sample-image \
  --destination-config "OnFailure={Destination=${DEFAULT_BUS_ARN}}" \
  --region ${AWS_REGION}
```

**EventBridge ルール（関数限定の失敗のみ抽出）**：

```bash
aws events put-rule \
  --name lambda-sample-image-failures \
  --event-pattern '{
    "source": ["lambda"],
    "detail-type": ["Lambda Function Invocation Result - Failure"],
    "detail": { "requestContext": { "functionArn": [{ "prefix": "arn:aws:lambda:'"${AWS_REGION}"':'"${ACCOUNT_ID}"':function:lambda-sample-image" }] } }
  }' \
  --region ${AWS_REGION}

aws events put-targets \
  --rule lambda-sample-image-failures \
  --targets "Id"="snsTarget","Arn"="${TOPIC_ARN}" \
  --region ${AWS_REGION}
```

> 注：上記は **非同期**呼び出し時に有効なパターンです。同期呼び出しでは Destinations は用いず、**CloudWatch アラーム**を利用してください。([AWS Documentation][4])

---

## 9. Slack 連携の IaC（CloudFormation 例：最小）

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Slack channel configuration for Amazon Q Developer (旧 AWS Chatbot)
Resources:
  SlackChannel:
    Type: AWS::Chatbot::SlackChannelConfiguration
    Properties:
      ConfigurationName: lambda-alerts-channel
      SlackWorkspaceId: !Ref SlackWorkspaceId   # 例: 'T0ABCDEF'
      SlackChannelId:   !Ref SlackChannelId     # 例: 'C0GHJKLMN'
      IamRoleArn:       !Ref ChatbotIamRoleArn
      SnsTopicArns:
        - arn:aws:sns:ap-northeast-1:123456789012:lambda-alerts
      LoggingLevel: INFO
Parameters:
  SlackWorkspaceId: { Type: String }
  SlackChannelId:   { Type: String }
  ChatbotIamRoleArn:{ Type: String }
```

> `AWS::Chatbot::SlackChannelConfiguration` により SNS トピックを Slack にひも付けます。([AWS Documentation][16])

---

## 10. 運用（監視・可観測性）

* **アラーム設計の推奨**：

  * **Errors ≥ 1**（本番は短い評価期間で即検知）
  * **ErrorRate ≥ X%**（実行頻度に応じた相対監視）
  * （必要に応じて）**Throttles**、**Duration p95** なども追加。
* **ログ**：`/aws/lambda/<関数名>` に出力。Timeout はログに `Task timed out` と出ます（メトリクスは `Errors` に計上）。([Repost][17], [AWS Documentation][3])
* **通知ノイズ低減**：Composite Alarm（複合アラーム）も Amazon Q Developer でサポート。([AWS Documentation][10])

---

## 11. テスト手順

1. **正常系**：`aws lambda invoke --function-name lambda-sample-image out.json`
2. **強制エラー**：環境変数 `FORCE_ERROR=1` を設定 → 実行 → Slack にアラート。
3. **強制タイムアウト**：`FORCE_TIMEOUT=1` とし、関数の `timeout` を短く設定 → 実行 → Slack にアラート。

   * いずれも `Errors` が上がり、アラーム経由で通知されます（Timeout も Errors に含む）。([AWS Documentation][3])

---

## 12. コスト最適化

* **arm64（Graviton）** への切替で**最大 34% の価格性能向上**が見込めます。ビルド時に `--platform linux/arm64`、Lambda 作成時に `--architectures arm64` を指定。([Amazon Web Services, Inc.][2], [Serverless Land][8])

---

## 13. 付録：よくあるハマりどころ

* **ECR と Lambda のリージョン不一致** → 作成に失敗。必ず同一リージョンに。([AWS Documentation][9])
* **Docker buildx** で **`--provenance=false`** を付けない → 一部環境でイメージ互換性エラー。([AWS Documentation][5])
* **非同期の失敗詳細を取りたいのに届かない** → Destinations（OnFailure）未設定 or 同期呼び出しである可能性。([AWS Documentation][4])

---

## 参考（主要ソース）

* **Python コンテナデプロイ（3.12/3.13、AL2023、Dockerfile 例、buildx注意点）** ([AWS Documentation][5])
* **コンテナイメージ上限 10GB** ([AWS Documentation][6])
* **Lambda Errors（Timeout を含む）** ([AWS Documentation][3], [Amazon Web Services, Inc.][18])
* **Destinations / EventBridge（Failure イベント）** ([AWS Documentation][4])
* **Slack 連携（Amazon Q Developer in chat applications）** ([AWS Documentation][1])
* **Graviton（arm64）価格性能** ([Amazon Web Services, Inc.][2])
* **ECR ログイン & 作成 CLI** ([AWS Documentation][19])

---

### すぐに使えるコマンド・スニペットまとめ

* **ビルド & プッシュ**：`docker buildx build --platform linux/arm64 --provenance=false ... && docker push ...` ([AWS Documentation][5])
* **関数作成（Image パッケージ）**：`aws lambda create-function --package-type Image --code ImageUri=...` ([AWS Documentation][13])
* **エラー検知アラーム**：`aws cloudwatch put-metric-alarm --metric-name Errors ...`
* **Slack 連携**：Amazon Q Developer で **SNS トピックをチャンネルに関連付け**（テスト通知可）。([AWS Documentation][1])

---

必要であれば、**Terraform/CDK 化**や、**Slack メッセージの整形（EventBridge Input Transformer や Amazon Q Developer のカスタム通知）** まで落とし込んだテンプレートもご用意できます。
運用環境の前提（ワークロードの同期／非同期、想定トラフィック、通知閾値の運用ポリシーなど）があれば、それに合わせてしきい値やアーキテクチャ（Composite Alarm、ErrorRate 監視、Dead Letter Queue など）を最適化します。

[1]: https://docs.aws.amazon.com/chatbot/latest/adminguide/slack-setup.html "Tutorial: Get started with Slack - Amazon Q Developer in chat applications"
[2]: https://aws.amazon.com/blogs/aws/aws-lambda-functions-powered-by-aws-graviton2-processor-run-your-functions-on-arm-and-get-up-to-34-better-price-performance/?utm_source=chatgpt.com "AWS Lambda Functions Powered by AWS Graviton2 ..."
[3]: https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html?utm_source=chatgpt.com "Types of metrics for Lambda functions"
[4]: https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html "Capturing records of Lambda asynchronous invocations - AWS Lambda"
[5]: https://docs.aws.amazon.com/lambda/latest/dg/python-image.html "Deploy Python Lambda functions with container images - AWS Lambda"
[6]: https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html?utm_source=chatgpt.com "Lambda quotas"
[7]: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html?utm_source=chatgpt.com "Lambda runtimes"
[8]: https://serverlessland.com/content/service/lambda/guides/cost-optimization/2-graviton?utm_source=chatgpt.com "Cost Optimization for AWS Lambda | 2. Switch to Graviton2"
[9]: https://docs.aws.amazon.com/lambda/latest/dg/images-create.html?utm_source=chatgpt.com "Create a Lambda function using a container image"
[10]: https://docs.aws.amazon.com/chatbot/latest/adminguide/related-services.html "Monitoring AWS services using Amazon Q Developer in chat applications - Amazon Q Developer in chat applications"
[11]: https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-to-arm-based-aws-graviton2-processors/?utm_source=chatgpt.com "Migrating AWS Lambda functions to Arm-based ..."
[12]: https://docs.aws.amazon.com/cli/latest/reference/ecr/create-repository.html?utm_source=chatgpt.com "create-repository — AWS CLI 2.28.26 Command Reference"
[13]: https://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html?utm_source=chatgpt.com "create-function — AWS CLI 2.28.26 Command Reference"
[14]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create-alarm-on-metric-math-expression.html?utm_source=chatgpt.com "Create a CloudWatch alarm based on a metric math expression"
[15]: https://docs.aws.amazon.com/chatbot/latest/adminguide/test-notifications-cw.html?utm_source=chatgpt.com "Test notifications from AWS services to chat channels using ..."
[16]: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-chatbot-slackchannelconfiguration.html?utm_source=chatgpt.com "Chatbot::SlackChannelConfiguration - AWS CloudFormation"
[17]: https://repost.aws/knowledge-center/lambda-verify-invocation-timeouts?utm_source=chatgpt.com "Use CloudWatch logs to determine if a Lambda function ..."
[18]: https://aws.amazon.com/blogs/mt/monitoring-aws-lambda-errors-using-amazon-cloudwatch/?utm_source=chatgpt.com "Monitoring AWS Lambda errors using Amazon CloudWatch"
[19]: https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html?utm_source=chatgpt.com "Private registry authentication in Amazon ECR"
