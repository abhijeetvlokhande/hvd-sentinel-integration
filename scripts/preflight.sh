#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <subscription-id-or-name>" >&2
  exit 1
fi

SUBSCRIPTION="$1"
INCLUDE_SENTINEL="${INCLUDE_SENTINEL:-false}"

if [[ "${2:-}" == "--sentinel" ]]; then
  INCLUDE_SENTINEL="true"
fi

az account set --subscription "$SUBSCRIPTION"

providers=(Microsoft.Web Microsoft.OperationalInsights Microsoft.Insights Microsoft.Monitor Microsoft.Storage)

if [[ "$INCLUDE_SENTINEL" == "true" ]]; then
  providers+=(Microsoft.SecurityInsights)
fi

for ns in "${providers[@]}"; do
  echo "Registering ${ns}"
  az provider register --namespace "$ns" --wait >/dev/null
done

echo "Preflight complete."
