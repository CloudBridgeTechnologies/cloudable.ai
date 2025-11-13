# Cloudable.AI – Multi‑Tenant Responsible AI Platform

Cloudable.AI is a production‑ready reference implementation for running multi‑tenant AI agents on AWS. Terraform builds every component: network, security boundaries, Bedrock agents, knowledge bases, document ingestion, analytics, and observability. Lambdas add the runtime logic for conversation orchestration, document summarization, and knowledge-base synchronization, all protected by WAF, API keys, optional Cognito auth, and Langfuse telemetry.

---

## ⚙️ Key Capabilities

- **Multi‑Tenant Isolation** – Each tenant gets its own S3 buckets, Bedrock agent, knowledge base, and tagging.
- **Dual API Surface** – REST API Gateway (API key + WAF) for public access and HTTP API (optionally Cognito/Lambda authorizer) for internal administration flows.
- **Document → Knowledge Pipeline** – Uploads go to S3, trigger helper Lambdas, generate summaries, and ingest into Bedrock Knowledge Bases backed by OpenSearch Serverless.
- **Conversational AI** – Orchestrator Lambda brokers chat requests to tenant-specific Bedrock agents with Langfuse traces and response scoring.
- **Operational Guardrails** – IAM least privilege roles, KMS encryption, API throttling, DLQs, CloudWatch dashboards/alarms, and feature flags for S3 logging/tiering.
- **GitHub Actions Friendly** – Scripts and docs for CI/CD workflows plus local deployment helpers.

---

## 🗺️ Architecture Snapshot

```
    Clients / QA Tools
            │
     ┌──────┴────────────────────────────────────────────┐
     │ REST API Gateway (WAF + API Key + Usage Plan)     │
     │  • /chat  • /kb/query  • /kb/upload-url  • /kb/sync│
     └──────┬─────────────────────────────┬──────────────┘
            │                             │
        Orchestrator Lambda           S3 Helper Lambda
            │                             │
  Langfuse Traces + Bedrock Agents        ▼
            │                      Document Summarizer ──► Summary Bucket
            │                             │                       │
   DB Actions Lambda → Aurora             │               Summary Retriever
            │                             │                       │
     Knowledge Base Manager ◄────────────┘               REST /summary/{tenant}/{doc}
            │
     Bedrock Knowledge Base → OpenSearch Serverless (per tenant)
```

Supporting services: Cognito User Pool (optional authorizer), SNS + CloudWatch alarms, SQS DLQs, DynamoDB (tenant user index), KMS (RDS/S3), and VPC networking from terraform-aws-modules.

---

## 📁 Repository Layout

| Path | Description |
|------|-------------|
| `infras/envs/us-east-1/` | Terraform stack (API Gateway, Cognito, Lambdas, Bedrock, OpenSearch, S3, RDS, monitoring). |
| `infras/lambdas/` | Lambda sources (`orchestrator`, `document_summarizer`, `s3_helper`, `kb_manager`, `kb_sync_trigger`, `db_actions`, `summary_retriever`, shared telemetry utils). |
| `deploy_terraform.sh` | Guided wrapper for init/plan/apply/destroy with optional import mode. |
| `import_existing_resources.sh` | Bulk `terraform import` helper for resources already created in AWS. |
| `test_api_endpoints.sh`, `infras/envs/us-east-1/test/*` | Smoke/regression scripts (curl, Python, Postman collection). |
| `docs/*.md` | Deep dives (architecture, workflows, testing, deployment status). |

---

## 🚀 Deploying the Stack

### Prerequisites

- AWS CLI v2 configured (`aws sts get-caller-identity` should succeed).
- Terraform ≥ 1.5.
- Python 3.10+ (for Lambda dependencies/tests).
- Authenticated GitHub CLI (if you use GitHub Actions workflows).

### Quick Start (local)

```bash
# Configure or export AWS credentials first
./deploy_terraform.sh --env dev --region us-east-1
```

The script will:
1. Generate `infras/envs/us-east-1/terraform.tfvars` with default tenants.
2. `terraform init -migrate-state`
3. `terraform plan -out=tfplan`
4. Prompt, then `terraform apply` and emit API endpoint + key in `deployment_outputs.json`.

### Manual Terraform Commands

```bash
cd infras/envs/us-east-1
terraform init                    # or switch to S3 backend before init
terraform validate
terraform plan -var-file=tenants.tfvars -out=tfplan
terraform apply tfplan
```

Use `terraform destroy` (with the same tfvars) to tear everything down.

### Importing Existing AWS Resources

If parts of the stack already exist (e.g., WAF ACL, Bedrock agents, budgets, IAM policies), import them before `terraform apply`:

```bash
cd infras/envs/us-east-1
../../import_existing_resources.sh dev us-east-1   # runs targeted terraform import commands
```

### Feature Flags & Config

Add to `terraform.tfvars` as needed:

```hcl
enable_bucket_logging      = false   # true requires s3:GetBucketLogging rights
enable_intelligent_tiering = false
enable_bedrock_agents      = true
```

Tenants are defined as:

```hcl
tenants = {
  t001 = { name = "acme" }
  t002 = { name = "globex" }
}
```

---

## 🔐 Authentication & Secrets

- **REST APIs** – Require `x-api-key` header (Terraform outputs `secure_api_key`). WAF provides managed rule protection.
- **HTTP API routes** – Intended for internal services; wire up Cognito or Lambda authorizer (see `cognito-auth.tf` and `lambda-authorizer.tf`).
- **Cognito User Pool** – Optional user/groups per tenant.
- **SSM Parameters** – Langfuse host/public/secret keys live under `/cloudable/{env}/langfuse/*`. Agent alias ARNs are stored at `/cloudable/{env}/agent/{tenant_id}/alias_arn`.
- **KMS** – Separate keys for RDS and S3 encryption.

Never commit live secrets. If you rotate Langfuse or API keys, update SSM or Terraform variables via your secure CI/CD channel.

---

## 🧠 Runtime Workflows

### Chat / Reasoning Path
1. Client `POST /chat` (API key header).
2. API Gateway -> Orchestrator Lambda.
3. Orchestrator fetches tenant agent alias from SSM, records Langfuse trace, and calls Bedrock Agent.
4. Agent can invoke DB Actions Lambda (Aurora HTTP endpoint) or query the Knowledge Base.
5. Response quality metrics and traces are flushed to Langfuse; results returned to client.

### Document Ingestion & Summaries
1. Upload documents via presigned URL from `POST /kb/upload-url`.
2. S3 event triggers `s3_helper` and `document_summarizer` Lambdas.
3. Summaries land in per-tenant summary buckets and write an `index/{document_uuid}.json` pointer.
4. `kb_manager` Lambda starts Bedrock ingestion jobs using OpenSearch Serverless vector stores.
5. `GET /summary/{tenant}/{document_id}` looks up the index pointer, retrieves the summary JSON, and returns it via API Gateway.

---

## 📡 Monitoring & Ops

- **CloudWatch Dashboards** – AI safety and agent-core telemetry dashboards (see `monitoring-ai-safety.tf` and `agent-core-telemetry.tf`).
- **Logs** – Explicit log groups for every Lambda, API Gateway stage, and OpenSearch ingestion with retention policies.
- **Alarms** – Lambda error/throttle, DLQ depth, API Gateway 4xx/5xx, KB query latency.
- **Langfuse** – Session-level tracing, scoring, and latency metrics for Bedrock calls.
- **SNS Notifications** – Critical alerts flow to the emails configured in `alert_emails`.

---

## 🔌 Testing & Validation

| Test | Command |
|------|---------|
| Basic API smoke tests | `./test_api_endpoints.sh` (edit API ID & key first). |
| Knowledge Base API tests | `python infras/envs/us-east-1/test/kb/aws_api_kb_test.py` |
| Summary API validator | `python infras/envs/us-east-1/test_summary_api.py` |
| Full workflow harness | `bash infras/envs/us-east-1/test/comprehensive_local_test.sh` |
| Postman/Thunder tests | `infras/envs/us-east-1/test/postman_collection.json` |

After any change, always:

```bash
cd infras/envs/us-east-1
terraform fmt
terraform validate
terraform plan -var-file=tenants.tfvars
```

---

## 🛠️ Troubleshooting Cheatsheet

| Symptom | Fix |
|---------|-----|
| `CloudWatch Logs role ARN must be set…` | Ensure `aws_api_gateway_account` exists and stage depends_on it (see `cloudwatch-logging.tf`). |
| `ValidationException: policy json is invalid` | Confirm `opensearch-serverless.tf` access policy uses `jsonencode([ { … } ])` and correct resource names. |
| `Bedrock Knowledge Base was unable to assume the role` | Import existing KB role or verify trust policy uses `bedrock.amazonaws.com`. |
| `S3 GetBucketLogging AccessDenied` | Leave `enable_bucket_logging=false` or grant operator s3:GetBucketLogging.
| Lambda log group already exists | Import the log group (`terraform import aws_cloudwatch_log_group.<name> /aws/lambda/...`). |
| Missing agent alias during chat | Set `/cloudable/{env}/agent/{tenant}/alias_arn` via `deploy_agent_core.sh` or SSM put-parameter. |

---

## 🤝 Contributing & Support

1. Create a feature branch, run `terraform fmt` + `terraform validate`.
2. Update tests/docs as needed (especially `README.md`, API docs, and Postman scripts).
3. Commit with a clear message and open a PR. GitHub Actions workflows will run linting, plan, and tests.
4. For questions, open an issue referencing the module/function in question.

## 📄 License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for details.
