#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

resource "azurerm_public_ip" "netskope_sdwan_primary_gw" {
  for_each            = toset(keys(local.public_overlay_interfaces))
  name                = join("-", ["primary", each.key, var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_public_ip" "netskope_sdwan_secondary_gw" {
  for_each            = var.netskope_gateway_config.ha_enabled ? local.public_overlay_interfaces : {}
  name                = join("-", ["secondary", each.key, var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  location            = local.netskope_sdwan_gw_rg.location
  resource_group_name = local.netskope_sdwan_gw_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_network_interface" "netskope_sdwan_primary_gw_intf" {
  for_each             = local.enabled_interfaces
  name                 = join("-", ["primary", each.key, var.netskope_tenant.tenant_id])
  location             = local.netskope_sdwan_gw_rg.location
  resource_group_name  = local.netskope_sdwan_gw_rg.name
  enable_ip_forwarding = try(local.public_overlay_interfaces[each.key], null) == null ? true : false

  ip_configuration {
    name                          = join("-", ["primary", each.key, var.netskope_tenant.tenant_id])
    subnet_id                     = local.azurerm_subnets[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = try(local.public_overlay_interfaces[each.key], null) != null ? azurerm_public_ip.netskope_sdwan_primary_gw[each.key].id : null
  }
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_network_interface" "netskope_sdwan_secondary_gw_intf" {
  for_each             = var.netskope_gateway_config.ha_enabled ? local.enabled_interfaces : {}
  name                 = join("-", ["secondary", each.key, var.netskope_tenant.tenant_id])
  location             = local.netskope_sdwan_gw_rg.location
  resource_group_name  = local.netskope_sdwan_gw_rg.name
  enable_ip_forwarding = try(local.public_overlay_interfaces[each.key], null) == null ? true : false

  ip_configuration {
    name                          = join("-", ["secondary", each.key, var.netskope_tenant.tenant_id])
    subnet_id                     = local.azurerm_subnets[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = try(local.public_overlay_interfaces[each.key], null) != null ? azurerm_public_ip.netskope_sdwan_secondary_gw[each.key].id : null
  }
  tags = merge(var.tags, local.netskope_tags)
}
