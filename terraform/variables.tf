# =============================================================================
# Required Variables
# =============================================================================

variable "log_analytics_workspace_name" {
  description = "Name of the existing Log Analytics workspace"
  type        = string
}

variable "log_analytics_workspace_resource_group_name" {
  description = "Resource group name where the Log Analytics workspace exists"
  type        = string
}

variable "resource_group_name" {
  description = "The resource group name for deploying new resources"
  type        = string
}

variable "location" {
  description = "Location for all resources"
  type        = string
}

# =============================================================================
# Optional Variables
# =============================================================================

variable "custom_table_name" {
  description = "Custom table name (without _CL suffix)"
  type        = string
  default     = "CognitiveServicesInventory"
}

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "cogai"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "management_group_id" {
  description = "Management group ID for cross-subscription Resource Graph queries. Leave empty for subscription-level scope."
  type        = string
  default     = ""
}

variable "retention_in_days" {
  description = "Retention time in days for the custom table"
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 4 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 4 and 730"
  }
}

variable "total_retention_in_days" {
  description = "Total retention time in days including archive for the custom table"
  type        = number
  default     = 30

  validation {
    condition     = var.total_retention_in_days >= 4 && var.total_retention_in_days <= 2556
    error_message = "total_retention_in_days must be between 4 and 2556"
  }
}
