# Cognitive Services Inventory - Azure Infrastructure

This repository contains Azure Bicep templates for deploying infrastructure to inventory all Azure Cognitive Services resources across subscriptions and log them to a custom Log Analytics table.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           HTTP Trigger Request                            │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                      Standard Logic App (Workflow)                        │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ 1. Receive HTTP request (trigger only, no parameters required)     │  │
│  │ 2. Query Azure Resource Graph for all Cognitive Services           │  │
│  │    (scope determined by managed identity's Reader permissions)     │  │
│  │ 3. Transform results for custom table schema                       │  │
│  │ 4. Send data to Data Collection Rule endpoint                      │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                          (System Managed Identity)                        │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              Data Collection Endpoint (DCE) & Rule (DCR)                  │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ • Logs Ingestion API endpoint                                      │  │
│  │ • Custom table schema definition                                   │  │
│  │ • Transform KQL (passthrough)                                      │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                      Log Analytics Workspace                              │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ CognitiveServicesInventory_CL (Custom Table)                       │  │
│  │ • TimeGenerated, ResourceId, ResourceName, ResourceType            │  │
│  │ • Kind, Location, SubscriptionId, SubscriptionName                 │  │
│  │ • ResourceGroup, Sku, ProvisioningState, PublicNetworkAccess       │  │
│  │ • Endpoint                                                         │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| **Data Collection Endpoint (DCE)** | Provides the ingestion endpoint for the Logs Ingestion API |
| **Data Collection Rule (DCR)** | Defines the custom table schema and routing to Log Analytics |
| **Custom Table** | `CognitiveServicesInventory_CL` table in Log Analytics |
| **Storage Account** | Required backing storage for Standard Logic App |
| **App Service Plan** | Workflow Standard SKU for Logic App hosting |
| **Standard Logic App** | Hosts the workflow with managed identity |
| **Logic App Workflow** | HTTP-triggered workflow that queries Resource Graph |
| **RBAC Assignments** | Monitoring Metrics Publisher + Reader roles |

## Prerequisites

- Azure subscription with Owner or Contributor + User Access Administrator permissions
- Existing Log Analytics workspace
- Azure CLI with Bicep support
- PowerShell 7+ (for deployment script)
- (Optional) Management Group access for cross-subscription queries

## Deployment

### Option 1: Automated Deployment (Recommended)

Use the PowerShell deployment script to deploy everything in one step:

```powershell
# Login to Azure
az login

# Set subscription
az account set --subscription "<your-subscription-id>"

# Deploy infrastructure and workflow
.\Deploy-CognitiveServicesInventory.ps1 `
    -LogAnalyticsWorkspaceName "your-workspace-name" `
    -LogAnalyticsWorkspaceResourceGroupName "your-workspace-rg" `
    -ResourceGroupName "rg-cognitive-services-inventory" `
    -Location "eastus"
```

**With cross-subscription support:**
```powershell
.\Deploy-CognitiveServicesInventory.ps1 `
    -LogAnalyticsWorkspaceName "your-workspace-name" `
    -LogAnalyticsWorkspaceResourceGroupName "your-workspace-rg" `
    -ResourceGroupName "rg-cognitive-services-inventory" `
    -Location "eastus" `
    -ManagementGroupId "your-management-group-id" `
    -Tags @{ Environment = "Production"; Project = "AI Inventory" }
```

**Script Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `LogAnalyticsWorkspaceName` | Yes | Name of existing Log Analytics workspace |
| `LogAnalyticsWorkspaceResourceGroupName` | Yes | Resource group of the workspace |
| `ResourceGroupName` | Yes | Target resource group for new resources |
| `Location` | Yes | Azure region (e.g., eastus) |
| `CustomTableName` | No | Table name without _CL suffix (default: CognitiveServicesInventory) |
| `ResourcePrefix` | No | Prefix for resources (default: cogai) |
| `ManagementGroupId` | No | For cross-subscription queries |
| `Tags` | No | Hashtable of tags |
| `SkipInfrastructure` | No | Only deploy/update workflow |
| `SkipWorkflow` | No | Only deploy infrastructure |

### Option 2: Manual Deployment

#### Step 1: Update Parameters

Edit [main.bicepparam](main.bicepparam) with your values:

```bicep
param logAnalyticsWorkspaceName = 'your-workspace-name'
param logAnalyticsWorkspaceResourceGroupName = 'your-workspace-rg'
param resourceGroupName = 'rg-cognitive-services-inventory'
param location = 'eastus'
```

#### Step 2: Deploy Main Infrastructure

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "<your-subscription-id>"

# Deploy at subscription scope
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

#### Step 3: Configure Logic App Workflow

After deployment, you need to configure the Logic App with the DCR/DCE settings:

1. Navigate to the deployed Logic App in Azure Portal
2. Go to **Configuration** > **Application settings**
3. Add the following settings using values from deployment outputs:

| Setting | Value |
|---------|-------|
| `DCE_LOGS_INGESTION_ENDPOINT` | From output: `dceLogsIngestionEndpoint` |
| `DCR_IMMUTABLE_ID` | From output: `dcrImmutableId` |
| `DCR_STREAM_NAME` | From output: `dcrStreamName` |

4. Deploy the workflow using Azure Functions Core Tools:
   ```bash
   # Navigate to the repo root
   cd CustomLATable
   
   # Deploy the workflow
   func azure functionapp publish <logic-app-name> --javascript
   ```

#### Step 4: (Optional) Cross-Subscription RBAC

For cross-subscription queries, deploy the management group RBAC:

```bash
# Update main-management-group-rbac.bicepparam with the Logic App principal ID
# (from the main deployment output: logicAppPrincipalId)

az deployment mg create \
  --management-group-id "<your-management-group-id>" \
  --location eastus \
  --template-file main-management-group-rbac.bicep \
  --parameters main-management-group-rbac.bicepparam
```

## Usage

### Trigger the Workflow

The workflow queries **all Cognitive Services resources** that the Logic App's managed identity has `Reader` access to. The query scope is determined entirely by RBAC permissions, not by request parameters.

```bash
# Get the callback URL from the Azure Portal or via CLI
curl -X POST "<callback-url>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Using Azure CLI to trigger:**
```powershell
# Get the callback URL
$callbackUrl = (az rest --method post --uri "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<logic-app-name>/hostruntime/runtime/webhooks/workflow/api/management/workflows/cognitive-services-inventory/triggers/When_a_HTTP_request_is_received/listCallbackUrl?api-version=2024-04-01" -o json | ConvertFrom-Json).value

# Trigger the workflow
Invoke-RestMethod -Uri $callbackUrl -Method POST -ContentType "application/json" -Body '{}'
```

### Query the Custom Table

```kusto
CognitiveServicesInventory_CL
| where TimeGenerated > ago(1h)
| summarize count() by Kind, Location
| order by count_ desc
```

## RBAC Assignments

The deployment creates the following role assignments for the Logic App managed identity:

| Role | Scope | Purpose |
|------|-------|---------|
| **Monitoring Metrics Publisher** | Data Collection Rule | Send data to DCR via Logs Ingestion API |
| **Reader** | Subscription or Management Group | Query Azure Resource Graph |

### Understanding Query Scope

The workflow's ability to discover Cognitive Services resources is **entirely determined by the managed identity's Reader permissions**:

| Reader Role Scope | Cognitive Services Discovered |
|-------------------|-------------------------------|
| Single Subscription | Only resources in that subscription |
| Multiple Subscriptions | Resources in each subscription where Reader is assigned |
| Management Group | All resources in subscriptions under that management group |

**Important:** The Log Analytics workspace permissions do **not** affect what Cognitive Services can be queried. The workspace only needs to accept data from the DCR (handled by the Monitoring Metrics Publisher role on the DCR). The Reader role on subscriptions/management groups is what enables cross-subscription resource discovery via Azure Resource Graph.

### Expanding Query Scope

To query Cognitive Services across multiple subscriptions:

1. **Option A: Assign Reader at Management Group level** (recommended)
   - Deploy the management group RBAC template (see Step 4 in Manual Deployment)
   - This grants Reader to all current and future subscriptions under the management group

2. **Option B: Assign Reader to individual subscriptions**
   ```bash
   # For each subscription you want to include
   az role assignment create \
     --assignee "<logic-app-principal-id>" \
     --role "Reader" \
     --scope "/subscriptions/<target-subscription-id>"
   ```

## Custom Table Schema

| Column | Type | Description |
|--------|------|-------------|
| TimeGenerated | datetime | Timestamp when record was created |
| ResourceId | string | Full Azure Resource ID |
| ResourceName | string | Name of the Cognitive Service |
| ResourceType | string | Resource type (microsoft.cognitiveservices/accounts) |
| Kind | string | Kind of Cognitive Service (e.g., OpenAI, TextAnalytics) |
| Location | string | Azure region |
| SubscriptionId | string | Subscription GUID |
| SubscriptionName | string | Subscription display name |
| ResourceGroup | string | Resource group name |
| Sku | string | SKU name |
| ProvisioningState | string | Resource provisioning state |
| PublicNetworkAccess | string | Public network access setting |
| Endpoint | string | Cognitive Services endpoint URL |

## File Structure

```
CustomLATable/
├── .funcignore                             # Files to exclude from workflow deployment
├── .gitignore                              # Git ignore file
├── Deploy-CognitiveServicesInventory.ps1   # Automated deployment script
├── host.json                               # Logic App host configuration
├── main.bicep                              # Main deployment template (subscription scope)
├── main.bicepparam                         # Parameters file for main deployment
├── main-management-group-rbac.bicep        # Management group RBAC deployment
├── main-management-group-rbac.bicepparam
├── cognitive-services-inventory/           # Workflow folder (deployed to Logic App)
│   └── workflow.json                       # Logic App workflow definition
├── modules/
│   ├── app-service-plan.bicep              # App Service Plan for Logic App
│   ├── custom-table.bicep                  # Custom Log Analytics table
│   ├── data-collection-endpoint.bicep      # Data Collection Endpoint
│   ├── data-collection-rule.bicep          # Data Collection Rule
│   ├── logic-app.bicep                     # Standard Logic App
│   ├── rbac-assignments.bicep              # RBAC at resource/subscription level
│   ├── rbac-management-group.bicep         # RBAC at management group level
│   └── storage-account.bicep               # Storage Account for Logic App
└── README.md                               # This file
```

## Troubleshooting

### Workflow not sending data to Log Analytics

1. Verify the Logic App application settings are configured correctly
2. Check the Logic App managed identity has the `Monitoring Metrics Publisher` role on the DCR
3. Review the Logic App workflow run history for errors

### Resource Graph not returning expected results

1. Verify the Logic App managed identity has `Reader` role at the appropriate scope
2. For cross-subscription queries, ensure the management group RBAC is deployed
3. Test the Resource Graph query directly in Azure Portal

### Custom table not created

1. Ensure the custom table module is deployed to the same resource group as the Log Analytics workspace
2. Wait a few minutes for the table to be created after DCR deployment

## License

MIT License
