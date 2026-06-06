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

The default endpoint is an Azure Function App. It validates a shared bearer token, normalizes Vault audit events, and writes to Azure Monitor using its managed identity. The Data Collection Rule maps those records into the custom Log Analytics table. If Sentinel is enabled, the same table becomes available for hunting, analytics rules, incidents, and workbooks.

For subscriptions that cannot create App Service workers, Terraform can create a Logic Apps Consumption workflow instead by setting `ingestion_endpoint_type = "logic_app"`. The Logic App uses a signed callback URL for ingress and its managed identity to post normalized single-event payloads to the same DCR stream.
