## Lambda Container + Slack Alerts (SNS -> Lambda -> Webhook)

本リポジトリは、Python 3.12 のコンテナイメージで実装した AWS Lambda をデプロイし、失敗（エラー/タイムアウト）を Slack へ通知するテンプレートです。通知は Amazon Q Developer（旧 Chatbot）ではなく、SNS → Lambda → Slack Incoming Webhook 経由で配信します。

---

## リポジトリ構成

- `src/lambda_sample/` – Lambda 本体（Python 3.12, コンテナイメージ）
- `src/notify_slack/` – SNS購読 Lambda（Slack Webhook へ Block Kit で投稿）
- `infra/` – Terraform 定義（Lambda/SNS/IAM など）
- `Dockerfile` – Lambda コンテナ（ベース: `public.ecr.aws/lambda/python:3.12`）
- `Makefile` – コンテナの build/push 補助
- `tests/` – 最小限のユニットテスト
- `docs/` – 設計/手順（`rdd.md`, `design.md`, `plan.md`）

---

## 要件

- AWS CLI v2 / Docker Buildx / Terraform >= 1.6 / AWS Provider ~> 6.5
- Slack Incoming Webhook URL（機密情報）

---

## セットアップとデプロイ

1) コンテナのビルド/プッシュ
- 変数例: `REGION=ap-northeast-1 REPO=lambda-sample TAG=v1`
- コマンド:
  - `make build push REGION=${REGION} REPO=${REPO} TAG=${TAG}`
  - ECR リポジトリは未作成なら自動作成されます

2) Terraform 変数設定
- `infra/terraform.tfvars` を作成（例 `infra/terraform.tfvars.example` を参考）
- 必須:
  - `region = "ap-northeast-1"`
  - `ecr_repository_name = "lambda-sample"`（Makefile の `REPO` と一致）
  - `image_tag = "v1"`（Makefile の `TAG` と一致）
  - `slack_webhook_url = "https://hooks.slack.com/services/xxx/yyy/zzz"`（機密）

3) Terraform 適用
- `cd infra && terraform init -upgrade && terraform apply -auto-approve`

4) 動作確認
- 正常: `aws lambda invoke --function-name <lambda-name> out.json`
- エラー: 環境変数 `FORCE_ERROR=1` を設定して実行 → CloudWatch アラーム発火 → Slack 通知
- タイムアウト: `FORCE_TIMEOUT=1` + 短い `timeout` 設定 → Slack 通知

---

## 通知の仕組み（現行）

- CloudWatch アラーム（`AWS/Lambda:Errors`）→ SNS トピック（`lambda-alerts`）→ SNS購読 Lambda（`notify-slack`）→ Slack Webhook
- Slack メッセージは Block Kit で整形（ヘッダー/状態/理由/リージョン/アカウント/リンク）。
- CloudWatch へのリンクはアラーム ARN からリージョンコードを抽出して生成します。

---

## イメージ更新ポリシー（タグ固定 + ダイジェスト解決）

- Terraform は `ecr_repository_name` と `image_tag` から ECR の最新ダイジェストを解決し、`repo_url@sha256:<digest>` で Lambda を更新します。
- フロー:
  1. 同じ `TAG` で新イメージを `docker push`
  2. `terraform apply` でダイジェスト差分を検知し Lambda を更新

---

## 開発コマンド

- `make build` – コンテナビルド（`--platform linux/arm64`）
- `make push` – ECR へプッシュ（自動ログイン/作成）
- `make test` – テスト実行（`pytest` があれば）

テスト（ローカル）:
- `pip install pytest`
- `make test`

---

## セキュリティ/運用メモ

- Slack Webhook URL は機密です。リポジトリに直接コミットせず、`terraform.tfvars` の保護や CI の Secrets を利用してください。必要であれば SSM/Secrets Manager 管理に変更可能です。
- IAM は最小権限で構成：
  - アプリ Lambda: `AWSLambdaBasicExecutionRole`
  - 通知 Lambda: `AWSLambdaBasicExecutionRole`
  - SNS トピックポリシー: `cloudwatch.amazonaws.com` の `SNS:Publish` のみ許可
- ノイズ対策は ErrorRate（Metric Math）や Composite Alarm で拡張可能です。

---

## 既知事項

- Slack のボタン（インタラクティブ要素）は Webhook では制限があるため、テキストリンクで提供しています。
- 非同期呼び出し失敗の EventBridge 詳細通知は本テンプレートから除外しています（必要な場合は SNS→Lambda での整形配信に拡張可能）。

---

## 参考

- `docs/rdd.md` – 要件/設計方針
- `docs/design.md` – 具体構成と Terraform 例
- AWS Lambda コンテナイメージ: `public.ecr.aws/lambda/python:3.12`

---

## トラブルシュート（抜粋）

- Slack に届かない
  - SNS トピック `lambda-alerts` → サブスクリプションに `notify-slack` の Lambda が登録/確認済みか
  - CloudWatch アラームの `alarm_actions` に SNS トピックが設定されているか
- CloudWatch リンクが開けない
  - アラーム発報メッセージに `AlarmArn` が含まれるか（リージョンコードの抽出に使用）

---

## ライセンス

本プロジェクトのライセンスは [LICENSE](LICENSE) を参照してください。
