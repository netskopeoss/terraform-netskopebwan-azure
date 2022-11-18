#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

locals {
  route_server_peer_ip1 = cidrhost(var.azurerm_route_server.route_server_cidr, 4)
  route_server_peer_ip2 = cidrhost(var.azurerm_route_server.route_server_cidr, 5)
}

module "azurerm_vnet" {
  source                  = "./modules/azurerm_vnet"
  clients                 = var.clients
  azurerm_instance        = var.azurerm_instance
  netskope_tenant         = var.netskope_tenant
  azurerm_route_server    = var.azurerm_route_server
  azurerm_network_config  = var.azurerm_network_config
  netskope_gateway_config = var.netskope_gateway_config
}

module "nsg_config" {
  source                  = "./modules/nsg_config"
  netskope_tenant         = var.netskope_tenant
  clients                 = var.clients
  azurerm_instance        = var.azurerm_instance
  azurerm_route_server    = var.azurerm_route_server
  azurerm_network_config  = merge(var.azurerm_network_config, module.azurerm_vnet.azurerm_vnet_output.azurerm_network_config)
  netskope_gateway_config = merge(var.netskope_gateway_config, module.azurerm_vnet.azurerm_vnet_output.netskope_gateway_config)
}

module "azurerm_vm" {
  source                  = "./modules/azurerm_vm"
  azurerm_instance        = var.azurerm_instance
  netskope_tenant         = var.netskope_tenant
  azurerm_network_config  = merge(var.azurerm_network_config, module.azurerm_vnet.azurerm_vnet_output.azurerm_network_config)
  azurerm_route_server    = merge(var.azurerm_route_server, module.azurerm_vnet.azurerm_vnet_output.route_server)
  netskope_gateway_config = merge(var.netskope_gateway_config, module.nsg_config.nsg_config_output.netskope_gateway_config)
}

module "clients" {
  source                  = "./modules/clients"
  count                   = var.clients.create_clients ? 1 : 0
  netskope_tenant         = var.netskope_tenant
  azurerm_instance        = var.azurerm_instance
  clients                 = var.clients
  azurerm_network_config  = merge(var.azurerm_network_config, module.azurerm_vnet.azurerm_vnet_output.azurerm_network_config)
  azurerm_route_server    = var.azurerm_route_server
  netskope_gateway_config = module.nsg_config.nsg_config_output.netskope_gateway_config
}