#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/terraform}"

FUNC_URL="$(terraform -chdir="$TF_DIR" output -raw function_url)"
HCP_TOKEN="$(terraform -chdir="$TF_DIR" output -raw hcp_bearer_token)"
INGESTION_ENDPOINT_TYPE="$(terraform -chdir="$TF_DIR" output -raw ingestion_endpoint_type 2>/dev/null || echo "function_app")"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
REQ_ID="smoke-$(date +%s)"

payload=$(cat <<JSON
{
  "time": "${NOW_UTC}",
  "type": "request",
  "auth": { "display_name": "smoke-test-user" },
  "request": {
    "id": "${REQ_ID}",
    "operation": "read",
    "path": "kv/data/demo",
    "remote_address": "10.10.10.10"
  },
  "error": ""
}
JSON
)

response_file="$(mktemp)"

curl_headers=(-H "Content-Type: application/json")

if [[ "$INGESTION_ENDPOINT_TYPE" == "function_app" ]]; then
  curl_headers+=(-H "Authorization: Bearer ${HCP_TOKEN}")
fi

status=$(curl -sS -o "$response_file" -w "%{http_code}" \
  -X POST "$FUNC_URL" \
  "${curl_headers[@]}" \
  --data "$payload")

echo "HTTP ${status}"
cat "$response_file"
echo
rm -f "$response_file"

if [[ "$status" != "200" && "$status" != "202" ]]; then
  exit 1
fi

echo "Smoke request ID: ${REQ_ID}"
