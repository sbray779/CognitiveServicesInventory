# =============================================================================
# Outputs
# =============================================================================

output "resource_group_name" {
  description = "The resource group name"
  value       = azurerm_resource_group.main.name
}

output "dce_name" {
  description = "The Data Collection Endpoint name"
  value       = azurerm_monitor_data_collection_endpoint.main.name
}

output "dce_logs_ingestion_endpoint" {
  description = "The Data Collection Endpoint logs ingestion endpoint"
  value       = azurerm_monitor_data_collection_endpoint.main.logs_ingestion_endpoint
}

output "dcr_name" {
  description = "The Data Collection Rule name"
  value       = azapi_resource.data_collection_rule.name
}

output "dcr_immutable_id" {
  description = "The Data Collection Rule immutable ID"
  value       = azapi_resource.data_collection_rule.output.properties.immutableId
}

output "dcr_stream_name" {
  description = "The Data Collection Rule stream name"
  value       = local.stream_name
}

output "storage_account_name" {
  description = "The Storage Account name"
  value       = azurerm_storage_account.main.name
}

output "logic_app_name" {
  description = "The Logic App name"
  value       = azurerm_logic_app_standard.main.name
}

output "logic_app_hostname" {
  description = "The Logic App default hostname"
  value       = azurerm_logic_app_standard.main.default_hostname
}

output "logic_app_principal_id" {
  description = "The Logic App managed identity principal ID"
  value       = azurerm_logic_app_standard.main.identity[0].principal_id
}

output "custom_table_name" {
  description = "The custom table name in Log Analytics"
  value       = local.custom_table_name
}

# =============================================================================
# Post-Deployment Configuration Values
# =============================================================================

output "logic_app_settings" {
  description = "App settings to configure on the Logic App after workflow deployment"
  value = {
    DCE_LOGS_INGESTION_ENDPOINT = azurerm_monitor_data_collection_endpoint.main.logs_ingestion_endpoint
    DCR_IMMUTABLE_ID            = azapi_resource.data_collection_rule.output.properties.immutableId
    DCR_STREAM_NAME             = local.stream_name
  }
}
