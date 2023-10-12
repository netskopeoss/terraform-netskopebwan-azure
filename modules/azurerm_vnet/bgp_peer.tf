#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

resource "azurerm_route_server_bgp_connection" "primary" {
  count           = (var.azurerm_route_server.create_route_server || var.azurerm_route_server.route_server_id != null) && length(local.lan_interfaces) > 0 ? 1 : 0
  name            = join("-", ["primary", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  route_server_id = local.azurerm_route_server
  peer_asn        = var.netskope_tenant.tenant_bgp_asn
  peer_ip         = azurerm_network_interface.netskope_sdwan_primary_gw_intf[tolist(local.lan_interfaces)[0]].private_ip_address
}

resource "azurerm_route_server_bgp_connection" "secondary" {
  count           = (var.azurerm_route_server.create_route_server || var.azurerm_route_server.route_server_id != null) && length(local.lan_interfaces) > 0 && var.netskope_gateway_config.ha_enabled ? 1 : 0
  name            = join("-", ["secondary", var.netskope_tenant.tenant_id, local.netskope_sdwan_gw_rg.location])
  route_server_id = local.azurerm_route_server
  peer_asn        = var.netskope_tenant.tenant_bgp_asn
  peer_ip         = azurerm_network_interface.netskope_sdwan_secondary_gw_intf[tolist(local.lan_interfaces)[0]].private_ip_address
  depends_on = [
    azurerm_route_server_bgp_connection.primary
  ]
}
