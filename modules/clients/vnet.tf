#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------
locals {
  enabled_interfaces = {
    for intf, subnet in var.azurerm_network_config.subnets :
    intf => subnet if subnet != null && startswith(intf, "ge")
  }
  public_overlay_interfaces = {
    for intf, subnet in local.enabled_interfaces : intf => subnet if subnet.overlay == "public"
  }
  private_overlay_interfaces = {
    for intf, subnet in local.enabled_interfaces : intf => subnet if subnet.overlay == "private"
  }
  non_overlay_interfaces = setsubtract(keys(local.enabled_interfaces), keys(merge(local.public_overlay_interfaces, local.private_overlay_interfaces)))
  lan_interfaces         = length(local.non_overlay_interfaces) != 0 ? local.non_overlay_interfaces : keys(local.private_overlay_interfaces)

  virtual_appliance_ip = length(local.lan_interfaces) > 0 ? var.netskope_gateway_config.gateway_data.primary.interfaces[tolist(local.lan_interfaces)[0]].private_ip_address : "0.0.0.0"

  netskope_tags = {
    netskope_tenant_id = var.netskope_tenant.tenant_id
  }

  client_security_rules = {
    all = {
      name                       = "Allow_All"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefixes    = ["0.0.0.0/0"]
      destination_address_prefix = "*"
    }
  }

  use_remote_gateway = (var.azurerm_route_server.create_route_server || var.azurerm_route_server.route_server_id != null) && length(local.lan_interfaces) > 0 ? true : false
}



resource "azurerm_virtual_network" "client" {
  name                = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  location            = var.azurerm_network_config.location
  resource_group_name = var.azurerm_network_config.vnet_rg_name
  address_space       = [var.clients.vnet_cidr]
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_subnet" "client" {
  name                 = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  resource_group_name  = var.azurerm_network_config.vnet_rg_name
  virtual_network_name = azurerm_virtual_network.client.name
  address_prefixes     = [var.clients.vnet_cidr]
}

resource "azurerm_network_security_group" "client" {
  name                = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  location            = var.azurerm_network_config.location
  resource_group_name = var.azurerm_network_config.vnet_rg_name
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_network_security_rule" "client" {
  for_each                    = local.client_security_rules
  name                        = each.value.name
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = var.azurerm_network_config.vnet_rg_name
  network_security_group_name = azurerm_network_security_group.client.name
}

resource "azurerm_subnet_network_security_group_association" "client" {
  subnet_id                 = azurerm_subnet.client.id
  network_security_group_id = azurerm_network_security_group.client.id
}

resource "azurerm_route_table" "client" {
  name                = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  location            = var.azurerm_network_config.location
  resource_group_name = var.azurerm_network_config.vnet_rg_name

  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_subnet_route_table_association" "client" {
  subnet_id      = azurerm_subnet.client.id
  route_table_id = azurerm_route_table.client.id
}

resource "azurerm_virtual_network_peering" "client_nsg" {
  name                      = join("-", ["client", "nsg", var.netskope_tenant.tenant_id])
  resource_group_name       = var.azurerm_network_config.vnet_rg_name
  virtual_network_name      = azurerm_virtual_network.client.name
  use_remote_gateways       = local.use_remote_gateway
  allow_forwarded_traffic   = true
  remote_virtual_network_id = var.azurerm_network_config.vnet_object.id
}

resource "azurerm_virtual_network_peering" "nsg_client" {
  name                      = join("-", ["nsg", "client", var.netskope_tenant.tenant_id])
  resource_group_name       = var.azurerm_network_config.vnet_rg_name
  virtual_network_name      = var.azurerm_network_config.vnet_object.name
  allow_gateway_transit     = true
  allow_forwarded_traffic   = true
  remote_virtual_network_id = azurerm_virtual_network.client.id
}

resource "azurerm_route" "static_default_route" {
  count                  = var.azurerm_route_server.create_route_server == false && var.azurerm_route_server.route_server_id == null ? 1 : 0
  name                   = "staticDefaultRoute"
  resource_group_name    = var.azurerm_network_config.vnet_rg_name
  route_table_name       = azurerm_route_table.client.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.virtual_appliance_ip
}

resource "azurerm_route" "local_route" {
  name                = "local"
  resource_group_name = var.azurerm_network_config.vnet_rg_name
  route_table_name    = azurerm_route_table.client.name
  address_prefix      = var.clients.vnet_cidr
  next_hop_type       = "VnetLocal"
}
