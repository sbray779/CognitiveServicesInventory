# Cognitive Services Deployment Inventory - Azure Infrastructure

This repository contains Azure Bicep templates for deploying infrastructure to inventory all Azure Cognitive Services **deployments** (model deployments within accounts) across subscriptions and log them to a custom Log Analytics table.

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
│  │ 2. Query Azure Resource Graph for all Cognitive Services ACCOUNTS  │  │
│  │    (scope determined by managed identity's Reader permissions)     │  │
│  │ 3. For each account (20 in parallel):                              │  │
│  │    a. Call ARM API to get DEPLOYMENTS                              │  │
│  │    b. Transform deployments with account metadata                  │  │
│  │    c. Send to DCR immediately (per-account batching)               │  │
│  │ 4. Return summary response                                         │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                          (System Managed Identity)                        │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                            (multiple parallel sends)
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              Data Collection Endpoint (DCE) & Rule (DCR)                  │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ • Logs Ingestion API endpoint                                      │  │
│  │ • Deployment-focused custom table schema                           │  │
│  │ • Transform KQL (passthrough)                                      │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────┬────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                      Log Analytics Workspace                              │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ CognitiveServicesInventory_CL (Custom Table)                       │  │
│  │ Deployment Fields:                                                 │  │
│  │ • DeploymentId, DeploymentName, ModelName, ModelVersion            │  │
│  │ • ModelFormat, SkuName, SkuCapacity                                │  │
│  │ Account Fields:                                                    │  │
│  │ • AccountName, AccountId, AccountKind, AccountEndpoint             │  │
│  │ Metadata:                                                          │  │
│  │ • SubscriptionId, SubscriptionName, ResourceGroup, Location        │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

## How It Works

The workflow uses a **two-step query approach** because Cognitive Services deployments are not indexed in Azure Resource Graph:

1. **Step 1 - Query Accounts**: Use Azure Resource Graph to find all Cognitive Services accounts
2. **Step 2 - Query Deployments**: For each account, call the ARM API to retrieve deployments

This approach ensures complete visibility into all model deployments across your Azure environment.

## Scalability Features

The workflow is designed for large-scale environments with many Cognitive Services accounts:

| Feature | Description |
|---------|-------------|
| **Parallel Processing** | Processes up to 20 accounts concurrently |
| **Per-Account DCR Sends** | Sends deployments to Log Analytics per account (avoids 1MB payload limit) |
| **Select Transform** | Uses efficient Select action instead of nested loops |
| **Exponential Retry** | Automatically retries on ARM API throttling (429 errors) |
| **Chunked Transfer** | Uses chunked transfer mode for large responses |

### Performance Characteristics

| Accounts | Sequential (old) | Parallel (current) |
|----------|------------------|-------------------|
| 10 | ~30 seconds | ~5 seconds |
| 100 | ~5 minutes | ~30 seconds |
| 500 | ~25 minutes | ~2-3 minutes |

### Limitations

- **Resource Graph**: Returns max 1000 accounts per query (pagination not yet implemented)
- **HTTP Trigger Timeout**: 30 minutes max execution time
- **ARM API Rate Limits**: ~12,000 requests/hour per subscription (retry policy handles throttling)

## Components

| Component | Description |
|-----------|-------------|
| **Data Collection Endpoint (DCE)** | Provides the ingestion endpoint for the Logs Ingestion API |
| **Data Collection Rule (DCR)** | Defines the deployment-focused table schema and routing to Log Analytics |
| **Custom Table** | `CognitiveServicesInventory_CL` table with deployment and account fields |
| **Storage Account** | Required backing storage for Standard Logic App |
| **App Service Plan** | Workflow Standard SKU for Logic App hosting |
| **Standard Logic App** | Hosts the workflow with managed identity |
| **Logic App Workflow** | HTTP-triggered workflow that queries accounts via Resource Graph, then queries deployments via ARM API |
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
// Summary of deployments by model
CognitiveServicesInventory_CL
| where TimeGenerated > ago(1h)
| summarize DeploymentCount=count(), TotalCapacity=sum(SkuCapacity) by ModelName, SkuName
| order by DeploymentCount desc

// All deployments with account details
CognitiveServicesInventory_CL
| where TimeGenerated > ago(1h)
| project DeploymentName, ModelName, ModelVersion, SkuName, SkuCapacity, AccountName, SubscriptionName, Location
| order by AccountName, DeploymentName

// Capacity by subscription
CognitiveServicesInventory_CL
| where TimeGenerated > ago(1h)
| summarize TotalCapacity=sum(SkuCapacity), DeploymentCount=count() by SubscriptionName, ModelName
| order by TotalCapacity desc
```

### Join with API Management Logs

Use the custom table to enrich API Management LLM logs with deployment details:

```kusto
ApiManagementGatewayLogs 
| where TimeGenerated >= ago(60d) 
| join kind=inner ApiManagementGatewayLlmLog on CorrelationId 
| where SequenceNumber == 0 and IsRequestSuccess 
| extend ParsedUrl = parse_url(BackendUrl)
| extend ExtractedEndpoint = strcat(ParsedUrl.Scheme, "://", ParsedUrl.Host, "/")
| extend DeploymentFromUrl = extract("/openai/deployments/([^/]+)/", 1, BackendUrl)
| join kind=leftouter (
    CognitiveServicesInventory_CL 
    | summarize arg_max(TimeGenerated, *) by AccountEndpoint, DeploymentName
    | project 
        AccountEndpoint, 
        CogSvcDeploymentName = DeploymentName,
        CogSvcModelName = ModelName,
        CogSvcSkuName = SkuName,
        CogSvcSkuCapacity = SkuCapacity,
        CogSvcAccountName = AccountName,
        CogSvcSubscriptionId = SubscriptionId
) on $left.ExtractedEndpoint == $right.AccountEndpoint, $left.DeploymentFromUrl == $right.CogSvcDeploymentName
| summarize 
    TotalTokens = sum(TotalTokens), 
    CompletionTokens = sum(CompletionTokens), 
    PromptTokens = sum(PromptTokens), 
    FirstSeen = min(TimeGenerated), 
    LastSeen = max(TimeGenerated), 
    Regions = make_set(Region, 8), 
    CallerIpAddresses = make_set(CallerIpAddress, 8), 
    Calls = count() 
    by ProductId, DeploymentFromUrl, ExtractedEndpoint, BackendId, CogSvcModelName, CogSvcSkuName, CogSvcSkuCapacity, CogSvcAccountName, CogSvcSubscriptionId
| project 
    ProductId, 
    DeploymentName = DeploymentFromUrl,
    ModelName = CogSvcModelName,
    AccountName = CogSvcAccountName,
    SubscriptionId = CogSvcSubscriptionId,
    SkuName = CogSvcSkuName,
    SkuCapacity = CogSvcSkuCapacity,
    BackendId,
    Endpoint = ExtractedEndpoint,
    PromptTokens, 
    CompletionTokens, 
    TotalTokens, 
    Calls, 
    FirstSeen, 
    LastSeen, 
    Regions, 
    CallerIpAddresses
| order by ProductId asc, TotalTokens desc
```

## RBAC Assignments

The deployment creates the following role assignments for the Logic App managed identity:

| Role | Scope | Purpose |
|------|-------|---------|
| **Monitoring Metrics Publisher** | Data Collection Rule | Send data to DCR via Logs Ingestion API |
| **Reader** | Subscription or Management Group | Query Azure Resource Graph |

### Understanding Query Scope

The workflow uses a **two-step query approach** that requires Reader permissions:

1. **Resource Graph Query**: Finds all Cognitive Services accounts the managed identity can read
2. **ARM API Calls**: For each account, retrieves deployments (also requires Reader on the account)

| Reader Role Scope | Cognitive Services Discovered |
|-------------------|-------------------------------|
| Single Subscription | Only accounts/deployments in that subscription |
| Multiple Subscriptions | Accounts/deployments in each subscription where Reader is assigned |
| Management Group | All accounts/deployments in subscriptions under that management group |

**Important:** The Log Analytics workspace permissions do **not** affect what Cognitive Services can be queried. The workspace only needs to accept data from the DCR (handled by the Monitoring Metrics Publisher role on the DCR). The Reader role on subscriptions/management groups is what enables cross-subscription resource discovery via Azure Resource Graph and ARM API.

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
| DeploymentId | string | Full Azure Resource ID of the deployment |
| DeploymentName | string | Name of the deployment |
| ModelName | string | The model deployed (e.g., gpt-4, text-embedding-ada-002) |
| ModelVersion | string | Version of the deployed model |
| ModelFormat | string | Format/type of the model (e.g., OpenAI) |
| SkuName | string | SKU name (e.g., Standard, GlobalStandard) |
| SkuCapacity | int | Provisioned capacity/TPM |
| AccountName | string | Parent Cognitive Services account name |
| AccountId | string | Full Azure Resource ID of the parent account |
| AccountKind | string | Kind of the parent account (e.g., OpenAI, CognitiveServices) |
| AccountEndpoint | string | Endpoint URL of the parent Cognitive Services account |
| SubscriptionId | string | Subscription GUID |
| SubscriptionName | string | Subscription display name |
| ResourceGroup | string | Resource group name |
| Location | string | Azure region |

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
4. Check the workflow health status in the Azure Portal (should be "Healthy")

### Resource Graph not returning expected accounts

1. Verify the Logic App managed identity has `Reader` role at the appropriate scope
2. For cross-subscription queries, ensure the management group RBAC is deployed
3. Test the Resource Graph query directly in Azure Portal

### Deployments not being retrieved

1. Verify the Logic App managed identity has `Reader` role on the Cognitive Services accounts
2. Check workflow run history for 403 (Forbidden) errors on ARM API calls
3. Ensure accounts are not filtered out by network restrictions (Private Endpoint only)

### Custom table not created

1. Ensure the custom table module is deployed to the same resource group as the Log Analytics workspace
2. Wait a few minutes for the table to be created after DCR deployment

## License

MIT License
