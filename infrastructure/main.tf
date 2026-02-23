# ── Root Module ───────────────────────────────────────────────────────────────

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
  tags = {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ── Networking ───────────────────────────────────────────────────────────────

module "networking" {
  source = "./modules/networking"

  project_name                    = var.project_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  vnet_address_space              = var.vnet_address_space
  subnet_appservice_prefix        = var.subnet_appservice_prefix
  subnet_private_endpoints_prefix = var.subnet_private_endpoints_prefix
  subnet_foundry_prefix           = var.subnet_foundry_prefix
  subnet_bastion_prefix           = var.subnet_bastion_prefix
  subnet_jumpbox_prefix           = var.subnet_jumpbox_prefix
  tags                            = local.tags
}

# ── Azure Container Registry ────────────────────────────────────────────────

module "acr" {
  source = "./modules/acr"

  project_name        = var.project_name
  suffix              = local.suffix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

# ── Key Vault ────────────────────────────────────────────────────────────────

module "keyvault" {
  source = "./modules/keyvault"

  project_name                = var.project_name
  suffix                      = local.suffix
  location                    = var.location
  resource_group_name         = azurerm_resource_group.main.name
  subnet_private_endpoints_id = module.networking.subnet_private_endpoints_id
  dns_zone_keyvault_id        = module.networking.dns_zone_keyvault_id
  deployer_ip                 = var.deployer_ip
  tags                        = local.tags
}

# ── App Service ──────────────────────────────────────────────────────────────

module "appservice" {
  source = "./modules/appservice"

  project_name         = var.project_name
  location             = var.location
  resource_group_name  = azurerm_resource_group.main.name
  subnet_appservice_id = module.networking.subnet_appservice_id
  acr_id               = module.acr.acr_id
  acr_login_server     = module.acr.acr_login_server
  key_vault_id         = module.keyvault.key_vault_id
  tags                 = local.tags
}

# ── Microsoft Foundry v2 ────────────────────────────────────────────────────

module "foundry" {
  source = "./modules/foundry"

  project_name                = var.project_name
  suffix                      = local.suffix
  location                    = var.location
  resource_group_name         = azurerm_resource_group.main.name
  resource_group_id           = azurerm_resource_group.main.id
  subnet_private_endpoints_id = module.networking.subnet_private_endpoints_id
  dns_zone_cognitive_id       = module.networking.dns_zone_cognitive_id
  dns_zone_openai_id          = module.networking.dns_zone_openai_id
  dns_zone_services_ai_id     = module.networking.dns_zone_services_ai_id
  dns_zone_search_id          = module.networking.dns_zone_search_id
  dns_zone_blob_id            = module.networking.dns_zone_blob_id
  dns_zone_cosmosdb_id        = module.networking.dns_zone_cosmosdb_id
  model_name                  = var.foundry_model_name
  model_format                = var.foundry_model_format
  model_version               = var.foundry_model_version
  model_sku                   = var.foundry_model_sku
  model_capacity              = var.foundry_model_capacity
  tags                        = local.tags
}

# ── Jumpbox + Bastion ───────────────────────────────────────────────────────

module "jumpbox" {
  source = "./modules/jumpbox"

  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_bastion_id   = module.networking.subnet_bastion_id
  subnet_jumpbox_id   = module.networking.subnet_jumpbox_id
  key_vault_id        = module.keyvault.key_vault_id
  tags                = local.tags

  depends_on = [module.keyvault]
}
