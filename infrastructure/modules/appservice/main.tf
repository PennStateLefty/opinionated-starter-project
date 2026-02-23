# ── App Service Module ───────────────────────────────────────────────────────
# Linux container, VNet integration, staging deployment slot

variable "project_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_appservice_id" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ── App Service Plan ─────────────────────────────────────────────────────────

resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "S1"
  tags                = var.tags
}

# ── Web App ──────────────────────────────────────────────────────────────────

resource "azurerm_linux_web_app" "main" {
  name                = "app-${var.project_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    container_registry_use_managed_identity = true

    application_stack {
      docker_registry_url = "https://${var.acr_login_server}"
      docker_image_name   = "hello-world:latest"
    }
  }

  app_settings = {
    "WEBSITES_PORT" = "8000"
  }

  virtual_network_subnet_id = var.subnet_appservice_id
  tags                      = var.tags
}

# ── Staging Deployment Slot ──────────────────────────────────────────────────

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    container_registry_use_managed_identity = true

    application_stack {
      docker_registry_url = "https://${var.acr_login_server}"
      docker_image_name   = "hello-world:latest"
    }
  }

  app_settings = {
    "WEBSITES_PORT" = "8000"
  }

  tags = var.tags
}

# ── RBAC: App Service → ACR Pull ────────────────────────────────────────────

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "slot_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging.identity[0].principal_id
}

# ── RBAC: App Service → Key Vault Secrets User ──────────────────────────────

resource "azurerm_role_assignment" "app_kv_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "app_service_id" {
  value = azurerm_linux_web_app.main.id
}

output "app_service_name" {
  value = azurerm_linux_web_app.main.name
}

output "app_service_default_hostname" {
  value = azurerm_linux_web_app.main.default_hostname
}

output "app_service_principal_id" {
  value = azurerm_linux_web_app.main.identity[0].principal_id
}

output "staging_slot_name" {
  value = azurerm_linux_web_app_slot.staging.name
}

output "staging_slot_hostname" {
  value = azurerm_linux_web_app_slot.staging.default_hostname
}
