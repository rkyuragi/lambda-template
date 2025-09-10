REGION ?= ap-northeast-1
ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
REPO ?= lambda-sample
TAG ?= v1
IMAGE_URI := $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com/$(REPO):$(TAG)

.PHONY: setup lint test build push print-image-uri local

setup:
	@echo "No setup steps defined. Install tools as needed."

lint:
	@echo "No linters configured. Skipping."

test:
	@if command -v pytest >/dev/null 2>&1; then \
		pytest -q; \
	else \
		echo "pytest not installed; skipping tests"; \
	fi

build:
	docker buildx build --platform linux/arm64 --provenance=false -t $(IMAGE_URI) .

push:
	aws ecr describe-repositories --repository-names $(REPO) --region $(REGION) >/dev/null 2>&1 || \
	  aws ecr create-repository --repository-name $(REPO) --image-scanning-configuration scanOnPush=true --region $(REGION)
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
	docker push $(IMAGE_URI)

print-image-uri:
	@echo $(IMAGE_URI)

local:
	@echo "Use 'docker run -p 9000:8080 <image>' and invoke locally if needed."

