#!/usr/bin/env bash
# run-full-test.sh
# One-shot script: preflight → terraform init/apply → publish → smoke test
# Usage: bash run-full-test.sh

set -euo pipefail

SUBSCRIPTION="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo " HVD Sentinel Integration — Full Test Run"
echo " $(date -u)"
echo "================================================"

# ── 1. Azure login check ──────────────────────────────────────────────────────
echo ""
echo "── Step 1: Azure account ──"
az account set --subscription "$SUBSCRIPTION"
az account show --query "{subscription:name, id:id, user:user.name, tenant:tenantId}" -o table
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# ── 2. Preflight (register providers) ────────────────────────────────────────
echo ""
echo "── Step 2: Register resource providers ──"
"${REPO_ROOT}/scripts/preflight.sh" "$SUBSCRIPTION" --sentinel

# ── 3. Write terraform.tfvars ─────────────────────────────────────────────────
echo ""
echo "── Step 3: Write terraform.tfvars ──"
cat > "${REPO_ROOT}/terraform/terraform.tfvars" <<EOF
subscription_id = "${SUBSCRIPTION}"
tenant_id       = "${TENANT_ID}"

location        = "eastus"
resource_prefix = "hvd-sentinel"
environment     = "blog"

ingestion_endpoint_type = "function_app"

log_analytics_retention_days = 30
sentinel_enabled             = true
create_sentinel_rules        = false

hcp_bearer_token = null
EOF
echo "terraform.tfvars written."
cat "${REPO_ROOT}/terraform/terraform.tfvars"

# ── 4. Terraform init ─────────────────────────────────────────────────────────
echo ""
echo "── Step 4: terraform init ──"
terraform -chdir="${REPO_ROOT}/terraform" init -upgrade

# ── 5. Terraform apply ───────────────────────────────────────────────────────
echo ""
echo "── Step 5: terraform apply ──"
terraform -chdir="${REPO_ROOT}/terraform" apply -auto-approve

# ── 6. Show outputs ──────────────────────────────────────────────────────────
echo ""
echo "── Step 6: Terraform outputs ──"
terraform -chdir="${REPO_ROOT}/terraform" output

# ── 7. Publish Function App ──────────────────────────────────────────────────
echo ""
echo "── Step 7: Publish Function App ──"
"${REPO_ROOT}/scripts/publish-function.sh"

# ── 8. Smoke test ────────────────────────────────────────────────────────────
echo ""
echo "── Step 8: Smoke test ──"
"${REPO_ROOT}/scripts/smoke-test.sh"

echo ""
echo "================================================"
echo " All steps complete."
echo " Run: terraform -chdir=terraform output -raw hcp_sink_url"
echo " Run: terraform -chdir=terraform output -raw hcp_bearer_token"
echo " Use these values to configure the HCP Vault Dedicated Generic HTTP Sink."
echo "================================================"
