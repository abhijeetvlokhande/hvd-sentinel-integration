variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into."
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID for the target subscription."
}

variable "location" {
  type        = string
  description = "Azure region for all regional resources."
  default     = "eastus"
}

variable "resource_prefix" {
  type        = string
  description = "Short prefix used for Azure resource names. Use lowercase letters, numbers, and hyphens."
  default     = "hvd-sentinel"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.resource_prefix))
    error_message = "resource_prefix must be 3-24 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name or suffix used in resource names."
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "environment must be 2-16 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Retention in days for the Log Analytics workspace."
  default     = 30
}

variable "table_name" {
  type        = string
  description = "Custom Log Analytics table name. Must end in _CL."
  default     = "HCPVaultAudit_CL"
}

variable "stream_name" {
  type        = string
  description = "Custom stream name used by the DCR."
  default     = "Custom-HCPVaultAuditRaw"
}

variable "sentinel_enabled" {
  type        = bool
  description = "Onboard the Log Analytics workspace to Microsoft Sentinel. This is optional for the base Azure log ingestion pipeline."
  default     = true
}

variable "create_sentinel_rules" {
  type        = bool
  description = "Create starter Microsoft Sentinel scheduled analytics rules. Optional; the base pipeline lands logs without these rules."
  default     = false
}

variable "register_resource_providers" {
  type        = bool
  description = "Register required Azure resource providers before creating resources. Requires permission to register providers."
  default     = true
}

variable "hcp_bearer_token" {
  type        = string
  description = "Optional bearer token for HCP Vault Dedicated Generic HTTP Sink. If null, Terraform generates one."
  default     = null
  sensitive   = true
}
