# Harness AI SRE — AWS Demo Lab

End-to-end incident management demo: multi-source alert correlation powered by Harness AI SRE.

A deliberate Lambda failure triggers alerts from two independent monitoring sources (CloudWatch and Dash0). AI SRE correlates them with a recent CD deployment to surface a single, contextualized incident.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        HARNESS AI SRE — AWS DEMO LAB                            │
└─────────────────────────────────────────────────────────────────────────────────┘

  ┌──────────┐         ┌──────────────────────────────────────────┐
  │ Harness  │         │                 AWS                      │
  │ CD       │         │                                          │
  │ Pipeline │────────►│  ┌──────────────────────────────────┐    │
  │ (CI+CD)  │ deploy  │  │     Lambda                       │    │
  └──────────┘         │  │     harness-ai-sre-lab-demo      │    │
       │               │  │     (Dash0 Extension Layer)      │    │
       │               │  └──────┬─────────────────┬─────────┘    │
       │               │         │                 │              │
       │               │    metrics            traces (OTel)      │
       │               │         │                 │              │
       │               │         ▼                 │              │
       │               │  ┌──────────────┐         │              │
       │               │  │ CloudWatch   │         │              │
       │               │  │ Alarm        │         │              │
       │               │  │ (≥1 err/60s) │         │              │
       │               │  └──────┬───────┘         │              │
       │               │         │ OK→ALARM         │              │
       │               │         ▼                 │              │
       │               │  ┌──────────────┐         │              │
       │               │  │ SNS Topic    │         │              │
       │               │  └──────┬───────┘         │              │
       │               │         ▼                 │              │
       │               │  ┌──────────────┐         │              │
       │               │  │ Lambda       │         │              │
       │               │  │ Forwarder    │         │              │
       │               │  │ (SNS→JSON)   │         │              │
       │               │  └──────┬───────┘         │              │
       │               └─────────┼─────────────────┼──────────────┘
       │                         │                 │
       │                         │ webhook         │
       │                         │ (JSON)          │
       │                         │                 │
       │                         │          ┌──────┼──────────────────┐
       │                         │          │      ▼       Dash0     │
       │                         │          │ ┌──────────────┐       │
       │                         │          │ │ Check Rule   │       │
       │                         │          │ │ PromQL on    │       │
       │                         │          │ │ dash0.spans  │       │
       │                         │          │ └──────┬───────┘       │
       │                         │          │        │ OK→CRITICAL   │
       │                         │          │        │ webhook       │
       │                         │          └────────┼───────────────┘
       │                         │                   │
       │  deploy                 │                   │
       │  event                  ▼                   ▼
  ┌────┼─────────────────────────────────────────────────────────────┐
  │    │                   Harness AI SRE                           │
  │    │                                                            │
  │    ▼                                                            │
  │ ┌───────────────────────────────────────────────────────┐       │
  │ │              Monitored Service                        │       │
  │ │         (Service + Environment)                       │       │
  │ │                                                       │       │
  │ │  ┌─────────────┐    ┌──────────────┐                  │       │
  │ │  │Change Source │    │ Alert Rule   │◄── webhooks ─────┤       │
  │ │  │ (CD deploy) │    │ (dual alerts)│                  │       │
  │ │  └──────┬──────┘    └──────┬───────┘                  │       │
  │ │         │                  │                          │       │
  │ │         └──────┬───────────┘                          │       │
  │ │                │ correlation                          │       │
  │ │                ▼                                      │       │
  │ │  ┌─────────────────────────────────────┐              │       │
  │ │  │          INCIDENT                   │              │       │
  │ │  │  deploy v2.0.1 + CloudWatch alarm   │              │       │
  │ │  │  + Dash0 check rule = correlated    │              │       │
  │ │  └──────────────┬──────────────────────┘              │       │
  │ │                 │                                     │       │
  │ └─────────────────┼─────────────────────────────────────┘       │
  │                   │                                             │
  │                   ▼                                             │
  │         ┌───────────────────┐                                   │
  │         │  Runbook Trigger  │                                   │
  │         │ (Activity Created)│                                   │
  │         └────────┬──────────┘                                   │
  │                  │ auto                                         │
  │                  ▼                                              │
  │         ┌───────────────────┐                                   │
  │         │    RUNBOOK        │                                   │
  │         │  (auto-execute)   │                                   │
  │         └───────────────────┘                                   │
  └─────────────────────────────────────────────────────────────────┘


  ┌─────────┐   invoke ×30
  │ demo.sh │─── {"fail": true} ──────────────────────► Lambda
  │  fail   │
  └─────────┘
```

## Components

### AWS

- **Lambda** (`harness-ai-sre-lab-demo`) — función demo, falla con `{"fail": true}`
- **CloudWatch Alarm** — detecta ≥1 error en ventana de 60s, notifica vía SNS
- **SNS Topic** — recibe notificaciones del alarm
- **Lambda Forwarder** — convierte SNS (`text/plain`) → webhook JSON para Harness
- **S3 Bucket** (`harness-ai-sre-lab-artifacts`) — almacena ZIP del código Lambda para CD
- **IAM Roles** — permisos de ejecución para Lambda, Forwarder y CloudWatch Logs

### Dash0

- **Lambda Extension Layer v26** — instrumentación OTel, envía traces a Dash0
- **Check Rule** — PromQL sobre `dash0.spans`, detecta invocaciones ERROR en ventana de 5 min
- **Notification Channel** — webhook a Harness AI SRE (condición: `max_status=critical`)

### Harness CD

- **Pipeline CI+CD** — CI empaqueta `lambda_function.py` → ZIP → S3; CD despliega Lambda
- **Service** — entidad que identifica la Lambda; incluye Service Variable `dash0_token` (tipo Secret → `dash0_auth_token`)
- **Environment** — target de despliegue (AWS connector + región)
- **Function Definition** (`function_definition.json`) — configuración Lambda con `<+serviceVariables.dash0_token>` para inyectar token en deploy

### Harness AI SRE

- **Monitored Service** — vincula Service + Environment; captura deploys CD como change events automáticamente
- **Webhook Integration (CloudWatch)** — recibe payloads del Forwarder, parsea campos del alarm
- **Webhook Integration (Dash0)** — recibe payloads de Dash0, parsea `parsed_body.data.issue.*`
- **Alert Rule** — mapea alertas de ambos webhooks al Monitored Service → crea incidentes
- **Runbook** — procedimiento de respuesta automatizado
- **Runbook Trigger** — ejecuta el Runbook automáticamente al crearse un incidente (Activity Created)

### Harness IACM

- **Workspace** (`harnessaisreaws`) — gestiona toda la infraestructura AWS vía Terraform
- **Recursos Terraform** — Lambda (demo + forwarder), CloudWatch (logs + alarm), SNS, S3, IAM

## Where to Check — AWS Console (`us-west-2`)

- **Lambda → Functions → `harness-ai-sre-lab-demo`** — código, layers (Dash0 v26), env vars (`DASH0_TOKEN`, `DASH0_ENDPOINT`, `AWS_LAMBDA_EXEC_WRAPPER`)
- **Lambda → Functions → Forwarder** — código que reenvía SNS → webhook Harness
- **CloudWatch → Alarms → `harness-ai-sre-lab-lambda-errors`** — estado (OK/ALARM), métrica `Errors`, período 60s, threshold ≥1
- **CloudWatch → Log Groups → `/aws/lambda/harness-ai-sre-lab-demo`** — logs de invocaciones (éxito y error)
- **SNS → Topics → `harness-ai-sre-lab-alerts`** — subscripciones: Lambda Forwarder como endpoint
- **S3 → Buckets → `harness-ai-sre-lab-artifacts`** — ZIP del código Lambda, versionado habilitado
- **IAM → Roles** — roles de ejecución para Lambda demo, Forwarder y CloudWatch Logs

## Where to Check — Dash0

- **Alerting → Check Rules** — regla PromQL sobre `dash0.spans`, estado OK/CRITICAL
- **Alerting → Notification Channels** — webhook a Harness AI SRE, condición `max_status=critical`
- **Tracing** — traces OTel de la Lambda (`service_name=harness-ai-sre-lab-demo`)

## Where to Check — Harness

- **CD → Pipelines** — pipeline CI+CD; CI empaqueta ZIP → S3, CD despliega Lambda
- **CD → Services** — Service de la Lambda; revisar Service Variable `dash0_token` (tipo Secret → `dash0_auth_token`)
- **CD → Environments** — Environment con AWS connector y región `us-west-2`
- **CD → Connectors** — AWS connector con access key y secret key
- **IACM → Workspaces → `harnessaisreaws`** — workspace Terraform que gestiona toda la infra AWS
- **AI SRE → Monitored Services** — vincula Service + Environment; verificar que coincidan con los del pipeline CD
- **AI SRE → Alerts → Webhook Integrations** — dos webhooks: uno para CloudWatch (Forwarder) y otro para Dash0; revisar URLs y parsing
- **AI SRE → Alerts → Route Alerts (Alert Rule)** — regla que mapea alertas de ambos webhooks al Monitored Service → crea incidentes
- **AI SRE → Incidents** — incidentes creados con correlación: deploy + CloudWatch + Dash0
- **AI SRE → Runbooks** — runbook de respuesta; revisar pestaña Triggers → debe tener trigger "Activity Created"

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

- **Dash0 token**: `function_definition.json` uses `<+serviceVariables.dash0_token>` — a Service Variable of type Secret that references `dash0_auth_token`. This resolves at deploy time (unlike `secrets.getValue()` which doesn't resolve inside JSON manifests).
- **Dash0 notifications**: require condition `dash0.failed_check.max_status=critical` to fire on check rule failures.
- **Monitored Service**: must use the **same** Service + Environment as the CD pipeline for AI SRE to correlate deploys with alerts.
- **Lambda Forwarder**: necessary because SNS sends `text/plain` but Harness webhook requires `application/json`.
