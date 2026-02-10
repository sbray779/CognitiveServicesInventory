<#
.SYNOPSIS
    Deploys the Cognitive Services Inventory infrastructure and workflow to Azure.

.DESCRIPTION
    This script automates the complete deployment of:
    1. Azure infrastructure (DCE, DCR, Custom Table, Logic App, Storage, RBAC)
    2. Logic App application settings configuration
    3. Logic App workflow deployment

    Requires Azure PowerShell module (Az). Install with: Install-Module -Name Az -Scope CurrentUser

.PARAMETER LogAnalyticsWorkspaceName
    Required. Name of the existing Log Analytics workspace.

.PARAMETER LogAnalyticsWorkspaceResourceGroupName
    Required. Resource group name where the Log Analytics workspace exists.

.PARAMETER ResourceGroupName
    Required. The resource group name for deploying new resources.

.PARAMETER Location
    Required. Azure region for deployment (e.g., eastus, westus2).

.PARAMETER SubscriptionId
    Optional. Target subscription ID. If not provided, uses current context.

.PARAMETER CustomTableName
    Optional. Custom table name (without _CL suffix). Default: CognitiveServicesInventory

.PARAMETER ResourcePrefix
    Optional. Prefix for all resource names. Default: cogai

.PARAMETER ManagementGroupId
    Optional. Management group ID for cross-subscription queries. Leave empty for subscription scope.

.PARAMETER Tags
    Optional. Hashtable of tags to apply to resources.

.PARAMETER SkipInfrastructure
    Optional. Skip infrastructure deployment and only deploy/update the workflow.

.PARAMETER SkipWorkflow
    Optional. Skip workflow deployment and only deploy infrastructure.

.EXAMPLE
    .\Deploy-CognitiveServicesInventory.ps1 `
        -LogAnalyticsWorkspaceName "my-workspace" `
        -LogAnalyticsWorkspaceResourceGroupName "my-workspace-rg" `
        -ResourceGroupName "rg-cognitive-inventory" `
        -Location "eastus"

.EXAMPLE
    .\Deploy-CognitiveServicesInventory.ps1 `
        -LogAnalyticsWorkspaceName "my-workspace" `
        -LogAnalyticsWorkspaceResourceGroupName "my-workspace-rg" `
        -ResourceGroupName "rg-cognitive-inventory" `
        -Location "eastus" `
        -ManagementGroupId "my-management-group" `
        -Tags @{ Environment = "Production"; Project = "AI Inventory" }
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsWorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsWorkspaceResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$CustomTableName = "CognitiveServicesInventory",

    [Parameter(Mandatory = $false)]
    [string]$ResourcePrefix = "cogai",

    [Parameter(Mandatory = $false)]
    [string]$ManagementGroupId = "",

    [Parameter(Mandatory = $false)]
    [hashtable]$Tags = @{},

    [Parameter(Mandatory = $false)]
    [switch]$SkipInfrastructure,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWorkflow
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Colors for output
function Write-Step { param($Message) Write-Host "`n▶ $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "  $Message" -ForegroundColor Gray }
function Write-Warn { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }

# ============================================
# Verify Azure PowerShell Module
# ============================================
Write-Step "Verifying Azure PowerShell module..."

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Azure PowerShell module (Az) is not installed. Install with: Install-Module -Name Az -Scope CurrentUser"
    exit 1
}

# Import required modules
$requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Websites')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module)) {
        Import-Module $module -ErrorAction SilentlyContinue
    }
}

Write-Success "Azure PowerShell modules loaded"

# ============================================
# Verify Azure Authentication
# ============================================
Write-Step "Verifying Azure authentication..."

$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $context) {
    Write-Warn "Not logged in to Azure. Starting login..."
    Connect-AzAccount
    $context = Get-AzContext
}

if (-not $context) {
    Write-Error "Failed to authenticate to Azure. Please run Connect-AzAccount manually."
    exit 1
}

Write-Success "Logged in as: $($context.Account.Id)"
Write-Info "Tenant: $($context.Tenant.Id)"

# Set subscription if provided
if ($SubscriptionId) {
    Write-Info "Setting subscription to: $SubscriptionId"
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $context = Get-AzContext
}

Write-Info "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"

# Variables to store deployment outputs
$deploymentOutputs = $null

# ============================================
# STEP 1: Deploy Infrastructure
# ============================================
if (-not $SkipInfrastructure) {
    Write-Step "Deploying Azure infrastructure..."
    
    $deploymentName = "cognitive-inventory-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Info "Deployment name: $deploymentName"
    Write-Info "Resource group: $ResourceGroupName"
    Write-Info "Location: $Location"

    # Build parameters hashtable
    $bicepParams = @{
        logAnalyticsWorkspaceName              = $LogAnalyticsWorkspaceName
        logAnalyticsWorkspaceResourceGroupName = $LogAnalyticsWorkspaceResourceGroupName
        resourceGroupName                      = $ResourceGroupName
        location                               = $Location
        customTableName                        = $CustomTableName
        resourcePrefix                         = $ResourcePrefix
        managementGroupId                      = $ManagementGroupId
        tags                                   = $Tags
    }

    try {
        $deployment = New-AzSubscriptionDeployment `
            -Name $deploymentName `
            -Location $Location `
            -TemplateFile "$scriptPath\main.bicep" `
            -TemplateParameterObject $bicepParams `
            -Verbose

        if ($deployment.ProvisioningState -ne "Succeeded") {
            Write-Error "Infrastructure deployment failed with state: $($deployment.ProvisioningState)"
            exit 1
        }

        $deploymentOutputs = $deployment.Outputs
        Write-Success "Infrastructure deployed successfully"

        # Display outputs
        Write-Info "DCE Name: $($deploymentOutputs.dceName.Value)"
        Write-Info "DCR Name: $($deploymentOutputs.dcrName.Value)"
        Write-Info "Logic App: $($deploymentOutputs.logicAppName.Value)"
        Write-Info "Custom Table: $($deploymentOutputs.customTableName.Value)"
    }
    catch {
        Write-Error "Infrastructure deployment failed: $_"
        exit 1
    }
}
else {
    Write-Step "Skipping infrastructure deployment (retrieving existing deployment outputs)..."
    
    # Get the latest deployment outputs
    $deployments = Get-AzSubscriptionDeployment | Where-Object { $_.DeploymentName -like "cognitive-inventory-*" }
    
    if ($deployments.Count -eq 0) {
        Write-Error "No existing deployment found. Run without -SkipInfrastructure first."
        exit 1
    }

    $latestDeployment = $deployments | Sort-Object -Property Timestamp -Descending | Select-Object -First 1
    $deploymentOutputs = $latestDeployment.Outputs
    
    Write-Success "Retrieved outputs from deployment: $($latestDeployment.DeploymentName)"
}

# Extract output values
$logicAppName = $deploymentOutputs.logicAppName.Value
$dceLogsIngestionEndpoint = $deploymentOutputs.dceLogsIngestionEndpoint.Value
$dcrImmutableId = $deploymentOutputs.dcrImmutableId.Value
$dcrStreamName = $deploymentOutputs.dcrStreamName.Value
$logicAppHostName = $deploymentOutputs.logicAppHostName.Value
$logicAppPrincipalId = $deploymentOutputs.logicAppPrincipalId.Value
$userAssignedIdentityResourceId = $deploymentOutputs.userAssignedIdentityResourceId.Value
$userAssignedIdentityPrincipalId = $deploymentOutputs.userAssignedIdentityPrincipalId.Value

# ============================================
# STEP 2: Configure Logic App Settings
# ============================================
if (-not $SkipWorkflow) {
    Write-Step "Configuring Logic App application settings..."

    try {
        # Get the Logic App
        $logicApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $logicAppName

        # Get existing app settings
        $appSettings = @{}
        foreach ($setting in $logicApp.SiteConfig.AppSettings) {
            $appSettings[$setting.Name] = $setting.Value
        }

        # Add/Update DCE/DCR settings
        $appSettings["DCE_LOGS_INGESTION_ENDPOINT"] = $dceLogsIngestionEndpoint
        $appSettings["DCR_IMMUTABLE_ID"] = $dcrImmutableId
        $appSettings["DCR_STREAM_NAME"] = $dcrStreamName
        $appSettings["USER_ASSIGNED_IDENTITY_RESOURCE_ID"] = $userAssignedIdentityResourceId

        # Update the Logic App with new settings
        Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $logicAppName -AppSettings $appSettings | Out-Null

        Write-Success "Logic App settings configured"
        Write-Info "DCE_LOGS_INGESTION_ENDPOINT: $dceLogsIngestionEndpoint"
        Write-Info "DCR_IMMUTABLE_ID: $dcrImmutableId"
        Write-Info "DCR_STREAM_NAME: $dcrStreamName"
        Write-Info "USER_ASSIGNED_IDENTITY_RESOURCE_ID: $userAssignedIdentityResourceId"
    }
    catch {
        Write-Error "Failed to configure Logic App settings: $_"
        exit 1
    }

    # ============================================
    # STEP 3: Deploy Workflow using Azure Functions Core Tools
    # ============================================
    Write-Step "Deploying Logic App workflow..."

    $workflowPath = "$scriptPath\cognitive-services-inventory\workflow.json"
    $hostJsonPath = "$scriptPath\host.json"
    
    if (-not (Test-Path $workflowPath)) {
        Write-Error "Workflow file not found: $workflowPath"
        exit 1
    }

    if (-not (Test-Path $hostJsonPath)) {
        Write-Error "host.json not found: $hostJsonPath"
        exit 1
    }

    try {
        # Check if Azure Functions Core Tools is installed
        $funcVersion = func --version 2>$null
        if (-not $funcVersion) {
            Write-Warn "Azure Functions Core Tools not found. Attempting alternative deployment..."
            throw "func CLI not found"
        }

        Write-Info "Using Azure Functions Core Tools v$funcVersion"
        
        # Deploy using func azure functionapp publish
        Push-Location $scriptPath
        $publishResult = func azure functionapp publish $logicAppName --javascript 2>&1
        Pop-Location

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Workflow deployed successfully via Azure Functions Core Tools"
        }
        else {
            Write-Warn "func publish returned exit code: $LASTEXITCODE"
            throw "func publish failed: $publishResult"
        }
    }
    catch {
        Write-Warn "Azure Functions Core Tools deployment failed: $_"
        Write-Info "Attempting Kudu VFS API deployment method..."

        try {
            # Alternative: Use VFS API with publishing credentials
            $publishingCredentials = Invoke-AzResourceAction `
                -ResourceGroupName $ResourceGroupName `
                -ResourceType "Microsoft.Web/sites/config" `
                -ResourceName "$logicAppName/publishingcredentials" `
                -Action list `
                -ApiVersion "2024-04-01" `
                -Force

            $kuduUsername = $publishingCredentials.properties.publishingUserName
            $kuduPassword = $publishingCredentials.properties.publishingPassword
            $kuduBaseUrl = "https://$logicAppName.scm.azurewebsites.net"

            $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${kuduUsername}:${kuduPassword}"))
            $headers = @{
                "Authorization" = "Basic $base64Auth"
                "If-Match"      = "*"
                "Content-Type"  = "application/json"
            }

            # Create workflow directory
            $dirUrl = "$kuduBaseUrl/api/vfs/site/wwwroot/cognitive-services-inventory/"
            Invoke-RestMethod -Uri $dirUrl -Method PUT -Headers $headers -ErrorAction SilentlyContinue

            # Upload workflow.json
            $workflowApiUrl = "$kuduBaseUrl/api/vfs/site/wwwroot/cognitive-services-inventory/workflow.json"
            $workflowJson = Get-Content $workflowPath -Raw
            Invoke-RestMethod -Uri $workflowApiUrl -Method PUT -Headers $headers -Body $workflowJson

            # Upload host.json
            $hostApiUrl = "$kuduBaseUrl/api/vfs/site/wwwroot/host.json"
            $hostJson = Get-Content $hostJsonPath -Raw
            Invoke-RestMethod -Uri $hostApiUrl -Method PUT -Headers $headers -Body $hostJson

            Write-Success "Workflow deployed successfully via VFS API"
        }
        catch {
            Write-Warn "Automated workflow deployment failed: $_"
            Write-Warn "Please deploy the workflow manually using Azure Functions Core Tools:"
            Write-Info "  1. Install Azure Functions Core Tools: npm install -g azure-functions-core-tools@4"
            Write-Info "  2. Navigate to the repo root: cd $scriptPath"
            Write-Info "  3. Deploy: func azure functionapp publish $logicAppName --javascript"
        }
    }
}

# ============================================
# STEP 4: Deploy Management Group RBAC (Optional)
# ============================================
if ($ManagementGroupId -and -not $SkipInfrastructure) {
    Write-Step "Deploying Management Group RBAC for cross-subscription queries..."
    
    $mgDeploymentName = "mg-rbac-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    try {
        $mgDeployment = New-AzManagementGroupDeployment `
            -ManagementGroupId $ManagementGroupId `
            -Location $Location `
            -Name $mgDeploymentName `
            -TemplateFile "$scriptPath\main-management-group-rbac.bicep" `
            -TemplateParameterObject @{ 
                userAssignedIdentityPrincipalId = $userAssignedIdentityPrincipalId
            }

        if ($mgDeployment.ProvisioningState -eq "Succeeded") {
            Write-Success "Management Group RBAC deployed successfully"
            Write-Info "User-Assigned Identity has Reader access at management group level"
        }
        else {
            Write-Warn "Management Group RBAC deployment state: $($mgDeployment.ProvisioningState)"
        }
    }
    catch {
        Write-Warn "Management Group RBAC deployment failed: $_"
        Write-Info "You may need to deploy this manually with appropriate permissions."
    }
}

# ============================================
# Summary
# ============================================
Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Resource Group:     $ResourceGroupName" -ForegroundColor White
Write-Host "  Logic App:          $logicAppName" -ForegroundColor White
Write-Host "  Custom Table:       ${CustomTableName}_CL" -ForegroundColor White
Write-Host ""
Write-Host "  Logic App URL:" -ForegroundColor White
Write-Host "  https://$logicAppHostName" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Navigate to the Logic App in Azure Portal" -ForegroundColor White
Write-Host "  2. Go to Workflows > cognitive-services-inventory" -ForegroundColor White
Write-Host "  3. Get the workflow callback URL from the trigger" -ForegroundColor White
Write-Host "  4. Test by sending a POST request to the callback URL" -ForegroundColor White
Write-Host ""

if ($ManagementGroupId) {
    Write-Host "  For cross-subscription queries, include in request body:" -ForegroundColor Yellow
    Write-Host "  { `"managementGroupId`": `"$ManagementGroupId`" }" -ForegroundColor Cyan
}

Write-Host ""
