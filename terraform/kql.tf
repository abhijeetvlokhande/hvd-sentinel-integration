locals {
  kql_auth_activity_spike = <<KQL
let Window = 5m;
let MinAttempts = 10;
HCPVaultAudit_CL
| where TimeGenerated > ago(1h)
| where path startswith "auth/"
| summarize Attempts = count()
    by authDisplayName = coalesce(authDisplayName, "unknown"),
       path,
       bin(TimeGenerated, Window)
| where Attempts >= MinAttempts
| order by Attempts desc
KQL

  kql_secret_enumeration = <<KQL
let Window = 10m;
let MinDistinctPaths = 3;
HCPVaultAudit_CL
| where TimeGenerated > ago(2h)
| where operation == "read"
| where path startswith "kv/data/" or path startswith "secret/data/"
| summarize DistinctPaths = dcount(path),
            TotalReads = count()
    by authDisplayName = coalesce(authDisplayName, "unknown"),
       bin(TimeGenerated, Window)
| where DistinctPaths >= MinDistinctPaths
| order by DistinctPaths desc
KQL

  kql_sensitive_path_access = <<KQL
let SensitivePaths = dynamic([
  "auth/token/create",
  "kv/data/prod/db",
  "kv/data/prod/root",
  "auth/jwt/login",
  "auth/token/revoke",
  "sys/generate-root/attempt"
]);
HCPVaultAudit_CL
| where TimeGenerated > ago(2h)
| where operation in ("read", "create", "update", "patch", "delete", "list")
| where path in (SensitivePaths)
| project TimeGenerated, authDisplayName, operation, path, clientIp, requestId
| order by TimeGenerated desc
KQL

  kql_off_hours_vault_activity = <<KQL
let StartHourUtc = 6;
let EndHourUtc = 18;
HCPVaultAudit_CL
| where TimeGenerated > ago(24h)
| extend HourUTC = datetime_part("hour", TimeGenerated)
| where HourUTC < StartHourUtc or HourUTC >= EndHourUtc
| summarize Events = count()
    by authDisplayName = coalesce(authDisplayName, "unknown"),
       path,
       operation,
       HourUTC,
       bin(TimeGenerated, 1h)
| order by TimeGenerated desc
KQL
}
