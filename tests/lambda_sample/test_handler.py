import json
import sys

sys.path.append(".")
from src.lambda_sample.handler import handler


class _Ctx:
    # Lambda の実行コンテキストで参照される属性を用意
    function_name = "lambda-template"
    memory_limit_in_mb = 128
    invoked_function_arn = "arn:aws:lambda:ap-northeast-1:123456789012:function:lambda-template"
    aws_request_id = "test-request-id"

def test_handler_ok():
    resp = handler(event={}, context=_Ctx())
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"]) if isinstance(resp.get("body"), str) else resp["body"]
    assert body.get("ok") is True

