# Cognitive Services Deployment Inventory - Terraform Deployment

This folder contains Terraform configuration to deploy the Cognitive Services Deployment Inventory infrastructure as an alternative to the Bicep deployment.

## Components Deployed

| Resource | Description |
|----------|-------------|
| Resource Group | Container for all deployed resources |
| Custom Table | `CognitiveServicesInventory_CL` in Log Analytics |
| Data Collection Endpoint (DCE) | Ingestion endpoint for Logs Ingestion API |
| Data Collection Rule (DCR) | Schema definition and routing |
| Storage Account | Backing storage for Logic App |
| App Service Plan | Workflow Standard (WS1) hosting |
| Logic App (Standard) | Workflow host with managed identity |
| RBAC Assignments | Monitoring Metrics Publisher + Reader roles |

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) for authentication
- An existing Log Analytics workspace
- Azure subscription with appropriate permissions

## Usage

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Create Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
log_analytics_workspace_name                = "your-workspace-name"
log_analytics_workspace_resource_group_name = "your-workspace-rg"
resource_group_name                         = "rg-cognitive-services-inventory"
location                                    = "eastus"
```

### 3. Plan and Apply

```bash
# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "<subscription-id>"

# Preview changes
terraform plan

# Apply changes
terraform apply
```

### 4. Deploy Workflow and Configure Settings

After Terraform completes, use the deployment script to configure Logic App settings and deploy the workflow:

```powershell
.\Deploy-Workflow.ps1
```

The script will:
1. Read Terraform outputs automatically
2. Configure Logic App app settings (DCE endpoint, DCR immutable ID, stream name)
3. Deploy the workflow using Azure Functions Core Tools (with Kudu API fallback)

**Script options:**
- `-SkipSettings` - Skip Logic App settings configuration
- `-SkipWorkflow` - Skip workflow deployment
- `-TerraformDir` - Custom Terraform directory path (default: current directory)
- `-WorkflowSourceDir` - Custom path to workflow source files (default: parent directory)

#### Manual Alternative

If you prefer manual deployment:

```bash
# Get the output values
terraform output logic_app_settings

# Apply settings using Azure CLI
az functionapp config appsettings set \
  --name $(terraform output -raw logic_app_name) \
  --resource-group $(terraform output -raw resource_group_name) \
  --settings \
    DCE_LOGS_INGESTION_ENDPOINT="$(terraform output -json logic_app_settings | jq -r '.DCE_LOGS_INGESTION_ENDPOINT')" \
    DCR_IMMUTABLE_ID="$(terraform output -json logic_app_settings | jq -r '.DCR_IMMUTABLE_ID')" \
    DCR_STREAM_NAME="$(terraform output -json logic_app_settings | jq -r '.DCR_STREAM_NAME')"

# Deploy workflow from repository root
cd ..
func azure functionapp publish $(terraform -chdir=terraform output -raw logic_app_name) --javascript
```

## Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `log_analytics_workspace_name` | Yes | - | Existing Log Analytics workspace name |
| `log_analytics_workspace_resource_group_name` | Yes | - | Resource group of the workspace |
| `resource_group_name` | Yes | - | Target resource group for new resources |
| `location` | Yes | - | Azure region |
| `custom_table_name` | No | `CognitiveServicesInventory` | Table name (without _CL suffix) |
| `resource_prefix` | No | `cogai` | Prefix for resource names |
| `management_group_id` | No | `""` | Management group for cross-subscription queries |
| `retention_in_days` | No | `30` | Table retention (4-730 days) |
| `total_retention_in_days` | No | `365` | Total retention including archive (4-2556 days) |
| `tags` | No | `{}` | Additional tags for resources |

## Outputs

| Output | Description |
|--------|-------------|
| `resource_group_name` | Deployed resource group name |
| `dce_name` | Data Collection Endpoint name |
| `dce_logs_ingestion_endpoint` | DCE ingestion endpoint URL |
| `dcr_name` | Data Collection Rule name |
| `dcr_immutable_id` | DCR immutable ID for API calls |
| `dcr_stream_name` | Stream name for log ingestion |
| `storage_account_name` | Storage account name |
| `logic_app_name` | Logic App name |
| `logic_app_hostname` | Logic App hostname |
| `logic_app_principal_id` | Managed identity principal ID |
| `custom_table_name` | Custom table name with _CL suffix |
| `logic_app_settings` | Settings to configure on Logic App |

## Cross-Subscription Queries

To enable cross-subscription queries, set the `management_group_id` variable:

```hcl
management_group_id = "ContosoGroup"
```

This assigns the Reader role at the management group level instead of subscription level.

## Differences from Bicep Deployment

| Aspect | Bicep | Terraform |
|--------|-------|-----------|
| Scope | Subscription-scoped | Resource group + data sources |
| Custom Table | Native Bicep | AzAPI provider |
| DCR | Native Bicep | AzAPI provider (for full schema support) |
| State | Azure Resource Manager | Terraform state file |

## Clean Up

To destroy all resources:

```bash
terraform destroy
```

**Note:** The custom table in Log Analytics may take time to fully delete due to retention policies.
