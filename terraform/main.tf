locals {
  compact_prefix = replace(var.resource_prefix, "-", "")
  compact_env    = replace(var.environment, "-", "")

  name_base         = "${var.resource_prefix}-${var.environment}"
  resource_group    = "rg-${local.name_base}"
  workspace_name    = "law-${local.name_base}"
  dce_name          = "dce-${local.name_base}"
  dcr_name          = "dcr-${local.name_base}"
  function_app_name = "func-${local.name_base}-${random_string.suffix.result}"
  service_plan_name = "plan-${local.name_base}"
  app_insights_name = "appi-${local.name_base}"
  storage_name      = substr("${local.compact_prefix}${local.compact_env}${random_string.suffix.result}", 0, 24)
  logic_app_name    = "logic-${local.name_base}"

  hcp_bearer_token = coalesce(var.hcp_bearer_token, random_password.hcp_bearer_token.result)
  function_route   = "hcp-vault-ingest"

  use_function_app = var.ingestion_endpoint_type == "function_app"
  use_logic_app    = var.ingestion_endpoint_type == "logic_app"
  function_url     = local.use_function_app ? "https://${azurerm_linux_function_app.ingest[0].default_hostname}/api/${local.function_route}" : azurerm_logic_app_trigger_http_request.ingest[0].callback_url

  table_output_stream = "Custom-${var.table_name}"
  dce_uri             = jsondecode(azapi_resource.dce.output).properties.logsIngestion.endpoint
  dcr_immutable_id    = jsondecode(azapi_resource.dcr.output).properties.immutableId

  create_sentinel_rules = var.sentinel_enabled && var.create_sentinel_rules
  required_resource_providers = concat([
    "Microsoft.OperationalInsights",
    "Microsoft.Insights",
    "Microsoft.Monitor"
    ], local.use_function_app ? [
    "Microsoft.Web",
    "Microsoft.Storage"
    ] : [], local.use_logic_app ? [
    "Microsoft.Logic"
  ] : [], var.sentinel_enabled ? ["Microsoft.SecurityInsights"] : [])
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  numeric = true
  special = false
  upper   = false
}

resource "random_password" "hcp_bearer_token" {
  length  = 48
  special = false
}

resource "random_uuid" "auth_activity_spike_rule" {
  count = local.create_sentinel_rules ? 1 : 0
}

resource "random_uuid" "secret_enumeration_rule" {
  count = local.create_sentinel_rules ? 1 : 0
}

resource "random_uuid" "sensitive_path_rule" {
  count = local.create_sentinel_rules ? 1 : 0
}

resource "random_uuid" "off_hours_rule" {
  count = local.create_sentinel_rules ? 1 : 0
}

resource "null_resource" "register_providers" {
  count = var.register_resource_providers ? 1 : 0

  triggers = {
    subscription_id = var.subscription_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<EOT
for ns in ${join(" ", local.required_resource_providers)}; do
  az provider register --namespace "$ns" --subscription "${var.subscription_id}" --wait
done
EOT
  }
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group
  location = var.location

  depends_on = [null_resource.register_providers]
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
}

resource "azapi_resource" "sentinel_onboarding" {
  count = var.sentinel_enabled ? 1 : 0

  type      = "Microsoft.SecurityInsights/onboardingStates@2024-03-01"
  name      = "default"
  parent_id = azurerm_log_analytics_workspace.this.id
  body      = jsonencode({ properties = {} })
}

resource "azapi_resource" "custom_table" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = var.table_name
  parent_id = azurerm_log_analytics_workspace.this.id

  body = jsonencode({
    properties = {
      schema = {
        name = var.table_name
        columns = [
          { name = "TimeGenerated", type = "datetime" },
          { name = "eventTime", type = "string" },
          { name = "eventType", type = "string" },
          { name = "operation", type = "string" },
          { name = "path", type = "string" },
          { name = "authDisplayName", type = "string" },
          { name = "clientIp", type = "string" },
          { name = "requestId", type = "string" },
          { name = "errorMessage", type = "string" },
          { name = "rawData", type = "string" }
        ]
      }
    }
  })
}

resource "azapi_resource" "dce" {
  type      = "Microsoft.Insights/dataCollectionEndpoints@2023-03-11"
  name      = local.dce_name
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  body = jsonencode({
    properties = {
      networkAcls = {
        publicNetworkAccess = "Enabled"
      }
    }
  })

  response_export_values = ["properties.logsIngestion.endpoint"]
}

resource "azapi_resource" "dcr" {
  type      = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  name      = local.dcr_name
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  body = jsonencode({
    properties = {
      dataCollectionEndpointId = azapi_resource.dce.id
      streamDeclarations = {
        (var.stream_name) = {
          columns = [
            { name = "eventTime", type = "string" },
            { name = "eventType", type = "string" },
            { name = "operation", type = "string" },
            { name = "path", type = "string" },
            { name = "authDisplayName", type = "string" },
            { name = "clientIp", type = "string" },
            { name = "requestId", type = "string" },
            { name = "errorMessage", type = "string" },
            { name = "rawData", type = "string" }
          ]
        }
      }
      destinations = {
        logAnalytics = [
          {
            workspaceResourceId = azurerm_log_analytics_workspace.this.id
            name                = "dest-law"
          }
        ]
      }
      dataFlows = [
        {
          streams      = [var.stream_name]
          destinations = ["dest-law"]
          transformKql = "source | extend parsedEventTime=todatetime(eventTime) | project TimeGenerated=iff(isnull(parsedEventTime), now(), parsedEventTime), eventTime, eventType, operation, path, authDisplayName, clientIp, requestId, errorMessage, rawData"
          outputStream = local.table_output_stream
        }
      ]
    }
  })

  response_export_values = ["properties.immutableId"]

  depends_on = [azapi_resource.custom_table]
}

resource "azurerm_storage_account" "this" {
  count = local.use_function_app ? 1 : 0

  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

resource "azurerm_service_plan" "this" {
  count = local.use_function_app ? 1 : 0

  name                = local.service_plan_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_application_insights" "this" {
  count = local.use_function_app ? 1 : 0

  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
}

resource "azurerm_linux_function_app" "ingest" {
  count = local.use_function_app ? 1 : 0

  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  service_plan_id            = azurerm_service_plan.this[0].id
  storage_account_name       = azurerm_storage_account.this[0].name
  storage_account_access_key = azurerm_storage_account.this[0].primary_access_key

  functions_extension_version = "~4"
  https_only                  = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[0].connection_string
    DCE_URI                               = local.dce_uri
    DCR_ENDPOINT_URI                      = ""
    DCR_IMMUTABLE_ID                      = local.dcr_immutable_id
    FUNCTIONS_WORKER_RUNTIME              = "python"
    HCP_BEARER_TOKEN                      = local.hcp_bearer_token
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    STREAM_NAME                           = var.stream_name
  }
}

resource "azurerm_role_assignment" "function_monitoring_metrics_publisher" {
  count = local.use_function_app ? 1 : 0

  scope                = azapi_resource.dcr.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_linux_function_app.ingest[0].identity[0].principal_id
}

resource "azurerm_logic_app_workflow" "ingest" {
  count = local.use_logic_app ? 1 : 0

  name                = local.logic_app_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  workflow_schema  = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_logic_app_trigger_http_request" "ingest" {
  count = local.use_logic_app ? 1 : 0

  name         = local.function_route
  logic_app_id = azurerm_logic_app_workflow.ingest[0].id
  method       = "POST"

  schema = jsonencode({
    type  = "array"
    items = { type = "object", additionalProperties = true }
  })
}

resource "azurerm_role_assignment" "logic_app_monitoring_metrics_publisher" {
  count = local.use_logic_app ? 1 : 0

  scope                = azapi_resource.dcr.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_logic_app_workflow.ingest[0].identity[0].principal_id
}

resource "azurerm_logic_app_action_custom" "normalize_events" {
  count = local.use_logic_app ? 1 : 0

  name         = "normalize_events"
  logic_app_id = azurerm_logic_app_workflow.ingest[0].id

  body = jsonencode({
    type     = "Compose"
    inputs   = "@if(contains(string(triggerBody()), '[{'), triggerBody(), createArray(triggerBody()))"
    runAfter = {}
  })
}

resource "azurerm_logic_app_action_custom" "post_to_dcr" {
  count = local.use_logic_app ? 1 : 0

  name         = "post_to_dcr"
  logic_app_id = azurerm_logic_app_workflow.ingest[0].id

  body = jsonencode({
    type    = "Foreach"
    foreach = "@outputs('normalize_events')"
    actions = {
      post_to_dcr_http = {
        type = "Http"
        inputs = {
          method = "POST"
          uri    = "${local.dce_uri}/dataCollectionRules/${local.dcr_immutable_id}/streams/${var.stream_name}?api-version=2023-01-01"
          headers = {
            "Content-Type" = "application/json"
          }
          body = [
            {
              eventTime       = "@{coalesce(items('post_to_dcr')?['time'], utcNow())}"
              eventType       = "@{items('post_to_dcr')?['type']}"
              operation       = "@{items('post_to_dcr')?['request']?['operation']}"
              path            = "@{items('post_to_dcr')?['request']?['path']}"
              authDisplayName = "@{items('post_to_dcr')?['auth']?['display_name']}"
              clientIp        = "@{items('post_to_dcr')?['request']?['remote_address']}"
              requestId       = "@{items('post_to_dcr')?['request']?['id']}"
              errorMessage    = "@{items('post_to_dcr')?['error']}"
              rawData         = "@{string(items('post_to_dcr'))}"
            }
          ]
          authentication = {
            type     = "ManagedServiceIdentity"
            audience = "https://monitor.azure.com"
          }
        }
        runAfter = {}
      }
    }
    runAfter = {
      normalize_events = ["Succeeded"]
    }
  })

  depends_on = [
    azurerm_logic_app_action_custom.normalize_events,
    azurerm_role_assignment.logic_app_monitoring_metrics_publisher
  ]
}

resource "azapi_resource" "sentinel_rule_auth_activity_spike" {
  count = local.create_sentinel_rules ? 1 : 0

  type      = "Microsoft.SecurityInsights/alertRules@2024-03-01"
  name      = random_uuid.auth_activity_spike_rule[0].result
  parent_id = azurerm_log_analytics_workspace.this.id

  body = jsonencode({
    kind = "Scheduled"
    properties = {
      displayName           = "HCP Vault - Auth activity spike"
      description           = "Detects spikes in auth endpoint activity in HCP Vault audit events."
      enabled               = true
      query                 = local.kql_auth_activity_spike
      queryFrequency        = "PT30M"
      queryPeriod           = "PT1H"
      severity              = "Medium"
      triggerOperator       = "GreaterThan"
      triggerThreshold      = 0
      tactics               = ["CredentialAccess"]
      suppressionDuration   = "PT1H"
      suppressionEnabled    = true
      eventGroupingSettings = { aggregationKind = "SingleAlert" }
      incidentConfiguration = { createIncident = true }
      entityMappings = [
        {
          entityType = "Account"
          fieldMappings = [{ identifier = "FullName", columnName = "authDisplayName" }]
        },
        {
          entityType = "IP"
          fieldMappings = [{ identifier = "Address", columnName = "clientIp" }]
        }
      ]
    }
  })

  depends_on = [azapi_resource.sentinel_onboarding]
}

resource "azapi_resource" "sentinel_rule_secret_enumeration" {
  count = local.create_sentinel_rules ? 1 : 0

  type      = "Microsoft.SecurityInsights/alertRules@2024-03-01"
  name      = random_uuid.secret_enumeration_rule[0].result
  parent_id = azurerm_log_analytics_workspace.this.id

  body = jsonencode({
    kind = "Scheduled"
    properties = {
      displayName           = "HCP Vault - Secret enumeration"
      description           = "Detects one identity reading many distinct secret paths in a short window."
      enabled               = true
      query                 = local.kql_secret_enumeration
      queryFrequency        = "PT1H"
      queryPeriod           = "PT2H"
      severity              = "Medium"
      triggerOperator       = "GreaterThan"
      triggerThreshold      = 0
      tactics               = ["Discovery"]
      suppressionDuration   = "PT2H"
      suppressionEnabled    = true
      eventGroupingSettings = { aggregationKind = "SingleAlert" }
      incidentConfiguration = { createIncident = true }
      entityMappings = [
        {
          entityType = "Account"
          fieldMappings = [{ identifier = "FullName", columnName = "authDisplayName" }]
        }
      ]
    }
  })

  depends_on = [azapi_resource.sentinel_onboarding]
}

resource "azapi_resource" "sentinel_rule_sensitive_path" {
  count = local.create_sentinel_rules ? 1 : 0

  type      = "Microsoft.SecurityInsights/alertRules@2024-03-01"
  name      = random_uuid.sensitive_path_rule[0].result
  parent_id = azurerm_log_analytics_workspace.this.id

  body = jsonencode({
    kind = "Scheduled"
    properties = {
      displayName           = "HCP Vault - Sensitive path access"
      description           = "Detects access to sensitive Vault paths."
      enabled               = true
      query                 = local.kql_sensitive_path_access
      queryFrequency        = "PT1H"
      queryPeriod           = "PT2H"
      severity              = "High"
      triggerOperator       = "GreaterThan"
      triggerThreshold      = 0
      tactics               = ["CredentialAccess"]
      suppressionDuration   = "PT2H"
      suppressionEnabled    = true
      eventGroupingSettings = { aggregationKind = "SingleAlert" }
      incidentConfiguration = { createIncident = true }
      entityMappings = [
        {
          entityType = "Account"
          fieldMappings = [{ identifier = "FullName", columnName = "authDisplayName" }]
        },
        {
          entityType = "IP"
          fieldMappings = [{ identifier = "Address", columnName = "clientIp" }]
        }
      ]
    }
  })

  depends_on = [azapi_resource.sentinel_onboarding]
}

resource "azapi_resource" "sentinel_rule_off_hours" {
  count = local.create_sentinel_rules ? 1 : 0

  type      = "Microsoft.SecurityInsights/alertRules@2024-03-01"
  name      = random_uuid.off_hours_rule[0].result
  parent_id = azurerm_log_analytics_workspace.this.id

  body = jsonencode({
    kind = "Scheduled"
    properties = {
      displayName           = "HCP Vault - Off-hours secret access"
      description           = "Detects off-hours secret access activity."
      enabled               = true
      query                 = local.kql_off_hours_vault_activity
      queryFrequency        = "PT6H"
      queryPeriod           = "P1D"
      severity              = "Low"
      triggerOperator       = "GreaterThan"
      triggerThreshold      = 0
      tactics               = ["Collection"]
      suppressionDuration   = "P1D"
      suppressionEnabled    = true
      eventGroupingSettings = { aggregationKind = "SingleAlert" }
      incidentConfiguration = { createIncident = true }
      entityMappings = [
        {
          entityType = "Account"
          fieldMappings = [{ identifier = "FullName", columnName = "authDisplayName" }]
        },
        {
          entityType = "IP"
          fieldMappings = [{ identifier = "Address", columnName = "clientIp" }]
        }
      ]
    }
  })

  depends_on = [azapi_resource.sentinel_onboarding]
}
