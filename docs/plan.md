# 作業手順計画（Lambda コンテナ + Slack 通知）

`docs/rdd.md` と `docs/design.md` を踏まえた、実行可能な作業手順のまとめです。

---

## ゴール

- Python 3.12+ のコンテナイメージで AWS Lambda をデプロイする。
- Lambda の失敗（エラー/タイムアウト）を Slack へ通知する。
- ベースライン: CloudWatch `AWS/Lambda:Errors` アラーム → SNS → Amazon Q Developer（旧 AWS Chatbot）→ Slack。
- 任意: 非同期失敗の詳細（RequestId/メッセージ等）を EventBridge で整形して Slack へ。

参考: `docs/rdd.md`, `docs/design.md`

---

## 前提条件

- ツール: AWS CLI v2, Docker Buildx, Terraform ≥ 1.6（パスAの場合）。
- AWS リージョン例: `ap-northeast-1`（ECR と Lambda は同一リージョン）。
- Slack ワークスペースは Amazon Q Developer in chat applications で初回認可済み（Workspace/Channel ID 取得）。
- IAM 権限: ECR/Lambda/IAM/SNS/CloudWatch/EventBridge/Chatbot の作成権限。

---

## 実施パス（概要）

- パスA（推奨）: Terraform で一括構築 + Slack メッセージ整形
  - 生成物: Lambda（Image）, SNS, Slack チャネル構成, `Errors` アラーム, EventBridge ルール/ターゲット（Input Transformer による整形）, 非同期 OnFailure → EventBridge。
- パスB: AWS CLI 最小構成（ベースライン通知のみ、必要に応じ詳細通知追加）
  - 生成物: Lambda（Image）, SNS, `Errors` アラーム, Slack 連携（コンソール設定）。任意で OnFailure → EventBridge → SNS。

詳細の定義例・スニペットは `docs/design.md` / `docs/rdd.md` を参照。

---

## パスA（Terraform）

1) コンテナイメージのビルド/プッシュ

- 変数: `REGION=ap-northeast-1`, `REPO=lambda-sample`, `TAG=v1`
- 推奨コマンド（M1/ARM の例）: `docker buildx build --platform linux/arm64 --provenance=false -t <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/<REPO>:<TAG> .` → `docker push ...`
- 参考: `docs/design.md` の Makefile とコマンド例。

2) Terraform 変数を設定

- `infra/terraform.tfvars` に以下を設定:
  - `image_uri`（上記でプッシュした ECR の URI）
  - `slack_workspace_id`, `slack_channel_id`
  - `lambda_function_name` 他（必要に応じて）

3) Terraform を適用

- `cd infra && terraform init && terraform apply -auto-approve`
- 生成: Lambda（Image）, SNS, Slack チャネル構成, `Errors` アラーム, EventBridge（アラーム整形/非同期失敗詳細）。

4) 動作確認

- 正常: `aws lambda invoke --function-name <name> out.json`
- エラー: 環境変数 `FORCE_ERROR=1` で実行 → Slack（アラーム経由）
- タイムアウト: `FORCE_TIMEOUT=1` + 短い `timeout` → Slack（アラーム経由）
- 非同期失敗: `InvocationType=Event` で失敗 → Slack（詳細メッセージ）

---

## パスB（AWS CLI 最小構成）

1) ECR 作成/ログイン（初回）

- `aws ecr create-repository --repository-name <REPO> --image-scanning-configuration scanOnPush=true --region <REGION>`
- `aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com`

2) コンテナビルド/プッシュ（M1/ARM の例）

- `docker buildx build --platform linux/arm64 --provenance=false -t <IMAGE_URI> .` → `docker push <IMAGE_URI>`

3) Lambda 実行ロール作成

- 信頼ポリシー: `docs/rdd.md` の `iam/trust-policy.json` 例を使用。
- `aws iam create-role --role-name lambda-basic-exec-role --assume-role-policy-document file://iam/trust-policy.json`
- `aws iam attach-role-policy --role-name lambda-basic-exec-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole`

4) Lambda 関数作成（コンテナイメージ）

- `aws lambda create-function --function-name lambda-sample-image --package-type Image --code ImageUri=<IMAGE_URI> --role <ROLE_ARN> --architectures arm64 --timeout 10 --memory-size 1024 --region <REGION>`

5) SNS トピック作成

- `TOPIC_ARN=$(aws sns create-topic --name lambda-alerts --query TopicArn --output text --region <REGION>)`

6) CloudWatch アラーム（Errors ≥ 1, 1 分）

- `aws cloudwatch put-metric-alarm --alarm-name "LambdaErrors-lambda-sample-image" --metric-name Errors --namespace AWS/Lambda --dimensions Name=FunctionName,Value=lambda-sample-image --statistic Sum --period 60 --evaluation-periods 1 --threshold 0 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching --alarm-actions ${TOPIC_ARN} --region <REGION>`

7) Slack 連携（Amazon Q Developer）

- コンソールでワークスペース/チャンネルを連携し、上記 SNS トピックを購読に追加（テスト通知で確認）。

8) 任意: 非同期失敗の詳細通知を追加

- OnFailure → EventBridge: `aws lambda update-function-event-invoke-config --function-name lambda-sample-image --destination-config "OnFailure={Destination=arn:aws:events:<REGION>:<ACCOUNT_ID>:event-bus/default}"`
- 失敗イベント ルール/ターゲットを作成し SNS へ転送（整形が必要なら EventBridge Input Transformer を使用）。例は `docs/rdd.md` / `docs/design.md` を参照。

---

## テスト観点

- 同期失敗検知: `FORCE_ERROR=1` / `FORCE_TIMEOUT=1` → `Errors` 上昇 → アラーム → Slack。
- 非同期失敗詳細: 非同期呼び出し（`InvocationType=Event`）でエラー → 詳細通知（設定時）。
- Slack 側: 初回は Amazon Q Developer コンソールの「テスト通知」で受信確認。

---

## 運用メモ / よくある落とし穴

- `Errors` はタイムアウトを含む（ベースラインで Timeout 検知可）。
- ECR と Lambda のリージョンは一致させる。
- Docker Buildx は `--provenance=false` を付与（互換性のため）。
- `arm64`（Graviton）でコスト/性能向上が見込める。
- ノイズ対策: Metric Math による `ErrorRate`、必要に応じ Composite Alarm。

---

## 最小 TODO チェックリスト

- [ ] 実施パスを選定（A: Terraform / B: CLI）
- [ ] イメージを ECR に build/push（`--platform linux/arm64` 推奨）
- [ ] Slack ワークスペースを Amazon Q Developer で認可（Workspace/Channel ID 取得）
- [ ] パスA: `terraform apply` ／ パスB: SNS/アラーム/Slack 連携を作成
- [ ] 同期/非同期の動作確認（正常・エラー・タイムアウト）

---

詳細のコードと完全なテンプレートは `docs/design.md`、背景と設計判断は `docs/rdd.md` を参照してください。

