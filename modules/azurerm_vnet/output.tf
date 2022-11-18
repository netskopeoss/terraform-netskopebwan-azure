#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

output "azurerm_vnet_output" {
  value = {
    route_server = {
      route_server_id = local.azurerm_route_server
    }
    netskope_gateway_config = {
      gateway_data = {
        primary = {
          public_ip  = azurerm_public_ip.netskope_sdwan_primary_gw
          interfaces = azurerm_network_interface.netskope_sdwan_primary_gw_intf
        }
        secondary = {
          public_ip  = azurerm_public_ip.netskope_sdwan_secondary_gw
          interfaces = azurerm_network_interface.netskope_sdwan_secondary_gw_intf
        }
      }
    }
    azurerm_network_config = {
      location     = local.netskope_sdwan_gw_rg.location
      vnet_rg_name = local.netskope_sdwan_gw_rg.name
      vnet_object  = local.netskope_sdwan_gw_vnet
      subnets = {
        for intf, subnet in local.enabled_interfaces :
        intf => merge(subnet, { "subnet_object" = local.azurerm_subnets[intf] })
      }
    }
  }
}