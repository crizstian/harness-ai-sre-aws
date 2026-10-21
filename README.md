# Harness AI SRE — AWS Demo Lab

End-to-end incident management demo: multi-source alert correlation powered by Harness AI SRE.

A deliberate Lambda failure triggers alerts from two independent monitoring sources (CloudWatch and Dash0). AI SRE correlates them with a recent CD deployment to surface a single, contextualized incident.

## Architecture

```
                          ┌──────────────┐
                          │  Harness CD  │
                          │  Pipeline    │
                          │ (CI+CD)      │
                          └──────┬───────┘
                                 │ deploy
                                 ▼
┌─────────┐  invoke   ┌──────────────────┐
│ demo.sh │ ────────► │  AWS Lambda      │
│ (fail)  │           │  harness-ai-sre- │
└─────────┘           │  lab-demo        │
                      └───────┬──┬───────┘
                 traces (OTel)│  │ metrics
                              │  │
                    ┌─────────┘  └──────────┐
                    ▼                        ▼
             ┌────────────┐         ┌──────────────┐
             │   Dash0    │         │  CloudWatch  │
             │ Check Rule │         │    Alarm     │
             └─────┬──────┘         └──────┬───────┘
                   │ webhook               │ SNS
                   │                       ▼
                   │              ┌──────────────────┐
                   │              │ Lambda Forwarder  │
                   │              │ (SNS → webhook)   │
                   │              └────────┬─────────┘
                   │                       │ webhook
                   ▼                       ▼
             ┌─────────────────────────────────┐
             │        Harness AI SRE           │
             │  ┌───────────────────────────┐  │
             │  │    Monitored Service      │  │
             │  │  (Change + Health Sources) │  │
             │  └───────────┬───────────────┘  │
             │              │                  │
             │  ┌───────────▼───────────────┐  │
             │  │       Alert Rule          │  │
             │  │  deploy + dual alerts     │  │
             │  │  = correlated incident    │  │
             │  └───────────────────────────┘  │
             └─────────────────────────────────┘
```

## Components

### AWS

| Component | Purpose |
|-----------|---------|
| **Lambda** (`harness-ai-sre-lab-demo`) | Demo function — succeeds by default, fails with `{"fail": true}` |
| **CloudWatch Alarm** | Detects Lambda errors (>= 1 error in 60s window) |
| **SNS Topic** (`harness-ai-sre-lab-alerts`) | Receives alarm notifications |
| **Lambda Forwarder** | Relays SNS payloads to Harness webhook with `Content-Type: application/json` |
| **S3 Bucket** (`harness-ai-sre-lab-artifacts`) | Stores Lambda code ZIP for CD pipeline |
| **IAM Roles** | Execution permissions for Lambda, Forwarder, and CloudWatch Logs |

### Dash0

| Component | Purpose |
|-----------|---------|
| **Lambda Extension Layer v26** | OTel instrumentation — sends traces to Dash0 |
| **Check Rule** | PromQL on `dash0.spans` — detects ERROR invocations in 5 min window |
| **Notification Channel** | Webhook to Harness AI SRE (condition: `max_status=critical`) |

Check Rule PromQL:
```promql
sum by (service_name, service_namespace) (
  increase({
    otel_metric_name="dash0.spans",
    otel_span_kind="SERVER",
    otel_span_status_code="ERROR",
    service_name="harness-ai-sre-lab-demo"
  }[5m])
) > $__threshold
```

### Harness

| Component | Purpose |
|-----------|---------|
| **Pipeline CI+CD** | CI packages `lambda_function.py` → ZIP → S3; CD deploys Lambda |
| **Service + Environment** | CD entities identifying the Lambda and its deployment target |
| **Monitored Service** | Links Service + Environment; auto-captures CD deploys as change events |
| **Webhook Integration (CloudWatch)** | Receives Forwarder payloads, parses alarm fields |
| **Webhook Integration (Dash0)** | Receives Dash0 payloads, parses `parsed_body.data.issue.*` |
| **Alert Rule** | Maps incoming webhook alerts to the Monitored Service → creates incidents |
| **IACM Workspace** (`harnessaisreaws`) | Manages all AWS infrastructure via Terraform |

### Terraform (IaC)

All AWS resources declared in `main.tf`, managed by Harness IACM:

- Lambda (demo + forwarder)
- CloudWatch Log Groups, Alarm
- SNS Topic + Policy + Subscription
- S3 Bucket (versioned, private)
- IAM Roles + Policies

## File Structure

```
harness-ai-sre-aws/
├── main.tf                        # All AWS infrastructure
├── variables.tf                   # Input variables (incl. Dash0 config)
├── outputs.tf                     # Exported values
├── versions.tf                    # Provider versions
├── terraform.tfvars               # Secrets (gitignored)
├── lambda_function.py             # Demo Lambda source (packaged by CI)
├── harness-cd/
│   └── function_definition.json   # Lambda config for CD deploy
├── demo.sh                        # Repeatable demo runner
├── .gitignore                     # Excludes tfstate, zips, secrets
└── README.md                      # This file
```

## Demo Script

`demo.sh` automates the repeatable demo cycle.

### Commands

```bash
./demo.sh reset    # Send successful invocations to clear alarms
./demo.sh status   # Check CloudWatch alarm state
./demo.sh fail     # Send 30 failures to trigger alerts
./demo.sh run      # Full cycle: reset → wait for OK → fail
```

### Environment Variables

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-west-2"
```

Optional: `DEMO_FAIL_COUNT=30` (default).

### Repeatable Demo Flow

```
1. ./demo.sh reset          # Clear alarms (5+ min before demo)
2. ./demo.sh status          # Confirm CloudWatch=OK, Dash0=OK
3. Run Harness CD pipeline   # Creates change event in AI SRE
4. ./demo.sh fail            # 30 failures → triggers both alert sources
5. Show AI SRE               # Correlated incident: deploy + dual alerts
```

### Why Reset is Required

Both CloudWatch and Dash0 only notify on **state transitions** (OK → ALARM/CRITICAL), not on re-firings. Without resetting to OK first, no webhook is sent, and AI SRE receives nothing.

## Alert Timing

| Source | Detection Window | Webhook Delay |
|--------|-----------------|---------------|
| CloudWatch | 60s period, 1 evaluation | ~1-2 min after failures |
| Dash0 | 5 min window, 1 min interval, 5 min keepFiring | ~5 min after failures |

## Key Configuration Notes

- **Dash0 token**: `function_definition.json` uses `<+secrets.getValue("dash0_auth_token")>` so the CD pipeline injects it at runtime — never stored in Git.
- **Dash0 notifications**: require condition `dash0.failed_check.max_status=critical` to fire on check rule failures.
- **Monitored Service**: must use the **same** Service + Environment as the CD pipeline for AI SRE to correlate deploys with alerts.
- **Lambda Forwarder**: necessary because SNS sends `text/plain` but Harness webhook requires `application/json`.
