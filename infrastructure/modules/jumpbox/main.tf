# ── Jumpbox Module ───────────────────────────────────────────────────────────
# Azure Bastion + Windows VM for accessing private resources (e.g., Foundry portal)

variable "project_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_bastion_id" {
  type = string
}

variable "subnet_jumpbox_id" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "key_vault_id" {
  type = string
}

# ── Bastion ──────────────────────────────────────────────────────────────────

resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.project_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "main" {
  name                = "bastion-${var.project_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tunneling_enabled   = true
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = var.subnet_bastion_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# ── Jumpbox VM ───────────────────────────────────────────────────────────────

resource "random_password" "jumpbox" {
  length  = 24
  special = true
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "nic-jumpbox-${var.project_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_jumpbox_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "jumpbox" {
  name                = "vm-jb-${substr(var.project_name, 0, 8)}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = random_password.jumpbox.result
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.jumpbox.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-pro"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# ── Store Admin Password in Key Vault ─────────────────────────────────────────

resource "azurerm_key_vault_secret" "jumpbox_password" {
  name         = "jumpbox-admin-password"
  value        = random_password.jumpbox.result
  key_vault_id = var.key_vault_id
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "bastion_name" {
  value = azurerm_bastion_host.main.name
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.jumpbox.name
}

output "vm_private_ip" {
  value = azurerm_network_interface.jumpbox.private_ip_address
}
