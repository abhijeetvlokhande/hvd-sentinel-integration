#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <subscription-id-or-name>" >&2
  exit 1
fi

SUBSCRIPTION="$1"

az account set --subscription "$SUBSCRIPTION"

for ns in Microsoft.Web Microsoft.OperationalInsights Microsoft.Insights Microsoft.Monitor Microsoft.Storage Microsoft.SecurityInsights; do
  echo "Registering ${ns}"
  az provider register --namespace "$ns" --wait >/dev/null
done

echo "Preflight complete."
