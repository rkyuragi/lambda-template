# AWS 提供の Python 3.12 ベースイメージ（AL2023 / RIC 同梱）
FROM public.ecr.aws/lambda/python:3.12

# 依存インストール
COPY src/lambda_sample/requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
RUN pip install -r ${LAMBDA_TASK_ROOT}/requirements.txt

# コード配置（パッケージとして配置し、モジュール `lambda_sample.handler` を参照）
COPY src/lambda_sample/ ${LAMBDA_TASK_ROOT}/

# ハンドラ指定
CMD ["handler.handler"]
