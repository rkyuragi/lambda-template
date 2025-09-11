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

    def fake_post(url, text):
        called["url"] = url
        called["text"] = text

    monkeypatch.setenv("SLACK_WEBHOOK_URL", "https://example.com/webhook")
    monkeypatch.setattr(h, "_post_slack", fake_post)

    resp = h.handler(payload, None)
    assert resp["ok"] is True
    assert called["url"].startswith("https://example.com/")
    assert "Hello" in called["text"]

