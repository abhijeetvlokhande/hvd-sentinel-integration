#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/terraform}"
FUNC_DIR="${FUNC_DIR:-${REPO_ROOT}/function_app}"

INGESTION_ENDPOINT_TYPE="$(terraform -chdir="$TF_DIR" output -raw ingestion_endpoint_type 2>/dev/null || echo "function_app")"

if [[ "$INGESTION_ENDPOINT_TYPE" != "function_app" ]]; then
  echo "Skipping Function App publish because ingestion_endpoint_type is ${INGESTION_ENDPOINT_TYPE}."
  exit 0
fi

FUNCAPP="$(terraform -chdir="$TF_DIR" output -raw function_app_name)"

pushd "$FUNC_DIR" >/dev/null
if ! func azure functionapp publish "$FUNCAPP" --python; then
  func azure functionapp publish "$FUNCAPP" --python --build remote
fi
popd >/dev/null

echo "Published ${FUNCAPP}."
