## System Architecture (Mermaid)

```mermaid
flowchart LR
  subgraph Dev[Local Development]
    D[Developer]
    B[Docker Buildx\n--platform linux/arm64\n--provenance=false]
    D --> B
  end

  B --> ECR[(Amazon ECR\n<repo>:<tag>)]

  subgraph Deploy[AWS]
    L[Lambda Function\nPackage: Image\nPython 3.12 / arm64]
  end

  ECR -->|imageUri @ digest| L

  subgraph Runtime[Runtime & Monitoring]
    CWm[CloudWatch Metrics\nAWS/Lambda: Errors]
    CWa[CloudWatch Alarm\nErrors >= 1]
    SNS[(SNS Topic\nlambda-alerts)]
    NL[Notify Slack Lambda\nSNS Subscription]
    WH[Slack Incoming Webhook]
    SC[(Slack Channel)]
  end

  L -.invocation.-> CWm --> CWa -->|alarm_actions| SNS --> NL --> WH --> SC
```

### Notes
- Image update: Terraform resolves ECR tag to digest (`repo@sha256:<digest>`) and updates Lambda.
- Alarm path: CloudWatch Alarm sends directly to SNS (no EventBridge / Chatbot).
- Notify Slack Lambda formats messages using Slack Block Kit and posts via Incoming Webhook.

