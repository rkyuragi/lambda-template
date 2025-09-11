import json
from src.notify_slack import handler as h


def test_format_text_from_plain_message(monkeypatch):
    payload = {
        "Records": [
            {
                "Sns": {
                    "Subject": "Test",
                    "Message": "Hello",
                }
            }
        ]
    }

    called = {}

    def fake_post(url, payload):
        called["url"] = url
        called["payload"] = payload

    monkeypatch.setenv("SLACK_WEBHOOK_URL", "https://example.com/webhook")
    monkeypatch.setattr(h, "_post_slack", fake_post)

    resp = h.handler(payload, None)
    assert resp["ok"] is True
    assert called["url"].startswith("https://example.com/")
    assert "text" in called["payload"]
    assert "Hello" in called["payload"]["text"]


def test_blocks_from_alarm_json(monkeypatch):
    alarm_msg = {
        "AlarmName": "lambda-sample-image-Errors",
        "NewStateValue": "ALARM",
        "NewStateReason": "Threshold Crossed",
        "Region": "ap-northeast-1",
        "AWSAccountId": "123456789012",
        "StateChangeTime": "2025-09-10T00:00:00Z",
    }
    payload = {"Records": [{"Sns": {"Message": json.dumps(alarm_msg)}}]}

    captured = {}

    def fake_post(url, payload):
        captured["payload"] = payload

    monkeypatch.setenv("SLACK_WEBHOOK_URL", "https://example.com/webhook")
    monkeypatch.setattr(h, "_post_slack", fake_post)

    resp = h.handler(payload, None)
    assert resp["ok"] is True
    p = captured["payload"]
    assert "blocks" in p and isinstance(p["blocks"], list)
    # ヘッダー or ボタン等が含まれているはず
    assert any(b.get("type") == "header" for b in p["blocks"])
