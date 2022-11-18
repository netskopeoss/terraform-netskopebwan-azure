#------------------------------------------------------------------------------
#  Copyright (c) 2022 Netskope Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

##############################
##  azurerm Instance Variables  ##
##############################

azurerm_instance = {
  ssh_key = "ssh-rsa AAAAB3Nz %"
}

clients = {
  create_clients = true
  vnet_cidr      = "192.168.250.0/27"
}

##################################
##  azurerm vnet Specific Variables  ##
##################################

azurerm_network_config = {
  location  = "westus"
  vnet_cidr = "172.32.1.0/24"
  subnets = {
    ge1 = {
      subnet_cidr = "172.32.1.32/27"
    }
    ge2 = {
      subnet_cidr = "172.32.1.64/27"
    }
  }
}

azurerm_route_server = {
  create_route_server = true
  route_server_cidr   = "172.32.1.0/27"
}
###################################################
##  Netskope Borderless SD-WAN Tenant Variables  ##
###################################################

netskope_tenant = {
  tenant_id      = "606******ac"
  tenant_url     = "https://demo****.infiot.net"
  tenant_token   = "WzEsIj****ZCcCswPSJd"
  tenant_bgp_asn = "400"
}

netskope_gateway_config = {
  gateway_policy = "azurerm-gw-us"
  gateway_name   = "azurerm-gw-us"
  gateway_role   = "hub"
}