# ── Microsoft Foundry Module ─────────────────────────────────────────────────
# Uses AzAPI provider for Foundry resource types
# Based on: microsoft-foundry/foundry-samples Bicep sample
#   infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup
#
# Creates: AI Services account, project, model deployment, project capability host,
#          dependent resources (CosmosDB, AI Search, Storage), private endpoints,
#          RBAC (ARM + data-plane), and post-caphost container-level roles.

terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

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

variable "subnet_agent_id" {
  type = string
}

variable "dns_zone_cognitive_id" {
  type = string
}

variable "dns_zone_openai_id" {
  type = string
}

variable "dns_zone_services_ai_id" {
  type = string
}

variable "dns_zone_search_id" {
  type = string
}

variable "dns_zone_blob_id" {
  type = string
}

variable "dns_zone_cosmosdb_id" {
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
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "suffix" {
  type = string
}

locals {
  suffix       = var.suffix
  account_name = "foundry${var.project_name}${local.suffix}"
  project_name = "proj${var.project_name}${local.suffix}"

  # Format the project internalId (hex string) as a GUID for CosmosDB/Storage scoping
  project_id_guid = "${substr(azapi_resource.project.output.properties.internalId, 0, 8)}-${substr(azapi_resource.project.output.properties.internalId, 8, 4)}-${substr(azapi_resource.project.output.properties.internalId, 12, 4)}-${substr(azapi_resource.project.output.properties.internalId, 16, 4)}-${substr(azapi_resource.project.output.properties.internalId, 20, 12)}"
}

# ══════════════════════════════════════════════════════════════════════════════
# Dependent Resources
# Mirrors: modules-network-secured/standard-dependent-resources.bicep
# ══════════════════════════════════════════════════════════════════════════════

resource "azurerm_storage_account" "main" {
  name                     = "st${var.project_name}${local.suffix}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${local.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  free_tier_enabled   = false

  local_authentication_disabled    = true
  public_network_access_enabled    = false
  automatic_failover_enabled       = false
  multiple_write_locations_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }

  tags = var.tags
}

# AI Search via AzAPI to match Bicep's property set exactly
resource "azapi_resource" "ai_search" {
  type                      = "Microsoft.Search/searchServices@2024-06-01-preview"
  name                      = "search-${var.project_name}-${local.suffix}"
  parent_id                 = var.resource_group_id
  location                  = var.location
  schema_validation_enabled = true

  body = {
    sku = {
      name = "standard"
    }
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      replicaCount   = 1
      partitionCount = 1
      hostingMode    = "default"
      semanticSearch = "disabled"

      # Bicep 15 uses disableLocalAuth: false with AAD-or-ApiKey fallback
      disableLocalAuth = false
      authOptions = {
        aadOrApiKey = {
          aadAuthFailureMode = "http401WithBearerChallenge"
        }
      }

      publicNetworkAccess = "disabled"
      networkRuleSet = {
        bypass  = "None"
        ipRules = []
      }
    }
  }

  tags = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# AI Services Account (Foundry)
# Mirrors: modules-network-secured/ai-account-identity.bicep
# ══════════════════════════════════════════════════════════════════════════════

resource "azapi_resource" "ai_account" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name                      = local.account_name
  location                  = var.location
  parent_id                 = var.resource_group_id
  schema_validation_enabled = false

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

      # Agent service requires API key auth internally
      disableLocalAuth = false

      # Private networking — Deny + bypass AzureServices (matches Bicep 15)
      publicNetworkAccess = "Disabled"
      networkAcls = {
        defaultAction      = "Deny"
        bypass              = "AzureServices"
        virtualNetworkRules = []
        ipRules             = []
      }

      # VNet injection for Standard Agents (BYO VNet)
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = var.subnet_agent_id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  tags = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# Private Endpoints + DNS
# Mirrors: modules-network-secured/private-endpoint-and-dns.bicep
# ══════════════════════════════════════════════════════════════════════════════

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${azurerm_storage_account.main.name}-private-endpoint"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id
  tags                = var.tags

  private_service_connection {
    name                           = "${azurerm_storage_account.main.name}-private-link-service-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "${azurerm_storage_account.main.name}-dns-config"
    private_dns_zone_ids = [var.dns_zone_blob_id]
  }
}

resource "azurerm_private_endpoint" "cosmosdb" {
  name                = "${azurerm_cosmosdb_account.main.name}-private-endpoint"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id
  tags                = var.tags

  private_service_connection {
    name                           = "${azurerm_cosmosdb_account.main.name}-private-link-service-connection"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "${azurerm_cosmosdb_account.main.name}-dns-config"
    private_dns_zone_ids = [var.dns_zone_cosmosdb_id]
  }
}

resource "azurerm_private_endpoint" "search" {
  name                = "${azapi_resource.ai_search.name}-private-endpoint"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id
  tags                = var.tags

  private_service_connection {
    name                           = "${azapi_resource.ai_search.name}-private-link-service-connection"
    private_connection_resource_id = azapi_resource.ai_search.id
    is_manual_connection           = false
    subresource_names              = ["searchService"]
  }

  private_dns_zone_group {
    name                 = "${azapi_resource.ai_search.name}-dns-config"
    private_dns_zone_ids = [var.dns_zone_search_id]
  }
}

resource "azurerm_private_endpoint" "ai_account" {
  name                = "${local.account_name}-private-endpoint"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_private_endpoints_id
  tags                = var.tags

  private_service_connection {
    name                           = "${local.account_name}-private-link-service-connection"
    private_connection_resource_id = azapi_resource.ai_account.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name = "${local.account_name}-dns-config"
    private_dns_zone_ids = [
      var.dns_zone_cognitive_id,
      var.dns_zone_services_ai_id,
      var.dns_zone_openai_id,
    ]
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Model Deployment
# ══════════════════════════════════════════════════════════════════════════════

resource "azurerm_cognitive_deployment" "model" {
  name                 = var.model_name
  cognitive_account_id = azapi_resource.ai_account.id

  depends_on = [azapi_resource.ai_account]

  sku {
    name     = var.model_sku
    capacity = var.model_capacity
  }

  model {
    format  = var.model_format
    name    = var.model_name
    version = var.model_version
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Foundry Project
# Mirrors: modules-network-secured/ai-project-identity.bicep
# Must wait for all private endpoints to be established first
# ══════════════════════════════════════════════════════════════════════════════

resource "azapi_resource" "project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name                      = local.project_name
  location                  = var.location
  parent_id                 = azapi_resource.ai_account.id
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = "Hello World starter project"
      displayName = "Hello World Project"
    }
  }

  response_export_values = [
    "identity.principalId",
    "properties.internalId",
  ]

  depends_on = [
    azurerm_cognitive_deployment.model,
    azurerm_private_endpoint.storage_blob,
    azurerm_private_endpoint.cosmosdb,
    azurerm_private_endpoint.search,
    azurerm_private_endpoint.ai_account,
  ]
}

# Wait for project SMI to replicate through Entra ID
resource "time_sleep" "wait_project_identity" {
  depends_on      = [azapi_resource.project]
  create_duration = "10s"
}

# ══════════════════════════════════════════════════════════════════════════════
# Project Connections
# Mirrors: ai-project-identity.bicep connection sub-resources
# ══════════════════════════════════════════════════════════════════════════════

resource "azapi_resource" "connection_cosmosdb" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = azurerm_cosmosdb_account.main.name
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  depends_on = [azapi_resource.project]

  body = {
    name = azurerm_cosmosdb_account.main.name
    properties = {
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.main.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.main.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "connection_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = azurerm_storage_account.main.name
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  depends_on = [azapi_resource.project]

  body = {
    name = azurerm_storage_account.main.name
    properties = {
      category = "AzureStorageAccount"
      target   = azurerm_storage_account.main.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.main.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "connection_search" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = azapi_resource.ai_search.name
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  depends_on = [azapi_resource.project]

  body = {
    name = azapi_resource.ai_search.name
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azapi_resource.ai_search.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.ai_search.id
        location   = var.location
      }
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# ARM-level RBAC Role Assignments (pre-caphost)
# Mirrors: azure-storage-account-role-assignment.bicep,
#          cosmosdb-account-role-assignment.bicep,
#          ai-search-role-assignments.bicep
# These must complete + propagate BEFORE the capability host is created.
# ══════════════════════════════════════════════════════════════════════════════

resource "azurerm_role_assignment" "project_storage_blob" {
  depends_on           = [time_sleep.wait_project_identity]
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.project.output.identity.principalId
}

resource "azurerm_role_assignment" "project_cosmos_operator" {
  depends_on           = [time_sleep.wait_project_identity]
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.project.output.identity.principalId
}

resource "azurerm_role_assignment" "project_search_index" {
  depends_on           = [time_sleep.wait_project_identity]
  scope                = azapi_resource.ai_search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.project.output.identity.principalId
}

resource "azurerm_role_assignment" "project_search_service" {
  depends_on           = [time_sleep.wait_project_identity]
  scope                = azapi_resource.ai_search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.project.output.identity.principalId
}

# Wait 60s for RBAC assignments to propagate before capability host creation
resource "time_sleep" "wait_rbac" {
  depends_on = [
    azurerm_role_assignment.project_storage_blob,
    azurerm_role_assignment.project_cosmos_operator,
    azurerm_role_assignment.project_search_index,
    azurerm_role_assignment.project_search_service,
  ]
  create_duration = "60s"
}

# ══════════════════════════════════════════════════════════════════════════════
# Project Capability Host
# Mirrors: modules-network-secured/add-project-capability-host.bicep
# Only the project-level capability host (no account-level one in Bicep 15).
# Uses 2025-04-01-preview API version (matches Bicep exactly).
# ══════════════════════════════════════════════════════════════════════════════

resource "azapi_resource" "project_capability_host" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = "caphostproj"
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [azapi_resource.ai_search.name]
      storageConnections       = [azurerm_storage_account.main.name]
      threadStorageConnections = [azurerm_cosmosdb_account.main.name]
    }
  }

  depends_on = [
    azapi_resource.connection_cosmosdb,
    azapi_resource.connection_storage,
    azapi_resource.connection_search,
    time_sleep.wait_rbac,
  ]
}

# ══════════════════════════════════════════════════════════════════════════════
# Post-CapHost: CosmosDB Data-Plane Role Assignment
# Mirrors: modules-network-secured/cosmos-container-role-assignments.bicep
# Scoped to the enterprise_memory database (created by capability host)
# ══════════════════════════════════════════════════════════════════════════════

resource "azurerm_cosmosdb_sql_role_assignment" "project_enterprise_memory" {
  depends_on          = [azapi_resource.project_capability_host]
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  scope               = "${azurerm_cosmosdb_account.main.id}/dbs/enterprise_memory"
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.project.output.identity.principalId
}

# ══════════════════════════════════════════════════════════════════════════════
# Post-CapHost: Storage Blob Data Owner (ABAC-scoped)
# Mirrors: modules-network-secured/blob-storage-container-role-assignments.bicep
# Scoped to the agent blob container created by the capability host
# ══════════════════════════════════════════════════════════════════════════════

resource "azurerm_role_assignment" "project_storage_blob_owner" {
  depends_on           = [azapi_resource.project_capability_host]
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.project.output.identity.principalId
  condition_version    = "2.0"
  condition            = <<-EOT
  ((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})  AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'}) AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.project_id_guid}' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent'))
  EOT
}

# ══════════════════════════════════════════════════════════════════════════════
# Outputs
# ══════════════════════════════════════════════════════════════════════════════

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
