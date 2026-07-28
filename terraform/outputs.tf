output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.this.name
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace name."
  value       = azurerm_log_analytics_workspace.this.name
}

output "function_app_name" {
  description = "Function App name."
  value       = local.use_function_app ? azurerm_linux_function_app.ingest[0].name : null
}

output "logic_app_name" {
  description = "Logic App workflow name when ingestion_endpoint_type is logic_app."
  value       = local.use_logic_app ? azurerm_logic_app_workflow.ingest[0].name : null
}

output "ingestion_endpoint_type" {
  description = "HTTPS ingestion endpoint type created by Terraform."
  value       = var.ingestion_endpoint_type
}

output "function_url" {
  description = "Raw signed URL (may contain percent-encoded characters). Use hcp_sink_url instead when configuring the HCP Vault Dedicated Generic HTTP Sink."
  value       = local.function_url
  sensitive   = true
}

output "hcp_sink_url" {
  description = "Paste-ready URL for the HCP Vault Dedicated Generic HTTP Sink. For logic_app the %2F sequences in the sp= parameter are decoded to / so HCP does not double-encode the SAS signature and cause silent 401 errors."
  value       = local.use_logic_app ? replace(azurerm_logic_app_trigger_http_request.ingest[0].callback_url, "%2F", "/") : local.function_url
  sensitive   = true
}

output "hcp_bearer_token" {
  description = "Bearer token to configure in HCP Vault Dedicated Generic HTTP Sink. Sensitive; protect Terraform state."
  value       = local.hcp_bearer_token
  sensitive   = true
}

output "dce_uri" {
  description = "Azure Monitor Logs Ingestion endpoint URI."
  value       = local.dce_uri
}

output "dcr_immutable_id" {
  description = "DCR immutable ID used by the Logs Ingestion API."
  value       = local.dcr_immutable_id
}

output "custom_table_name" {
  description = "Custom Log Analytics table name."
  value       = var.table_name
}
