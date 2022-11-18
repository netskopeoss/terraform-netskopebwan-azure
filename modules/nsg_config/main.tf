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

  common_tags = {
    environment = join("-", [var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  }
}

locals {
  route_server_primary_ip   = cidrhost(var.azurerm_route_server.route_server_cidr, 4)
  route_server_secondary_ip = cidrhost(var.azurerm_route_server.route_server_cidr, 5)
}

resource "netskopebwan_policy" "multicloud" {
  name = var.netskope_gateway_config.gateway_policy
}

locals {
  netskopebwan_policy = resource.netskopebwan_policy.multicloud
}

// Gateway Resource 
resource "netskopebwan_gateway" "primary" {
  name  = var.netskope_gateway_config.gateway_name
  model = var.netskope_gateway_config.gateway_model
  role  = var.netskope_gateway_config.gateway_role
  assigned_policy {
    id   = local.netskopebwan_policy.id
    name = local.netskopebwan_policy.name
  }
}

# Netskope GW creation can take a few seconds to
# create all dependent services in backend
resource "time_sleep" "primary_gw_propagation" {
  create_duration = "30s"

  triggers = {
    gateway_id = netskopebwan_gateway.primary.id
  }
}

resource "netskopebwan_gateway" "secondary" {
  count = var.netskope_gateway_config.ha_enabled ? 1 : 0
  name  = "${var.netskope_gateway_config.gateway_name}-ha"
  model = var.netskope_gateway_config.gateway_model
  role  = var.netskope_gateway_config.gateway_role
  assigned_policy {
    id   = local.netskopebwan_policy.id
    name = local.netskopebwan_policy.name
  }
  depends_on = [netskopebwan_gateway.primary, time_sleep.api_delay]
}

resource "time_sleep" "secondary_gw_propagation" {
  count           = var.netskope_gateway_config.ha_enabled ? 1 : 0
  create_duration = "30s"

  triggers = {
    gateway_id = netskopebwan_gateway.secondary[0].id
  }
}

resource "netskopebwan_gateway_interface" "primary" {
  for_each   = local.enabled_interfaces
  gateway_id = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  name       = upper(each.key)
  type       = "ethernet"
  addresses {
    address            = var.netskope_gateway_config.gateway_data.primary.interfaces[each.key].private_ip_address
    address_assignment = "static"
    address_family     = "ipv4"
    dns_primary        = var.netskope_gateway_config.dns_primary
    dns_secondary      = var.netskope_gateway_config.dns_secondary
    gateway            = cidrhost(var.azurerm_network_config.subnets[each.key].subnet_object.address_prefixes[0], 1)
    mask               = cidrnetmask(var.azurerm_network_config.subnets[each.key].subnet_object.address_prefixes[0])
  }
  dynamic "overlay_setting" {
    for_each = lookup(merge(local.public_overlay_interfaces, local.private_overlay_interfaces), each.key, "") != "" ? [1] : []
    content {
      is_backup           = false
      tx_bw_kbps          = 1000000
      rx_bw_kbps          = 1000000
      bw_measurement_mode = "manual"
      tag                 = lookup(local.public_overlay_interfaces, each.key, "") != "" ? "wired" : "private"
    }
  }
  enable_nat  = lookup(local.public_overlay_interfaces, each.key, "") != "" ? true : false
  mode        = "routed"
  is_disabled = false
  zone        = lookup(local.public_overlay_interfaces, each.key, "") != "" ? "untrusted" : "trusted"
}

resource "netskopebwan_gateway_interface" "secondary" {
  for_each = {
    for intf, vpc in local.enabled_interfaces : intf => vpc
    if var.netskope_gateway_config.ha_enabled
  }

  gateway_id = time_sleep.secondary_gw_propagation[0].triggers["gateway_id"]
  name       = upper(each.key)
  type       = "ethernet"
  addresses {
    address            = var.netskope_gateway_config.gateway_data.secondary.interfaces[each.key].private_ip_address
    address_assignment = "static"
    address_family     = "ipv4"
    dns_primary        = var.netskope_gateway_config.dns_primary
    dns_secondary      = var.netskope_gateway_config.dns_secondary
    gateway            = cidrhost(var.azurerm_network_config.subnets[each.key].subnet_object.address_prefixes[0], 1)
    mask               = cidrnetmask(var.azurerm_network_config.subnets[each.key].subnet_object.address_prefixes[0])
  }
  dynamic "overlay_setting" {
    for_each = lookup(merge(local.public_overlay_interfaces, local.private_overlay_interfaces), each.key, "") != "" ? [1] : []
    content {
      is_backup           = false
      tx_bw_kbps          = 1000000
      rx_bw_kbps          = 1000000
      bw_measurement_mode = "manual"
      tag                 = lookup(local.public_overlay_interfaces, each.key, "") != "" ? "wired" : "private"
    }
  }
  enable_nat  = lookup(local.public_overlay_interfaces, each.key, "") != "" ? true : false
  mode        = "routed"
  is_disabled = false
  zone        = lookup(local.public_overlay_interfaces, each.key, "") != "" ? "untrusted" : "trusted"
}

// Static Route
resource "netskopebwan_gateway_staticroute" "primary" {
  gateway_id  = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  advertise   = false
  destination = "169.254.169.254/32"
  device      = "GE1"
  install     = true
  nhop        = cidrhost(var.azurerm_network_config.subnets[keys(local.public_overlay_interfaces)[0]].subnet_object.address_prefixes[0], 1)
}

resource "netskopebwan_gateway_staticroute" "primary_rs" {
  count       = length(local.lan_interfaces) > 0 ? 1 : 0
  gateway_id  = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  advertise   = false
  destination = var.azurerm_route_server.route_server_cidr
  device      = upper(tolist(local.lan_interfaces)[0])
  install     = true
  nhop        = cidrhost(var.azurerm_network_config.subnets[tolist(local.lan_interfaces)[0]].subnet_object.address_prefixes[0], 1)
}

resource "netskopebwan_gateway_staticroute" "primary_static" {
  count       = var.azurerm_route_server.create_route_server == false && var.azurerm_route_server.route_server_id == null && length(local.lan_interfaces) > 0 && var.clients.create_clients == true ? 1 : 0
  gateway_id  = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  advertise   = true
  destination = var.clients.vnet_cidr
  device      = upper(tolist(local.lan_interfaces)[0])
  install     = true
  nhop        = cidrhost(var.azurerm_network_config.subnets[tolist(local.lan_interfaces)[0]].subnet_object.address_prefixes[0], 1)
}

resource "netskopebwan_gateway_staticroute" "secondary" {
  count       = var.netskope_gateway_config.ha_enabled ? 1 : 0
  gateway_id  = time_sleep.secondary_gw_propagation[0].triggers["gateway_id"]
  advertise   = false
  destination = "169.254.169.254/32"
  device      = "GE1"
  install     = true
  nhop        = cidrhost(var.azurerm_network_config.subnets[keys(local.public_overlay_interfaces)[0]].subnet_object.address_prefixes[0], 1)
}

resource "netskopebwan_gateway_staticroute" "secondary_rs" {
  count       = var.netskope_gateway_config.ha_enabled && length(local.lan_interfaces) > 0 ? 1 : 0
  gateway_id  = time_sleep.secondary_gw_propagation[0].triggers["gateway_id"]
  advertise   = false
  destination = var.azurerm_route_server.route_server_cidr
  device      = upper(tolist(local.lan_interfaces)[0])
  install     = true
  nhop        = cidrhost(var.azurerm_network_config.subnets[tolist(local.lan_interfaces)[0]].subnet_object.address_prefixes[0], 1)
}

resource "netskopebwan_gateway_activate" "primary" {
  gateway_id         = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  timeout_in_seconds = 86400
}

resource "netskopebwan_gateway_activate" "secondary" {
  count              = var.netskope_gateway_config.ha_enabled ? 1 : 0
  gateway_id         = time_sleep.secondary_gw_propagation[0].triggers["gateway_id"]
  timeout_in_seconds = 86400
}

// BGP Peer
resource "netskopebwan_gateway_bgpconfig" "route_serverpeer1_primary" {
  gateway_id = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  name       = "route_server-peer-1-primary"
  neighbor   = local.route_server_primary_ip
  remote_as  = var.azurerm_route_server.route_server_asn
}

resource "netskopebwan_gateway_bgpconfig" "route_serverpeer2_primary" {
  gateway_id = time_sleep.primary_gw_propagation.triggers["gateway_id"]
  name       = "route_server-peer-2-primary"
  neighbor   = local.route_server_secondary_ip
  remote_as  = var.azurerm_route_server.route_server_asn
}

// BGP Peer
resource "netskopebwan_gateway_bgpconfig" "route_serverpeer1_secondary" {
  count      = var.netskope_gateway_config.ha_enabled ? 1 : 0
  gateway_id = time_sleep.secondary_gw_propagation[0].triggers["gateway_id"]
  name       = "route_server-peer-1-secondary"
  neighbor   = local.route_server_primary_ip
  remote_as  = var.azurerm_route_server.route_server_asn
}

resource "netskopebwan_gateway_bgpconfig" "route_serverpeer2_secondary" {
  count      = var.netskope_gateway_config.ha_enabled ? 1 : 0
  gateway_id = time_sleep.secondary_gw_propagation[0].triggers["gateway_id"]
  name       = "route_server-peer-2-secondary"
  neighbor   = local.route_server_secondary_ip
  remote_as  = var.azurerm_route_server.route_server_asn
}

