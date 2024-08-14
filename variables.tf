variable "resource_group_name_prefix" {
  description = "Prefix for the resource group name"
  type        = string
  default     = "rg"
}

variable "vm_resource_group" {
  description = "Location for the resource group"
  type        = string
  default     = "East US"
}

variable "username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureadmin"
}

variable "admin_ssh_key" {
  description = "SSH public key for the VM"
  type        = string
}

variable "storage_account_name" {
  description = "The name of the storage account"
  type        = string
}

variable "location" {
  description = "Location for resources"
  type        = string
}

variable "account_tier" {
  description = "The tier of the storage account"
  type        = string
}

variable "account_replication_type" {
  description = "The replication type of the storage account"
  type        = string
}

# tflint-ignore: terraform_variable_separate, terraform_output_separate, terraform_standard_module_structure
variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see https://aka.ms/avm/telemetryinfo.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
}
