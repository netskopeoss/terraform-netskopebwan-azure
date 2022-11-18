// BGP Peer
resource "netskopebwan_gateway_port_forward" "client" {
  for_each        = toset(var.clients.ports)
  gateway_id      = var.netskope_gateway_config.gateway_data.primary.id
  name            = join("-", ["client", each.key])
  bi_directional  = false
  lan_ip          = azurerm_network_interface.client.private_ip_address
  lan_port        = each.key
  public_ip       = values(var.netskope_gateway_config.gateway_data.primary.public_ip)[0].ip_address
  public_port     = sum([2000, tonumber(each.key)])
  up_link_if_name = upper(keys(var.netskope_gateway_config.gateway_data.primary.public_ip)[0])
}