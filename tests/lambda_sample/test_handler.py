import json

from src.lambda_sample.handler import handler


class _Ctx:
    aws_request_id = "test-req-id"


def test_handler_ok():
    resp = handler(event={}, context=_Ctx())
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"]) if isinstance(resp.get("body"), str) else resp["body"]
    assert body.get("ok") is True

