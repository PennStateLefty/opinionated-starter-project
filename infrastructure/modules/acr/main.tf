# ── Azure Container Registry Module ──────────────────────────────────────────
# Public access enabled (no private endpoint) — allows GitHub Actions to push

variable "project_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "suffix" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_registry" "main" {
  name                = replace("acr${var.project_name}${var.suffix}", "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  admin_enabled       = false

  tags = var.tags
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}
