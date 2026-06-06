# Architecture

The integration streams HCP Vault Dedicated audit logs into Microsoft Sentinel without running a log forwarder next to Vault.

```text
HCP Vault Dedicated Generic HTTP Sink
  -> Azure Function App
  -> Azure Monitor Logs Ingestion API
  -> Data Collection Endpoint-backed Data Collection Rule
  -> HCPVaultAudit_CL in Log Analytics
  -> Microsoft Sentinel
```

The Function App validates a shared bearer token, normalizes Vault audit events, and writes to Azure Monitor using its managed identity. The Data Collection Rule maps those records into the custom Log Analytics table that Sentinel uses for hunting, analytics rules, incidents, and workbooks.
