variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westus3"
}

variable "environment" {
  description = "Environment tag (e.g., development, staging, production)"
  type        = string
  default     = "development"
}

variable "project_name" {
  description = "Base name used for resource naming"
  type        = string
  default     = "helloworld"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_appservice_prefix" {
  description = "CIDR prefix for the App Service integration subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_private_endpoints_prefix" {
  description = "CIDR prefix for the private endpoints subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_foundry_prefix" {
  description = "CIDR prefix for the Foundry services subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "subnet_bastion_prefix" {
  description = "CIDR prefix for the Azure Bastion subnet"
  type        = string
  default     = "10.0.4.0/26"
}

variable "subnet_jumpbox_prefix" {
  description = "CIDR prefix for the jumpbox VM subnet"
  type        = string
  default     = "10.0.5.0/24"
}

# ── Foundry Model Deployment ─────────────────────────────────────────────────

variable "foundry_model_name" {
  description = "Name of the AI model to deploy"
  type        = string
  default     = "gpt-4.1"
}

variable "foundry_model_format" {
  description = "Model provider format"
  type        = string
  default     = "OpenAI"
}

variable "foundry_model_version" {
  description = "Model version"
  type        = string
  default     = "2025-04-14"
}

variable "foundry_model_sku" {
  description = "Model deployment SKU"
  type        = string
  default     = "GlobalStandard"
}

variable "foundry_model_capacity" {
  description = "Tokens per minute (TPM) for model deployment"
  type        = number
  default     = 40
}
