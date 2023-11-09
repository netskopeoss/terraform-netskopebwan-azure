#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

locals {
  route_server_peer_ip1 = cidrhost(var.azurerm_route_server.route_server_cidr, 4)
  route_server_peer_ip2 = cidrhost(var.azurerm_route_server.route_server_cidr, 5)
}

locals {
  locations = ["westus2", "centralus", "canadacentral", "eastus2", "southcentralus", "brazilsouth", "southafricanorth", "swedencentral", "northeurope", "italynorth", "polandcentral", "israelcentral", "uaenorth", "centralindia", "southeastasia", "eastasia", "koreacentral", "japaneast", "australiaeast"]
}

locals {
  network_config_list = length(local.locations) == 0 ? [var.azurerm_network_config] : [
    for loc in local.locations : merge(var.azurerm_network_config, { location = loc })
  ]
}

module "azurerm_vnet" {
  for_each = { for index, ncon in local.network_config_list: ncon.location => ncon }
  source                  = "./modules/azurerm_vnet"
  clients                 = var.clients
  azurerm_instance        = var.azurerm_instance
  netskope_tenant         = var.netskope_tenant
  azurerm_route_server    = var.azurerm_route_server
  azurerm_network_config  = each.value
  netskope_gateway_config = var.netskope_gateway_config
  tags                    = var.tags
}

module "nsg_config" {
  for_each = { for index, ncon in local.network_config_list: ncon.location => ncon }
  source                  = "./modules/nsg_config"
  netskope_tenant         = var.netskope_tenant
  clients                 = var.clients
  azurerm_instance        = var.azurerm_instance
  azurerm_route_server    = var.azurerm_route_server
  azurerm_network_config  = merge(each.value, module.azurerm_vnet[each.key].azurerm_vnet_output.azurerm_network_config)
  netskope_gateway_config = merge(var.netskope_gateway_config, module.azurerm_vnet[each.key].azurerm_vnet_output.netskope_gateway_config)
  tags                    = var.tags
}

module "azurerm_vm" {
  for_each = { for index, ncon in local.network_config_list: ncon.location => ncon }
  source                  = "./modules/azurerm_vm"
  azurerm_instance        = var.azurerm_instance
  netskope_tenant         = var.netskope_tenant
  azurerm_network_config  = merge(each.value, module.azurerm_vnet[each.key].azurerm_vnet_output.azurerm_network_config)
  azurerm_route_server    = merge(var.azurerm_route_server, module.azurerm_vnet[each.key].azurerm_vnet_output.route_server)
  netskope_gateway_config = merge(var.netskope_gateway_config, module.nsg_config[each.key].nsg_config_output.netskope_gateway_config)
  tags                    = var.tags
}

/*
module "clients" {
  source                  = "./modules/clients"
  count                   = var.clients.create_clients ? 1 : 0
  netskope_tenant         = var.netskope_tenant
  azurerm_instance        = var.azurerm_instance
  clients                 = var.clients
  azurerm_network_config  = merge(var.azurerm_network_config, module.azurerm_vnet.azurerm_vnet_output.azurerm_network_config)
  azurerm_route_server    = var.azurerm_route_server
  netskope_gateway_config = module.nsg_config.nsg_config_output.netskope_gateway_config
  tags                    = var.tags
}*/
