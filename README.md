# HCP Vault Dedicated audit logs to Azure and Microsoft Sentinel

This repository deploys the Azure side of an HCP Vault Dedicated audit log streaming pattern. The required path lands Vault audit logs in Azure Log Analytics. Microsoft Sentinel onboarding and starter analytics rules are optional add-ons.

This repo is the companion implementation for the blog post **"Streaming HCP Vault Dedicated audit logs to Microsoft Sentinel"**.

The pattern is:

```text
HCP Vault Dedicated Generic HTTP Sink
  -> Azure Function App
  -> Azure Monitor Logs Ingestion API
  -> Data Collection Endpoint-backed Data Collection Rule
  -> Log Analytics custom table
  -> optional Microsoft Sentinel onboarding and analytics rules
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

Optional add-ons:

- Microsoft Sentinel onboarding for the Log Analytics workspace
- Microsoft Sentinel scheduled analytics rules

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

Create a local Terraform variables file. The helper prompts for your Azure region and asks whether to create the optional Sentinel resources:

```bash
./scripts/configure-terraform.sh
```

For the smallest working pipeline that proves logs land in Azure, answer `no` when asked to create starter Microsoft Sentinel analytics rules. The generated `terraform/terraform.tfvars` file is local-only and ignored by Git.

The default ingestion endpoint is `function_app`, which deploys an Azure Function. If your Azure subscription has zero App Service worker quota, choose `logic_app` when prompted; it creates an Azure Logic Apps Consumption workflow instead and still writes records to the same Log Analytics table through the Data Collection Rule.

You can also copy and edit the example file manually:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Deploy Azure infrastructure:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

Publish the Function App code:

```bash
./scripts/publish-function.sh
```

If you selected `logic_app`, this script exits without publishing because the workflow is fully created by Terraform.

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

If `ingestion_endpoint_type = "logic_app"`, the `function_url` output is already a signed callback URL. Use that URL, set the method to `POST`, and do not add a Bearer authorization header.

## Region selection

The configure helper prompts for the Azure region. If you edit `terraform/terraform.tfvars` manually, set the `location` variable:

```hcl
location = "eastus"
```

Use any Azure region that supports Log Analytics, Azure Functions, and Data Collection Endpoints. If you enable Sentinel onboarding, use a region where Microsoft Sentinel is available.

## Optional Sentinel resources

The Azure ingestion pipeline does not require Sentinel analytics rules. Set these values in `terraform/terraform.tfvars` or answer the prompts in `./scripts/configure-terraform.sh`:

```hcl
sentinel_enabled      = true
create_sentinel_rules = false
```

Use `sentinel_enabled = true` when you want the workspace onboarded to Microsoft Sentinel. Use `create_sentinel_rules = true` only when you want Terraform to create the starter scheduled analytics rules included in this repo.

## App Service quota fallback

Some fresh Azure subscriptions start with no App Service worker quota. If Terraform fails while creating `azurerm_service_plan` with a message such as `Current Limit (Total VMs): 0`, switch the local variables file to the Logic App endpoint:

```hcl
ingestion_endpoint_type = "logic_app"
```

Then run `terraform -chdir=terraform apply` again. The `function_url` output will be a signed Logic App callback URL that you can paste into the HCP Vault Dedicated Generic HTTP Sink URL field.

Because the Logic App callback URL already contains its access signature, configure the HCP sink without an additional Bearer token when using this fallback.

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
