# Architecture

The integration streams HCP Vault Dedicated audit logs into Azure without running a log forwarder next to Vault. The base path lands records in a Log Analytics custom table. Microsoft Sentinel onboarding and analytics rules are optional.

```text
HCP Vault Dedicated Generic HTTP Sink
  -> Azure Function App
  -> Azure Monitor Logs Ingestion API
  -> Data Collection Endpoint-backed Data Collection Rule
  -> HCPVaultAudit_CL in Log Analytics
  -> optional Microsoft Sentinel onboarding and analytics rules
```

The Function App validates a shared bearer token, normalizes Vault audit events, and writes to Azure Monitor using its managed identity. The Data Collection Rule maps those records into the custom Log Analytics table. If Sentinel is enabled, the same table becomes available for hunting, analytics rules, incidents, and workbooks.
