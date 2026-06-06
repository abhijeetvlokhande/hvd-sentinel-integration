#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS_FILE="${TFVARS_FILE:-${REPO_ROOT}/terraform/terraform.tfvars}"

default_subscription_id=""
default_tenant_id=""

if command -v az >/dev/null 2>&1; then
  default_subscription_id="$(az account show --query id -o tsv 2>/dev/null || true)"
  default_tenant_id="$(az account show --query tenantId -o tsv 2>/dev/null || true)"
fi

prompt_value() {
  local label="$1"
  local default_value="${2:-}"
  local value=""

  while true; do
    if [[ -n "$default_value" ]]; then
      read -r -p "${label} [${default_value}]: " value
      value="${value:-$default_value}"
    else
      read -r -p "${label}: " value
    fi

    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi

    echo "A value is required."
  done
}

prompt_bool() {
  local label="$1"
  local default_value="$2"
  local prompt="[y/N]"
  local value=""

  if [[ "$default_value" == "true" ]]; then
    prompt="[Y/n]"
  fi

  while true; do
    read -r -p "${label} ${prompt}: " value
    value="$(printf '%s' "${value:-$default_value}" | tr '[:upper:]' '[:lower:]')"

    case "$value" in
      y|yes|true)
        printf 'true'
        return
        ;;
      n|no|false)
        printf 'false'
        return
        ;;
      *)
        echo "Answer yes or no."
        ;;
    esac
  done
}

subscription_id="$(prompt_value "Azure subscription ID" "$default_subscription_id")"
tenant_id="$(prompt_value "Azure tenant ID" "$default_tenant_id")"
location="$(prompt_value "Azure region" "eastus")"
resource_prefix="$(prompt_value "Resource prefix" "hvd-sentinel")"
environment="$(prompt_value "Environment suffix" "demo")"
retention_days="$(prompt_value "Log Analytics retention days" "30")"
sentinel_enabled="$(prompt_bool "Onboard the workspace to Microsoft Sentinel?" "true")"
create_sentinel_rules="false"

if [[ "$sentinel_enabled" == "true" ]]; then
  create_sentinel_rules="$(prompt_bool "Create starter Microsoft Sentinel analytics rules?" "false")"
fi

mkdir -p "$(dirname "$TFVARS_FILE")"

cat > "$TFVARS_FILE" <<EOF
subscription_id = "${subscription_id}"
tenant_id       = "${tenant_id}"

location        = "${location}"
resource_prefix = "${resource_prefix}"
environment     = "${environment}"

log_analytics_retention_days = ${retention_days}
sentinel_enabled             = ${sentinel_enabled}
create_sentinel_rules        = ${create_sentinel_rules}

# Optional. If null, Terraform generates a bearer token.
hcp_bearer_token = null
EOF

echo "Wrote ${TFVARS_FILE}."
echo "Starter Sentinel analytics rules: ${create_sentinel_rules}."