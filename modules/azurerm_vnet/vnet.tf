#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

data "azurerm_resource_group" "netskope_sdwan_gw_rg" {
  count = var.azurerm_network_config.vnet_rg_name != null ? 1 : 0
  name  = var.azurerm_network_config.vnet_rg_name
}

resource "azurerm_resource_group" "netskope_sdwan_gw_rg" {
  count    = var.azurerm_network_config.vnet_rg_name == null ? 1 : 0
  name     = join("-", ["rg", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  location = var.azurerm_network_config.location
  tags = merge(var.tags, local.netskope_tags)
}

locals {
  netskope_sdwan_gw_rg = element(coalescelist(data.azurerm_resource_group.netskope_sdwan_gw_rg.*, azurerm_resource_group.netskope_sdwan_gw_rg.*, [""]), 0)
}

data "azurerm_virtual_network" "netskope_sdwan_gw_vnet" {
  count               = var.azurerm_network_config.vnet_name != null ? 1 : 0
  resource_group_name = local.netskope_sdwan_gw_rg.name
  name                = var.azurerm_network_config.vnet_name
}

resource "azurerm_virtual_network" "netskope_sdwan_gw_vnet" {
  name                = join("-", ["vnet", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  count               = var.azurerm_network_config.vnet_name == null ? 1 : 0
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name
  address_space       = [var.azurerm_network_config.vnet_cidr]
  tags = merge(var.tags, local.netskope_tags)
}

locals {
  netskope_sdwan_gw_vnet = element(coalescelist(data.azurerm_virtual_network.netskope_sdwan_gw_vnet.*, azurerm_virtual_network.netskope_sdwan_gw_vnet.*, [""]), 0)
}

data "azurerm_subnet" "netskope_sdwan_gw_subnets" {
  for_each = {
    for intf, subnet in local.enabled_interfaces : intf => subnet if subnet.subnet_name != null
  }
  name                 = each.value.subnet_name
  resource_group_name  = local.netskope_sdwan_gw_rg.name
  virtual_network_name = local.netskope_sdwan_gw_vnet.name
}

resource "azurerm_subnet" "netskope_sdwan_gw_subnets" {
  for_each = {
    for intf, subnet in local.enabled_interfaces : intf => subnet if subnet.subnet_name == null
  }
  name                 = join("-", [each.key, var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  resource_group_name  = local.netskope_sdwan_gw_rg.name
  virtual_network_name = local.netskope_sdwan_gw_vnet.name
  address_prefixes     = [each.value.subnet_cidr]
}

locals {
  azurerm_subnets = {
    for intf, subnet in local.enabled_interfaces :
    intf => element(coalescelist(try([data.azurerm_subnet.netskope_sdwan_gw_subnets[intf]], []), try([azurerm_subnet.netskope_sdwan_gw_subnets[intf]], []), [""]), 0)
  }
}

resource "azurerm_network_security_group" "netskope_sdwan_gw_public" {
  name                = join("-", ["public", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_network_security_group" "netskope_sdwan_gw_private" {
  name                = join("-", ["private", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_network_security_rule" "netskope_sdwan_gw_public" {
  for_each                    = local.public_nw_security_rules
  name                        = each.value.name
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = local.netskope_sdwan_gw_rg.name
  network_security_group_name = azurerm_network_security_group.netskope_sdwan_gw_public.name
}

resource "azurerm_network_security_rule" "client_ports" {
  for_each                    = var.clients.create_clients ? toset(var.clients.ports) : toset([])
  name                        = join("-", ["pf", each.key])
  direction                   = "Inbound"
  access                      = "Allow"
  priority                    = 200
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = sum([2000, tonumber(each.key)])
  source_address_prefixes     = ["0.0.0.0/0"]
  destination_address_prefix  = "*"
  resource_group_name         = local.netskope_sdwan_gw_rg.name
  network_security_group_name = azurerm_network_security_group.netskope_sdwan_gw_public.name
}

resource "azurerm_network_security_rule" "netskope_sdwan_gw_private" {
  for_each                    = local.private_nw_security_rules
  name                        = each.value.name
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = local.netskope_sdwan_gw_rg.name
  network_security_group_name = azurerm_network_security_group.netskope_sdwan_gw_private.name
}

resource "azurerm_subnet_network_security_group_association" "netskope_sdwan_gw_public" {
  for_each                  = { for k, v in keys(local.public_overlay_interfaces) : k => v if var.azurerm_network_config.vnet_name == null }
  subnet_id                 = local.azurerm_subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.netskope_sdwan_gw_public.id
}

resource "azurerm_subnet_network_security_group_association" "netskope_sdwan_gw_private" {
  for_each                  = { for index, value in local.lan_interfaces : value => value if var.azurerm_network_config.vnet_name == null }
  subnet_id                 = local.azurerm_subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.netskope_sdwan_gw_private.id
}

resource "azurerm_route_table" "netskope_sdwan_gw_public_rt" {
  count               = (var.azurerm_network_config.vnet_name == null || var.azurerm_network_config.route_table.public == "") ? 1 : 0
  name                = join("-", ["public", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name

  route {
    name           = "default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  route {
    name           = "local"
    address_prefix = local.netskope_sdwan_gw_vnet.address_space[0]
    next_hop_type  = "VnetLocal"
  }

  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_route_table" "netskope_sdwan_gw_private_rt" {
  count               = (var.azurerm_network_config.vnet_name == null || var.azurerm_network_config.route_table.private == "") ? 1 : 0
  name                = join("-", ["private", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name

  route {
    name           = "local"
    address_prefix = local.netskope_sdwan_gw_vnet.address_space[0]
    next_hop_type  = "VnetLocal"
  }

  tags = merge(var.tags, local.netskope_tags)
}

locals {
  netskope_sdwan_public_rt  = var.azurerm_network_config.route_table.public != "" ? var.azurerm_network_config.route_table.public : try(element(azurerm_route_table.netskope_sdwan_gw_public_rt.*.id, 0), "")
  netskope_sdwan_private_rt = var.azurerm_network_config.route_table.private != "" ? var.azurerm_network_config.route_table.private : try(element(azurerm_route_table.netskope_sdwan_gw_private_rt.*.id, 0), "")
}

resource "azurerm_subnet_route_table_association" "netskope_sdwan_gw_public_rt" {
  for_each       = toset(keys(local.public_overlay_interfaces))
  subnet_id      = local.azurerm_subnets[each.key].id
  route_table_id = local.netskope_sdwan_public_rt
}

resource "azurerm_subnet_route_table_association" "netskope_sdwan_gw_private_rt" {
  for_each       = toset(local.lan_interfaces)
  subnet_id      = local.azurerm_subnets[each.key].id
  route_table_id = local.netskope_sdwan_private_rt
}

resource "azurerm_subnet" "netskope_sdwan_gw_rs_subnet" {
  count                = var.azurerm_route_server.create_route_server && var.azurerm_route_server.route_server_cidr != "" ? 1 : 0
  name                 = "RouteServerSubnet"
  resource_group_name  = local.netskope_sdwan_gw_rg.name
  virtual_network_name = local.netskope_sdwan_gw_vnet.name
  address_prefixes     = [var.azurerm_route_server.route_server_cidr]
}

resource "azurerm_public_ip" "netskope_sdwan_gw_route_server" {
  count               = var.azurerm_route_server.create_route_server ? 1 : 0
  name                = join("-", ["rs", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_route_server" "netskope_sdwan_gw_route_server" {
  count                            = var.azurerm_route_server.create_route_server ? 1 : 0
  name                             = join("-", ["rs", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location                         = local.netskope_sdwan_gw_rg.location
  resource_group_name              = local.netskope_sdwan_gw_rg.name
  sku                              = "Standard"
  public_ip_address_id             = azurerm_public_ip.netskope_sdwan_gw_route_server[0].id
  subnet_id                        = azurerm_subnet.netskope_sdwan_gw_rs_subnet[0].id
  branch_to_branch_traffic_enabled = true
  depends_on = [
    azurerm_public_ip.netskope_sdwan_gw_route_server[0]
  ]
  tags = merge(var.tags, local.netskope_tags)
}

locals {
  azurerm_route_server = element(coalescelist(try([azurerm_route_server.netskope_sdwan_gw_route_server[0].id], []), [var.azurerm_route_server.route_server_id]), 0)
}
