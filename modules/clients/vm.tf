#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

resource "azurerm_network_interface" "client" {
  name                = join("-", ["client", var.netskope_tenant.tenant_id])
  location            = var.azurerm_network_config.location
  resource_group_name = var.azurerm_network_config.vnet_rg_name

  ip_configuration {
    name                          = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
    subnet_id                     = azurerm_subnet.client.id
    private_ip_address_allocation = "Dynamic"
  }
  tags = merge(var.tags, local.netskope_tags)
}

resource "azurerm_linux_virtual_machine" "client" {
  name                            = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
  location                        = var.azurerm_network_config.location
  resource_group_name             = var.azurerm_network_config.vnet_rg_name
  admin_username                  = "infiot"
  disable_password_authentication = true

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = "infiot"
    public_key = var.azurerm_instance.ssh_key
  }
  custom_data = base64encode(templatefile("${path.module}/scripts/user-data.sh",
    {
      password = var.clients.password,
    }
  ))

  network_interface_ids = [azurerm_network_interface.client.id]
  size                  = var.clients.instance_type

  boot_diagnostics {
    storage_account_uri = null
  }

  source_image_reference {
    publisher = var.clients.publisher
    offer     = var.clients.offer
    sku       = var.clients.sku
    version   = var.clients.version
  }

  os_disk {
    name                 = join("-", ["client", var.netskope_tenant.tenant_id, var.azurerm_network_config.location])
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = "32"
  }
  tags = merge(var.tags, local.netskope_tags)
}
