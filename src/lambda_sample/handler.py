import json
import logging
import os
import time

log = logging.getLogger()
log.setLevel(logging.INFO)


def handler(event, context):
    if os.getenv("FORCE_TIMEOUT") == "1":
        # テスト用に明示的なタイムアウトを誘発
        while True:
            time.sleep(1)

    if os.getenv("FORCE_ERROR") == "1":
        raise RuntimeError("FORCED_ERROR: 意図的にエラーを発生")

    log.info({"event": event, "request_id": getattr(context, "aws_request_id", None)})
    return {"statusCode": 200, "body": json.dumps({"ok": True})}

