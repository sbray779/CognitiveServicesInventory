# =============================================================================
# Cognitive Services Deployment Inventory - Terraform Deployment
# =============================================================================
# This Terraform configuration deploys the same infrastructure as the Bicep
# templates: DCE, DCR, Custom Table, Storage, App Service Plan, Logic App,
# and RBAC assignments.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

# =============================================================================
# Data Sources
# =============================================================================

data "azurerm_subscription" "current" {}

data "azurerm_log_analytics_workspace" "existing" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.log_analytics_workspace_resource_group_name
}

# =============================================================================
# Random Suffix for Unique Names
# =============================================================================

resource "random_string" "suffix" {
  length  = 13
  special = false
  upper   = false
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  unique_suffix     = random_string.suffix.result
  dce_name          = "${var.resource_prefix}-dce-${local.unique_suffix}"
  dcr_name          = "${var.resource_prefix}-dcr-${local.unique_suffix}"
  storage_name      = "${var.resource_prefix}st${local.unique_suffix}"
  logic_app_name    = "${var.resource_prefix}-logicapp-${local.unique_suffix}"
  asp_name          = "${var.resource_prefix}-asp-${local.unique_suffix}"
  custom_table_name = "${var.custom_table_name}_CL"
  stream_name       = "Custom-${var.custom_table_name}_CL"

  default_tags = {
    ManagedBy = "Terraform"
    Project   = "CognitiveServicesInventory"
  }

  tags = merge(local.default_tags, var.tags)

  # Custom table schema columns
  table_columns = [
    { name = "TimeGenerated", type = "datetime", description = "The time the record was generated" },
    { name = "DeploymentId", type = "string", description = "Full Azure Resource ID of the deployment" },
    { name = "DeploymentName", type = "string", description = "Name of the deployment" },
    { name = "ModelName", type = "string", description = "The model deployed (e.g., gpt-4, text-embedding-ada-002)" },
    { name = "ModelVersion", type = "string", description = "Version of the deployed model" },
    { name = "ModelFormat", type = "string", description = "Format/type of the model (e.g., OpenAI)" },
    { name = "SkuName", type = "string", description = "SKU name (e.g., Standard, GlobalStandard)" },
    { name = "SkuCapacity", type = "int", description = "Provisioned capacity/TPM" },
    { name = "AccountName", type = "string", description = "Parent Cognitive Services account name" },
    { name = "AccountId", type = "string", description = "Full Azure Resource ID of the parent account" },
    { name = "AccountKind", type = "string", description = "Kind of the parent account (e.g., OpenAI, CognitiveServices)" },
    { name = "AccountEndpoint", type = "string", description = "Endpoint URL of the parent Cognitive Services account" },
    { name = "SubscriptionId", type = "string", description = "Subscription ID containing the resource" },
    { name = "SubscriptionName", type = "string", description = "Subscription name containing the resource" },
    { name = "ResourceGroup", type = "string", description = "Resource group containing the resource" },
    { name = "Location", type = "string", description = "Azure region where the resource is deployed" }
  ]
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# =============================================================================
# Custom Table in Log Analytics (using AzAPI)
# =============================================================================

resource "azapi_resource" "custom_table" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = local.custom_table_name
  parent_id = data.azurerm_log_analytics_workspace.existing.id

  body = {
    properties = {
      schema = {
        name    = local.custom_table_name
        columns = local.table_columns
      }
      retentionInDays      = var.retention_in_days
      totalRetentionInDays = var.total_retention_in_days
    }
  }
}

# =============================================================================
# Data Collection Endpoint
# =============================================================================

resource "azurerm_monitor_data_collection_endpoint" "main" {
  name                          = local.dce_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  kind                          = "Linux"
  public_network_access_enabled = true
  description                   = "Data Collection Endpoint for Cognitive Services Inventory"
  tags                          = local.tags
}

# =============================================================================
# Data Collection Rule (using AzAPI for full control)
# =============================================================================

resource "azapi_resource" "data_collection_rule" {
  type      = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  name      = local.dcr_name
  location  = var.location
  parent_id = azurerm_resource_group.main.id
  tags      = local.tags

  body = {
    kind = "Direct"
    properties = {
      description              = "DCR for ingesting Cognitive Services deployment inventory to custom Log Analytics table"
      dataCollectionEndpointId = azurerm_monitor_data_collection_endpoint.main.id
      streamDeclarations = {
        (local.stream_name) = {
          columns = [
            { name = "TimeGenerated", type = "datetime" },
            { name = "DeploymentId", type = "string" },
            { name = "DeploymentName", type = "string" },
            { name = "ModelName", type = "string" },
            { name = "ModelVersion", type = "string" },
            { name = "ModelFormat", type = "string" },
            { name = "SkuName", type = "string" },
            { name = "SkuCapacity", type = "int" },
            { name = "AccountName", type = "string" },
            { name = "AccountId", type = "string" },
            { name = "AccountKind", type = "string" },
            { name = "AccountEndpoint", type = "string" },
            { name = "SubscriptionId", type = "string" },
            { name = "SubscriptionName", type = "string" },
            { name = "ResourceGroup", type = "string" },
            { name = "Location", type = "string" }
          ]
        }
      }
      destinations = {
        logAnalytics = [
          {
            workspaceResourceId = data.azurerm_log_analytics_workspace.existing.id
            name                = "logAnalyticsWorkspace"
          }
        ]
      }
      dataFlows = [
        {
          streams      = [local.stream_name]
          destinations = ["logAnalyticsWorkspace"]
          transformKql = "source | project TimeGenerated, DeploymentId, DeploymentName, ModelName, ModelVersion, ModelFormat, SkuName, SkuCapacity, AccountName, AccountId, AccountKind, AccountEndpoint, SubscriptionId, SubscriptionName, ResourceGroup, Location"
          outputStream = local.stream_name
        }
      ]
    }
  }

  depends_on = [azapi_resource.custom_table]
}

# =============================================================================
# Storage Account for Logic App
# =============================================================================

resource "azurerm_storage_account" "main" {
  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  tags                            = local.tags
}

# =============================================================================
# App Service Plan (Workflow Standard)
# =============================================================================

resource "azurerm_service_plan" "main" {
  name                = local.asp_name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  os_type             = "Windows"
  sku_name            = "WS1"
  tags                = local.tags
}

# =============================================================================
# Logic App (Standard)
# =============================================================================

resource "azurerm_logic_app_standard" "main" {
  name                                       = local.logic_app_name
  resource_group_name                        = azurerm_resource_group.main.name
  location                                   = var.location
  app_service_plan_id                        = azurerm_service_plan.main.id
  storage_account_name                       = azurerm_storage_account.main.name
  storage_account_access_key                 = azurerm_storage_account.main.primary_access_key
  https_only                                 = true
  version                                    = "~4"
  tags                                       = local.tags

  # Enable basic auth for SCM/Kudu deployment
  ftp_publish_basic_authentication_enabled   = true
  scm_publish_basic_authentication_enabled   = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    dotnet_framework_version  = "v6.0"
    use_32_bit_worker_process = false
    ftps_state                = "Disabled"
    min_tls_version           = "1.2"
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"      = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"  = "~18"
  }
}

# =============================================================================
# RBAC: Monitoring Metrics Publisher on DCR
# =============================================================================

resource "azurerm_role_assignment" "monitoring_metrics_publisher" {
  scope                = azapi_resource.data_collection_rule.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# =============================================================================
# RBAC: Reader at Subscription Level (when no management group specified)
# =============================================================================

resource "azurerm_role_assignment" "reader_subscription" {
  count                = var.management_group_id == "" ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# =============================================================================
# RBAC: Reader at Management Group Level (when management group specified)
# =============================================================================

resource "azurerm_role_assignment" "reader_management_group" {
  count                = var.management_group_id != "" ? 1 : 0
  scope                = "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
