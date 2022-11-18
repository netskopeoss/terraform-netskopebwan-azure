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

  common_tags = {
    environment = join("-", [var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  }
}

locals {
  public_nw_security_rules = {
    ipsec = {
      name                       = "Allow_IPSec"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = "4500"
      source_address_prefixes    = ["0.0.0.0/0"]
      destination_address_prefix = "*"
    }
    ssh = {
      name                       = "Allow_SSH_Access"
      priority                   = 101
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefixes    = ["0.0.0.0/0"]
      destination_address_prefix = "*"
    }
  }
  private_nw_security_rules = {
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
}