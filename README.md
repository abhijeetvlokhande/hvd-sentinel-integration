# HCP Vault Dedicated to Microsoft Sentinel integration

This repository deploys the Azure side of an HCP Vault Dedicated audit log streaming pattern for Microsoft Sentinel.

The pattern is:

```text
HCP Vault Dedicated Generic HTTP Sink
  -> Azure Function App
  -> Azure Monitor Logs Ingestion API
  -> Data Collection Endpoint-backed Data Collection Rule
  -> Log Analytics custom table
  -> Microsoft Sentinel
```

## What this repo creates

- Azure resource group
- Log Analytics workspace
- Custom table `HCPVaultAudit_CL`
- Data Collection Endpoint (DCE)
- Data Collection Rule (DCR)
- Linux Python Function App
- System-assigned managed identity
- RBAC assignment for the Function App identity
- Optional Microsoft Sentinel onboarding
- Optional Microsoft Sentinel scheduled analytics rules

The HCP Vault Dedicated Generic HTTP Sink configuration remains a portal step. Terraform outputs the URL and bearer token to paste into HCP.

## Prerequisites

- Terraform 1.6 or later
- Azure CLI
- Azure Functions Core Tools v4
- An HCP Vault Dedicated cluster on Essentials or Standard tier
- Azure permissions to create the resources in this repo
- Azure permission to create role assignments, such as User Access Administrator or Owner

## Quick start

Sign in to Azure and select the subscription:

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID_OR_NAME>"
```

Copy the example variables file and edit it:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Set your `subscription_id`, `tenant_id`, `location`, `resource_prefix`, and `environment` in `terraform/terraform.tfvars`.

Deploy Azure infrastructure:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

Publish the Function App code:

```bash
./scripts/publish-function.sh
```

Run an Azure-side smoke test:

```bash
./scripts/smoke-test.sh
```

Get the values for HCP Vault Dedicated:

```bash
terraform -chdir=terraform output -raw function_url
terraform -chdir=terraform output -raw hcp_bearer_token
```

In HCP Portal, open your Vault Dedicated cluster and configure:

- Audit Logs -> Enable log streaming -> Generic HTTP Sink
- URL: Terraform `function_url` output
- Method: `POST`
- Auth strategy: `Bearer`
- Token: Terraform `hcp_bearer_token` output
- Encoding: `JSON`
- Compression: disabled for first validation

## Region selection

Set the `location` variable in `terraform/terraform.tfvars`:

```hcl
location = "eastus"
```

Use any Azure region that supports Log Analytics, Azure Functions, Data Collection Endpoints, and Microsoft Sentinel.

## Security notes

If Terraform generates the bearer token, the token is stored in Terraform state. For production, protect Terraform state and consider supplying `hcp_bearer_token` from a secret manager.

Do not screenshot or share Function App app settings, Terraform state, or unmasked bearer tokens.

## Validate ingestion

After configuring HCP log streaming, run:

```kql
HCPVaultAudit_CL
| where TimeGenerated > ago(24h)
| summarize Events = count() by path
| order by Events desc
| take 20
```

More validation and detection queries are in [`kql/starter-queries.kql`](kql/starter-queries.kql).

## Cleanup

Remove the HCP Generic HTTP Sink destination first, then destroy Azure resources:

```bash
terraform -chdir=terraform destroy
```
