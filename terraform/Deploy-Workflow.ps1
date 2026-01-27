<#
.SYNOPSIS
    Deploys the Logic App workflow after Terraform infrastructure deployment.

.DESCRIPTION
    This script automates the post-Terraform deployment of:
    1. Logic App application settings configuration (DCE, DCR settings)
    2. Logic App workflow deployment

    Run this after 'terraform apply' completes successfully.
    
    Requires:
    - Azure PowerShell module (Az). Install with: Install-Module -Name Az -Scope CurrentUser
    - Azure Functions Core Tools (optional, will fall back to Kudu API)

.PARAMETER TerraformDir
    Optional. Path to the Terraform directory. Default: current directory.

.PARAMETER WorkflowSourceDir
    Optional. Path to the workflow source files. Default: parent directory.

.PARAMETER SkipSettings
    Optional. Skip Logic App settings configuration.

.PARAMETER SkipWorkflow
    Optional. Skip workflow deployment.

.EXAMPLE
    .\Deploy-Workflow.ps1

.EXAMPLE
    .\Deploy-Workflow.ps1 -TerraformDir "C:\path\to\terraform" -WorkflowSourceDir "C:\path\to\repo"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TerraformDir = ".",

    [Parameter(Mandatory = $false)]
    [string]$WorkflowSourceDir = "..",

    [Parameter(Mandatory = $false)]
    [switch]$SkipSettings,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWorkflow
)

$ErrorActionPreference = "Stop"

# ============================================
# Helper Functions
# ============================================
function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Gray }
function Write-Warn { param([string]$Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }

# ============================================
# Validate Prerequisites
# ============================================
Write-Step "Validating prerequisites..."

# Check Azure PowerShell
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Azure PowerShell module not found. Install with: Install-Module -Name Az -Scope CurrentUser"
    exit 1
}

# Check Terraform
$terraformVersion = terraform --version 2>$null
if (-not $terraformVersion) {
    Write-Error "Terraform CLI not found. Please install Terraform."
    exit 1
}

# Resolve paths
$TerraformDir = Resolve-Path $TerraformDir
$WorkflowSourceDir = Resolve-Path (Join-Path $TerraformDir $WorkflowSourceDir)

Write-Info "Terraform directory: $TerraformDir"
Write-Info "Workflow source directory: $WorkflowSourceDir"

# Verify terraform state exists
$tfStateFile = Join-Path $TerraformDir "terraform.tfstate"
if (-not (Test-Path $tfStateFile)) {
    Write-Error "Terraform state file not found. Run 'terraform apply' first."
    exit 1
}

# Verify workflow files exist
$workflowPath = Join-Path $WorkflowSourceDir "cognitive-services-inventory\workflow.json"
$hostJsonPath = Join-Path $WorkflowSourceDir "host.json"

if (-not (Test-Path $workflowPath)) {
    Write-Error "Workflow file not found: $workflowPath"
    exit 1
}

if (-not (Test-Path $hostJsonPath)) {
    Write-Error "host.json not found: $hostJsonPath"
    exit 1
}

# ============================================
# Get Terraform Outputs
# ============================================
Write-Step "Reading Terraform outputs..."

Push-Location $TerraformDir
try {
    $terraformOutput = terraform output -json | ConvertFrom-Json
}
catch {
    Write-Error "Failed to read Terraform outputs: $_"
    Pop-Location
    exit 1
}
Pop-Location

# Extract values
$resourceGroupName = $terraformOutput.resource_group_name.value
$logicAppName = $terraformOutput.logic_app_name.value
$dceLogsIngestionEndpoint = $terraformOutput.dce_logs_ingestion_endpoint.value
$dcrImmutableId = $terraformOutput.dcr_immutable_id.value
$dcrStreamName = $terraformOutput.dcr_stream_name.value
$logicAppHostname = $terraformOutput.logic_app_hostname.value

Write-Success "Terraform outputs retrieved"
Write-Info "Resource Group: $resourceGroupName"
Write-Info "Logic App: $logicAppName"
Write-Info "DCE Endpoint: $dceLogsIngestionEndpoint"
Write-Info "DCR Immutable ID: $dcrImmutableId"
Write-Info "DCR Stream: $dcrStreamName"

# ============================================
# Verify Azure Login
# ============================================
Write-Step "Verifying Azure authentication..."

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Info "Not logged in to Azure. Initiating login..."
    Connect-AzAccount
    $context = Get-AzContext
}

Write-Success "Authenticated as: $($context.Account.Id)"
Write-Info "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"

# ============================================
# STEP 1: Configure Logic App Settings
# ============================================
if (-not $SkipSettings) {
    Write-Step "Configuring Logic App application settings..."

    try {
        # Get the Logic App
        $logicApp = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $logicAppName

        # Get existing app settings
        $appSettings = @{}
        foreach ($setting in $logicApp.SiteConfig.AppSettings) {
            $appSettings[$setting.Name] = $setting.Value
        }

        # Add/Update DCE/DCR settings
        $appSettings["DCE_LOGS_INGESTION_ENDPOINT"] = $dceLogsIngestionEndpoint
        $appSettings["DCR_IMMUTABLE_ID"] = $dcrImmutableId
        $appSettings["DCR_STREAM_NAME"] = $dcrStreamName

        # Update the Logic App with new settings
        Set-AzWebApp -ResourceGroupName $resourceGroupName -Name $logicAppName -AppSettings $appSettings | Out-Null

        Write-Success "Logic App settings configured"
        Write-Info "DCE_LOGS_INGESTION_ENDPOINT: $dceLogsIngestionEndpoint"
        Write-Info "DCR_IMMUTABLE_ID: $dcrImmutableId"
        Write-Info "DCR_STREAM_NAME: $dcrStreamName"
    }
    catch {
        Write-Error "Failed to configure Logic App settings: $_"
        exit 1
    }
}
else {
    Write-Info "Skipping Logic App settings configuration"
}

# ============================================
# STEP 2: Deploy Workflow
# ============================================
if (-not $SkipWorkflow) {
    Write-Step "Deploying Logic App workflow..."

    try {
        # Check if Azure Functions Core Tools is installed
        $funcVersion = func --version 2>$null
        if (-not $funcVersion) {
            Write-Warn "Azure Functions Core Tools not found. Attempting alternative deployment..."
            throw "func CLI not found"
        }

        Write-Info "Using Azure Functions Core Tools v$funcVersion"
        
        # Deploy using func azure functionapp publish
        Push-Location $WorkflowSourceDir
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
                -ResourceGroupName $resourceGroupName `
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

            Write-Success "Workflow deployed successfully via Kudu VFS API"
        }
        catch {
            Write-Error "Kudu VFS API deployment failed: $_"
            Write-Info ""
            Write-Info "Manual deployment steps:"
            Write-Info "1. Install Azure Functions Core Tools: npm install -g azure-functions-core-tools@4"
            Write-Info "2. Navigate to: $WorkflowSourceDir"
            Write-Info "3. Run: func azure functionapp publish $logicAppName --javascript"
            exit 1
        }
    }
}
else {
    Write-Info "Skipping workflow deployment"
}

# ============================================
# Summary
# ============================================
Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Green
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Info "Logic App Name: $logicAppName"
Write-Info "Logic App URL: https://$logicAppHostname"
Write-Host ""
Write-Info "To trigger the workflow manually:"
Write-Info "1. Go to Azure Portal > Logic Apps > $logicAppName"
Write-Info "2. Navigate to Workflows > cognitive-services-inventory"
Write-Info "3. Click 'Run Trigger' > 'manual'"
Write-Host ""
Write-Info "Or use the workflow callback URL (available in the Azure Portal after first trigger)"
