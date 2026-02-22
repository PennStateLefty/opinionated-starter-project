# ── Outputs ──────────────────────────────────────────────────────────────────

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "Azure Container Registry login server"
  value       = module.acr.acr_login_server
}

output "acr_name" {
  description = "Azure Container Registry name"
  value       = module.acr.acr_name
}

output "app_service_url" {
  description = "App Service default URL"
  value       = "https://${module.appservice.app_service_default_hostname}"
}

output "app_service_name" {
  description = "App Service name"
  value       = module.appservice.app_service_name
}

output "staging_slot_url" {
  description = "Staging deployment slot URL"
  value       = "https://${module.appservice.staging_slot_hostname}"
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.keyvault.key_vault_uri
}

output "foundry_account_name" {
  description = "Microsoft Foundry AI Services account name"
  value       = module.foundry.ai_account_name
}

output "foundry_project_name" {
  description = "Microsoft Foundry project name"
  value       = module.foundry.project_name
}
