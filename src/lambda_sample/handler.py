import json
import os
import time

from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.metrics import MetricUnit

logger = Logger(service="lambda_sample")
metrics = Metrics(namespace=os.getenv("METRICS_NAMESPACE", "LambdaSample"))
tracer = Tracer(service="lambda_sample")


@metrics.log_metrics(capture_cold_start_metric=True)
@tracer.capture_lambda_handler
@logger.inject_lambda_context(log_event=True)
def handler(event, context):
    if os.getenv("FORCE_TIMEOUT") == "1":
        logger.warning("FORCE_TIMEOUT=1 のため意図的にタイムアウトを発生させます")
        while True:
            time.sleep(1)

    if os.getenv("FORCE_ERROR") == "1":
        logger.error("FORCE_ERROR=1 のため意図的にエラーを発生させます")
        raise RuntimeError("FORCED_ERROR: 意図的にエラーを発生")

    if os.getenv("FORCE_MEMORY_LEAK") == "1":
        logger.error("FORCE_MEMORY_LEAK=1 のため意図的にメモリエラーを発生させます")
        leak = []
        for _ in range(20):  # 約500MBx20を確保してメモリ逼迫を再現
            leak.append(bytearray(500 * 1024 * 1024))
        del leak
        raise MemoryError("FORCED_MEMORY_LEAK: 意図的にメモリエラーを発生")

    request_id = getattr(context, "aws_request_id", None)
    if request_id:
        tracer.put_metadata(key="aws_request_id", value=request_id)

    metrics.add_metric(name="SuccessfulInvocations", unit=MetricUnit.Count, value=1)

    response = {"statusCode": 200, "body": json.dumps({"ok": True})}
    logger.info("正常レスポンスを返却します", extra={"response": response})
    return response
