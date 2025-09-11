import json
import os
import urllib.parse
import urllib.request


def _post_slack(webhook_url: str, payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as resp:  # nosec - webhook to Slack
        if resp.status >= 300:
            raise RuntimeError(f"Slack webhook failed: {resp.status}")

def _build_alarm_blocks(m: dict) -> list:
    name = m.get("AlarmName") or "(unknown)"
    state = m.get("NewStateValue") or m.get("StateValue") or "ALARM"
    reason = (m.get("NewStateReason") or "").strip()
    # CloudWatch Alarm の SNS JSON は Region に表示名（例: "Asia Pacific (Tokyo)") を入れることがある
    region_display = m.get("Region") or ""
    account = m.get("AWSAccountId") or ""
    time = m.get("StateChangeTime") or m.get("Timestamp") or ""

    # Console link 用リージョンはコード（ap-northeast-1）が必要
    # AlarmArn からリージョン/アカウントを優先取得
    alarm_arn = m.get("AlarmArn") or ""
    region_code = ""
    if alarm_arn:
        try:
            parts = alarm_arn.split(":")  # arn:aws:cloudwatch:<region>:<account>:alarm:<name>
            region_code = parts[3]
            account = account or parts[4]
        except Exception:
            region_code = ""
    if not region_code:
        region_code = os.getenv("AWS_REGION", "")

    # Console link（リージョンはコードを使用）
    name_enc = urllib.parse.quote(name, safe="")
    link = (
        f"https://console.aws.amazon.com/cloudwatch/home?region={region_code}#alarmsV2:alarm/{name_enc}"
        if region_code and name
        else None
    )

    fields = []
    fields.append({"type": "mrkdwn", "text": f"*状態*: `{state}`"})
    if region_display or account or region_code:
        region_text = region_code or region_display
        fields.append({"type": "mrkdwn", "text": f"*リージョン*: `{region_text}`  /  *アカウント*: `{account}`"})
    if time:
        fields.append({"type": "mrkdwn", "text": f"*時刻*: `{time}`"})

    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": "🔔 CloudWatch Alarm"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*アラーム*: `{name}`"}},
    ]
    if fields:
        blocks.append({"type": "section", "fields": fields})
    if reason:
        # Reason が長すぎる場合は適度にトリム
        if len(reason) > 1200:
            reason = reason[:1200] + "…"
        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": f"*理由*: {reason}"}})
    if link:
        blocks.append({
            "type": "section",
            "text": {"type": "mrkdwn", "text": f"<{link}|CloudWatch で開く>"},
        })
    return blocks


def handler(event, _context):
    webhook = os.getenv("SLACK_WEBHOOK_URL")
    if not webhook:
        raise RuntimeError("SLACK_WEBHOOK_URL is not set")

    # SNS 通知形式に対応
    # Records: [{ Sns: { Message, Subject, MessageAttributes, ... } }]
    records = event.get("Records", []) if isinstance(event, dict) else []
    for rec in records:
        sns = rec.get("Sns", {})
        subject = sns.get("Subject")
        message = sns.get("Message")

        # CloudWatch Alarm の場合、Message は JSON のことが多い
        # JSON のときは Block Kit で整形
        payload = None
        try:
            m = json.loads(message)
            blocks = _build_alarm_blocks(m)
            payload = {
                "text": f"CloudWatch Alarm: {m.get('AlarmName')}",  # Fallback
                "blocks": blocks,
            }
        except Exception:
            # JSON でない場合はそのままテキスト送信
            payload = {"text": f"{subject or 'SNS Notification'}\n{message}"}

        _post_slack(webhook, payload)

    return {"ok": True, "count": len(records)}
