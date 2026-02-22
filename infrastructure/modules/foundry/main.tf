# ── Microsoft Foundry v2 Module ──────────────────────────────────────────────
# Uses AzAPI provider for latest Foundry resource types
# Creates: AI Services account, project, model deployment, capability hosts,
#          dependent resources (CosmosDB, AI Search, Storage), and RBAC

variable "project_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "subnet_private_endpoints_id" {
  type = string
}

variable "dns_zone_cognitive_id" {
  type = string
}

variable "dns_zone_openai_id" {
  type = string
}

variable "model_name" {
  type    = string
  default = "gpt-4.1"
}

variable "model_format" {
  type    = string
  default = "OpenAI"
}

variable "model_version" {
  type    = string
  default = "2025-04-14"
}

variable "model_sku" {
  type    = string
  default = "GlobalStandard"
}

variable "model_capacity" {
  type    = number
  default = 40
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ── Unique Suffix ────────────────────────────────────────────────────────────

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix       = random_string.suffix.result
  account_name = "foundry${var.project_name}${local.suffix}"
  project_name = "proj${var.project_name}${local.suffix}"
}

# ── Dependent Resources ──────────────────────────────────────────────────────

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${local.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  local_authentication_disabled = true

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = var.tags
}

resource "azurerm_search_service" "main" {
  name                = "search-${var.project_name}-${local.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "standard"

  identity {
    type = "SystemAssigned"
  }

  local_authentication_enabled = false
  authentication_failure_mode  = "http401WithBearerChallenge"

  tags = var.tags
}

resource "azurerm_storage_account" "main" {
  name                     = "st${var.project_name}${local.suffix}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

# ── AI Services Account (Foundry v2) ────────────────────────────────────────

resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.account_name
  location  = var.location
  parent_id = var.resource_group_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.account_name
      publicNetworkAccess    = "Disabled"
      disableLocalAuth       = true
      networkAcls = {
        defaultAction = "Deny"
      }
    }
  }

  tags = var.tags
}

# ── Private Endpoint for AI Services ────────────────────────────────────────

resource "azurerm_private_endpoint" "ai_account" {
  name                = "pe-${local.account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-cognitive"
    private_connection_resource_id = azapi_resource.ai_account.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name                 = "dns-zone-group-cognitive"
    private_dns_zone_ids = [var.dns_zone_cognitive_id, var.dns_zone_openai_id]
  }
}

# ── Model Deployment ─────────────────────────────────────────────────────────

resource "azapi_resource" "model_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name      = var.model_name
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = var.model_sku
      capacity = var.model_capacity
    }
    properties = {
      model = {
        name    = var.model_name
        format  = var.model_format
        version = var.model_version
      }
    }
  }
}

# ── Foundry Project ──────────────────────────────────────────────────────────

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = local.project_name
  location  = var.location
  parent_id = azapi_resource.ai_account.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = "Hello World starter project"
      displayName = "Hello World Project"
    }
  }

  depends_on = [azapi_resource.model_deployment]
}

# ── Project Connections ──────────────────────────────────────────────────────

resource "azapi_resource" "connection_cosmosdb" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = azurerm_cosmosdb_account.main.name
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category = "CosmosDB"
      target   = azurerm_cosmosdb_account.main.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.main.id
        location   = azurerm_cosmosdb_account.main.location
      }
    }
  }
}

resource "azapi_resource" "connection_storage" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = azurerm_storage_account.main.name
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = azurerm_storage_account.main.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.main.id
        location   = azurerm_storage_account.main.location
      }
    }
  }
}

resource "azapi_resource" "connection_search" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = azurerm_search_service.main.name
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azurerm_search_service.main.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_search_service.main.id
        location   = azurerm_search_service.main.location
      }
    }
  }
}

# ── Capability Hosts ─────────────────────────────────────────────────────────

resource "azapi_resource" "account_capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview"
  name      = "caphostacc"
  parent_id = azapi_resource.ai_account.id

  body = {
    properties = {
      capabilityHostKind = "Agents"
    }
  }

  depends_on = [
    azapi_resource.connection_cosmosdb,
    azapi_resource.connection_storage,
    azapi_resource.connection_search,
  ]
}

resource "azapi_resource" "project_capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "caphostproj"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [azurerm_search_service.main.name]
      storageConnections       = [azurerm_storage_account.main.name]
      threadStorageConnections = [azurerm_cosmosdb_account.main.name]
    }
  }

  depends_on = [azapi_resource.account_capability_host]
}

# ── RBAC Role Assignments ───────────────────────────────────────────────────

# Project SMI → Storage Blob Data Contributor
resource "azurerm_role_assignment" "project_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.project.identity[0].principal_id
}

# Project SMI → Cosmos DB Operator (account level)
resource "azurerm_role_assignment" "project_cosmos_operator" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.project.identity[0].principal_id
}

# Project SMI → Search Index Data Contributor
resource "azurerm_role_assignment" "project_search_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.project.identity[0].principal_id
}

# Project SMI → Search Service Contributor
resource "azurerm_role_assignment" "project_search_service" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.project.identity[0].principal_id
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "ai_account_id" {
  value = azapi_resource.ai_account.id
}

output "ai_account_name" {
  value = azapi_resource.ai_account.name
}

output "project_id" {
  value = azapi_resource.project.id
}

output "project_name" {
  value = azapi_resource.project.name
}
