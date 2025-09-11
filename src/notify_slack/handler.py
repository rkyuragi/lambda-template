import json
import os
import urllib.request


def _post_slack(webhook_url: str, text: str) -> None:
    data = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as resp:  # nosec - webhook to Slack
        if resp.status >= 300:
            raise RuntimeError(f"Slack webhook failed: {resp.status}")


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

        # CloudWatch Alarm の場合、Message は JSON またはテキスト
        # JSON のときは整形して簡潔にする
        text = None
        try:
            m = json.loads(message)
            # CloudWatch Alarm JSON 形式の典型フィールド
            alarm_name = m.get("AlarmName") or m.get("AlarmName")
            new_state = m.get("NewStateValue")
            reason = m.get("NewStateReason")
            region = m.get("Region")
            account = m.get("AWSAccountId")
            link = m.get("AlarmUrl") or m.get("AlarmArn")
            text = (
                f"🔔 CloudWatch Alarm\n"
                f"アラーム: {alarm_name}\n"
                f"状態: {new_state}\n"
                f"理由: {reason}\n"
                f"リージョン: {region} / アカウント: {account}\n"
                f"{link or ''}"
            )
        except Exception:
            # JSON でない場合はそのままテキスト送信
            pass

        if not text:
            text = f"{subject or 'SNS Notification'}\n{message}"

        _post_slack(webhook, text)

    return {"ok": True, "count": len(records)}

