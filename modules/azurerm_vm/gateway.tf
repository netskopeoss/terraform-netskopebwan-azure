#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

locals {
  enabled_interfaces = {
    for intf, subnet in var.azurerm_network_config.subnets :
    intf => subnet if subnet != null && startswith(intf, "ge")
  }
  primary_gw_interfaces = [
    for intf, subnet in local.enabled_interfaces :
    var.netskope_gateway_config.gateway_data.primary.interfaces[intf].id
  ]
  secondary_gw_interfaces = [
    for intf, subnet in local.enabled_interfaces :
    var.netskope_gateway_config.gateway_data.secondary.interfaces[intf].id if var.netskope_gateway_config.ha_enabled
  ]
}

locals {
  route_server_peer_ip1 = cidrhost(var.azurerm_route_server.route_server_cidr, 4)
  route_server_peer_ip2 = cidrhost(var.azurerm_route_server.route_server_cidr, 5)
}

resource "azurerm_linux_virtual_machine" "netskope_sdwan_primary_gw" {
  name                            = join("-", ["nsg", var.netskope_gateway_config.gateway_data.primary.id])
  location                        = var.azurerm_network_config.location
  resource_group_name             = var.azurerm_network_config.vnet_rg_name
  admin_username                  = "infiot"
  disable_password_authentication = true

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  admin_ssh_key {
    username   = "infiot"
    public_key = var.azurerm_instance.ssh_key
  }
  custom_data = base64encode(templatefile("modules/azurerm_vm/scripts/user-data.sh",
    {
      netskope_gw_default_password = var.netskope_gateway_config.gateway_password,
      netskope_tenant_url          = var.netskope_tenant.tenant_url,
      netskope_gw_activation_key   = var.netskope_gateway_config.gateway_data.primary.token,
      netskope_gw_bgp_metric       = "10",
      netskope_gw_asn              = var.netskope_tenant.tenant_bgp_asn,
      route_server_peer_ip1        = local.route_server_peer_ip1
      route_server_peer_ip2        = local.route_server_peer_ip2
    }
  ))

  network_interface_ids = tolist(local.primary_gw_interfaces)
  size                  = var.azurerm_instance.instance_type

  source_image_reference {
    publisher = var.azurerm_instance.publisher
    offer     = var.azurerm_instance.offer
    sku       = var.azurerm_instance.sku
    version   = var.azurerm_instance.version
  }

  plan {
    name      = var.azurerm_instance.sku
    product   = var.azurerm_instance.offer
    publisher = var.azurerm_instance.publisher
  }

  os_disk {
    name                 = join("-", ["osdisk", var.netskope_gateway_config.gateway_data.primary.id])
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = "32"
  }
}

resource "azurerm_linux_virtual_machine" "netskope_sdwan_secondary_gw" {
  count                           = var.netskope_gateway_config.ha_enabled ? 1 : 0
  name                            = join("-", ["nsg", var.netskope_gateway_config.gateway_data.secondary.id])
  location                        = var.azurerm_network_config.location
  resource_group_name             = var.azurerm_network_config.vnet_rg_name
  admin_username                  = "infiot"
  disable_password_authentication = true

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  admin_ssh_key {
    username   = "infiot"
    public_key = var.azurerm_instance.ssh_key
  }
  custom_data = base64encode(templatefile("modules/azurerm_vm/scripts/user-data.sh",
    {
      netskope_gw_default_password = var.netskope_gateway_config.gateway_password,
      netskope_tenant_url          = var.netskope_tenant.tenant_url,
      netskope_gw_activation_key   = var.netskope_gateway_config.gateway_data.secondary.token,
      netskope_gw_bgp_metric       = "20",
      netskope_gw_asn              = var.netskope_tenant.tenant_bgp_asn,
      route_server_peer_ip1        = local.route_server_peer_ip1
      route_server_peer_ip2        = local.route_server_peer_ip2
    }
  ))

  network_interface_ids = tolist(local.secondary_gw_interfaces)
  size                  = var.azurerm_instance.instance_type

  source_image_reference {
    publisher = var.azurerm_instance.publisher
    offer     = var.azurerm_instance.offer
    sku       = var.azurerm_instance.sku
    version   = var.azurerm_instance.version
  }

  plan {
    name      = var.azurerm_instance.sku
    product   = var.azurerm_instance.offer
    publisher = var.azurerm_instance.publisher
  }

  os_disk {
    name                 = join("-", ["osdisk", var.netskope_gateway_config.gateway_data.secondary.id])
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = "32"
  }
}