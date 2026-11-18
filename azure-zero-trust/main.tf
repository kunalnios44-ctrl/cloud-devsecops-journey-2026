terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.106.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

variable "location" {
  type        = string
  description = "Target European region for deployment"
  default     = "North Europe"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

data "azurerm_client_config" "current" {}

# 1. Enterprise Resource Group
resource "azurerm_resource_group" "enterprise_rg" {
  name     = "rg-nordic-nexus-lab-eu"
  location = var.location

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
    Security    = "Zero-Trust"
  }
}

# 2. Hub Virtual Network, Management Subnet & Azure Firewall Subnet
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-enterprise-hub-01"
  address_space       = ["10.100.0.0/16"]
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name

  tags = {
    Environment = "Lab"
    Tier        = "Hub"
  }
}

resource "azurerm_subnet" "hub_mgmt_subnet" {
  name                 = "snet-hub-management"
  resource_group_name  = azurerm_resource_group.enterprise_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.100.1.0/24"]
}

resource "azurerm_subnet" "firewall_subnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.enterprise_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.100.2.0/24"]
}

# Hub Management NSG
resource "azurerm_network_security_group" "hub_mgmt_nsg" {
  name                = "nsg-enterprise-hub-mgmt"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name

  security_rule {
    name                       = "DenyAllInboundInternet"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllOutboundInternet"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = {
    Environment = "Lab"
  }
}

resource "azurerm_subnet_network_security_group_association" "hub_mgmt_assoc" {
  subnet_id                 = azurerm_subnet.hub_mgmt_subnet.id
  network_security_group_id = azurerm_network_security_group.hub_mgmt_nsg.id
}

# 3. Spoke Virtual Network & Subnets
resource "azurerm_virtual_network" "spoke_vnet" {
  name                = "vnet-enterprise-spoke-01"
  address_space       = ["10.200.0.0/16"]
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name

  tags = {
    Environment = "Lab"
    Tier        = "Spoke"
  }
}

resource "azurerm_subnet" "private_workload_subnet" {
  name                 = "snet-private-workloads"
  resource_group_name  = azurerm_resource_group.enterprise_rg.name
  virtual_network_name = azurerm_virtual_network.spoke_vnet.name
  address_prefixes     = ["10.200.1.0/24"]
}

resource "azurerm_subnet" "private_endpoint_subnet" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.enterprise_rg.name
  virtual_network_name              = azurerm_virtual_network.spoke_vnet.name
  address_prefixes                  = ["10.200.2.0/24"]
  private_endpoint_network_policies = "Enabled"
}

# 4. Hub-and-Spoke Bi-Directional VNet Peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = azurerm_resource_group.enterprise_rg.name
  virtual_network_name      = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_vnet.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = azurerm_resource_group.enterprise_rg.name
  virtual_network_name      = azurerm_virtual_network.spoke_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
  allow_forwarded_traffic   = true
}

# 5. Central Azure Firewall & Policy
resource "azurerm_public_ip" "fw_pip" {
  name                = "pip-hub-firewall"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall_policy" "hub_fw_policy" {
  name                = "fwpol-enterprise-hub-01"
  resource_group_name = azurerm_resource_group.enterprise_rg.name
  location            = azurerm_resource_group.enterprise_rg.location
  sku                 = "Standard"

  intrusion_detection {
    mode = "Deny"
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "hub_fw_rcg" {
  name               = "rcg-enterprise-egress"
  firewall_policy_id = azurerm_firewall_policy.hub_fw_policy.id
  priority           = 100

  network_rule_collection {
    name     = "nrc-allow-azure-control-plane"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "AllowEntraID"
      protocols             = ["TCP"]
      source_addresses      = ["10.200.1.0/24"]
      destination_addresses = ["AzureActiveDirectory"]
      destination_ports     = ["443"]
    }
  }
}

resource "azurerm_firewall" "hub_fw" {
  name                = "fw-hub-enterprise-01"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  threat_intel_mode   = "Deny"
  firewall_policy_id  = azurerm_firewall_policy.hub_fw_policy.id

  ip_configuration {
    name                 = "firewall-ip-config"
    subnet_id            = azurerm_subnet.firewall_subnet.id
    public_ip_address_id = azurerm_public_ip.fw_pip.id
  }

  tags = {
    Environment = "Lab"
  }
}

# 6. Spoke User-Defined Route Table (UDR)
resource "azurerm_route_table" "spoke_udr" {
  name                          = "rt-spoke-governance"
  location                      = azurerm_resource_group.enterprise_rg.location
  resource_group_name           = azurerm_resource_group.enterprise_rg.name
  disable_bgp_route_propagation = false

  route {
    name                   = "RouteToHubFirewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub_fw.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "workload_udr_assoc" {
  subnet_id      = azurerm_subnet.private_workload_subnet.id
  route_table_id = azurerm_route_table.spoke_udr.id
}

# 7. Dedicated Hardened Workload NSG
resource "azurerm_network_security_group" "workload_nsg" {
  name                = "nsg-enterprise-workloads"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name

  security_rule {
    name                       = "DenyAllInboundInternet"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInboundVNet"
    priority                   = 4090
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowOutboundKeyVaultPrivateEndpoint"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.200.1.0/24"
    destination_address_prefix = "10.200.2.0/24"
  }

  security_rule {
    name                       = "AllowOutboundToHubVNet"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.200.1.0/24"
    destination_address_prefix = "10.100.0.0/16"
  }

  security_rule {
    name                       = "AllowOutboundIMDS"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.200.1.0/24"
    destination_address_prefix = "169.254.169.254/32"
  }

  tags = {
    Environment = "Lab"
  }
}

# 8. Dedicated Hardened PE NSG
resource "azurerm_network_security_group" "pe_nsg" {
  name                = "nsg-enterprise-private-endpoints"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name

  security_rule {
    name                       = "DenyAllInboundInternet"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInboundVNet"
    priority                   = 4090
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowInboundWorkloadToKeyVaultPE"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.200.1.0/24"
    destination_address_prefix = "10.200.2.0/24"
  }

  security_rule {
    name                       = "AllowInboundHubManagementToKeyVaultPE"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.100.1.0/24"
    destination_address_prefix = "10.200.2.0/24"
  }

  security_rule {
    name                       = "DenyAllOutboundInternet"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "DenyAllOutboundVNet"
    priority                   = 4090
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = {
    Environment = "Lab"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload_nsg_assoc" {
  subnet_id                 = azurerm_subnet.private_workload_subnet.id
  network_security_group_id = azurerm_network_security_group.workload_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "pe_nsg_assoc" {
  subnet_id                 = azurerm_subnet.private_endpoint_subnet.id
  network_security_group_id = azurerm_network_security_group.pe_nsg.id
}

# 9. Log Analytics Workspace & Diagnostics
resource "azurerm_log_analytics_workspace" "enterprise_law" {
  name                = "law-kunal-enterprise-logs-${random_string.suffix.result}"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
}

resource "azurerm_monitor_diagnostic_setting" "hub_mgmt_nsg_diag" {
  name                       = "diag-hub-mgmt-nsg"
  target_resource_id         = azurerm_network_security_group.hub_mgmt_nsg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.enterprise_law.id

  enabled_log { category = "NetworkSecurityGroupEvent" }
  enabled_log { category = "NetworkSecurityGroupRuleCounter" }
}

resource "azurerm_monitor_diagnostic_setting" "workload_nsg_diag" {
  name                       = "diag-workload-nsg"
  target_resource_id         = azurerm_network_security_group.workload_nsg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.enterprise_law.id

  enabled_log { category = "NetworkSecurityGroupEvent" }
  enabled_log { category = "NetworkSecurityGroupRuleCounter" }
}

resource "azurerm_monitor_diagnostic_setting" "pe_nsg_diag" {
  name                       = "diag-pe-nsg"
  target_resource_id         = azurerm_network_security_group.pe_nsg.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.enterprise_law.id

  enabled_log { category = "NetworkSecurityGroupEvent" }
  enabled_log { category = "NetworkSecurityGroupRuleCounter" }
}

resource "azurerm_monitor_diagnostic_setting" "fw_diag" {
  name                       = "diag-hub-firewall"
  target_resource_id         = azurerm_firewall.hub_fw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.enterprise_law.id

  enabled_log { category = "AZFWNetworkRule" }
  enabled_log { category = "AZFWApplicationRule" }
  enabled_log { category = "AZFWThreatIntel" }
  metric { category = "AllMetrics" }
}

# 10. Workload Managed Identity
resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = "id-enterprise-workload-app"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name
}

# 11. Enterprise Azure Key Vault (Hardened & Lifecycle Protected)
resource "azurerm_key_vault" "enterprise_kv" {
  name                          = "kv-kunal-sec-${random_string.suffix.result}"
  location                      = azurerm_resource_group.enterprise_rg.location
  resource_group_name           = azurerm_resource_group.enterprise_rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium"
  enabled_for_disk_encryption   = true
  soft_delete_retention_days    = 90
  purge_protection_enabled      = true
  public_network_access_enabled = false
  enable_rbac_authorization     = true

  network_acls {
    default_action = "Deny"
    bypass         = "None"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Compliance = "CIS-Hardened"
  }
}

resource "azurerm_monitor_diagnostic_setting" "kv_diag" {
  name                       = "diag-keyvault-audit"
  target_resource_id         = azurerm_key_vault.enterprise_kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.enterprise_law.id

  enabled_log { category = "AuditEvent" }
  metric { category = "AllMetrics" }
}

# 12. Private DNS Zone & Links for Hub & Spoke VNets
resource "azurerm_private_dns_zone" "kv_dns_zone" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.enterprise_rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub_dns_link" {
  name                  = "hub-vnet-dns-link"
  resource_group_name   = azurerm_resource_group.enterprise_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.kv_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.hub_vnet.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke_dns_link" {
  name                  = "spoke-vnet-dns-link"
  resource_group_name   = azurerm_resource_group.enterprise_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.kv_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.spoke_vnet.id
}

# 13. Key Vault Private Endpoint
resource "azurerm_private_endpoint" "kv_private_endpoint" {
  name                = "pe-keyvault-secure"
  location            = azurerm_resource_group.enterprise_rg.location
  resource_group_name = azurerm_resource_group.enterprise_rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "psc-keyvault-connection"
    private_connection_resource_id = azurerm_key_vault.enterprise_kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "kv-private-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv_dns_zone.id]
  }
}

# 14. RBAC Role Assignment
resource "azurerm_role_assignment" "kv_secrets_access" {
  scope                = azurerm_key_vault.enterprise_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
}

# --- OUTPUTS ---
output "resource_group_name" {
  value = azurerm_resource_group.enterprise_rg.name
}

output "hub_vnet_name" {
  value = azurerm_virtual_network.hub_vnet.name
}

output "spoke_vnet_name" {
  value = azurerm_virtual_network.spoke_vnet.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.enterprise_kv.vault_uri
}

output "workload_managed_identity_id" {
  value = azurerm_user_assigned_identity.workload_identity.id
}

output "hub_firewall_private_ip" {
  value = azurerm_firewall.hub_fw.ip_configuration[0].private_ip_address
}
