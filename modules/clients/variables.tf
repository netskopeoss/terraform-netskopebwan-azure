#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------
##############################
## Azure Instance Variables ##
##############################

variable "azurerm_instance" {
  description = "azurerm Instance Config"
  type = object({
    instance_type = optional(string, "Standard_D2s_v3")
    publisher     = optional(string, "infiotinc1614034091460")
    offer         = optional(string, "infiot-vedge")
    sku           = optional(string, "infiot_virtual_edge")
    version       = optional(string, "latest")
    ssh_key       = optional(string, "")
  })
  default = {
    instance_type = "Standard_B2ms"
  }
}

#######################
## azurerm vnet Variables ##
#######################

variable "azurerm_route_server" {
  description = "Existing azurerm vnet Details"
  type = object({
    route_server_id     = optional(string)          # Provide the existing Route server ID to reuse.
    create_route_server = optional(bool, false)     # Boolean to control a new Route server. This will override the above given value
    route_server_asn    = optional(string, "65515") # DO NOT CHANGE THIS.
    route_server_cidr   = string                    # Provide the Route Server Subnet irrespective of new or existing Route-Server
  })
}

variable "azurerm_network_config" {
  description = "Existing azurerm vnet Details"
  type = object({
    vnet_name      = optional(string) # If the above boolean was set to true, then should NOT be empty
    vnet_rg_name   = optional(string)
    location       = optional(string, "us-east-1")
    vnet_cidr      = optional(string)          # If the "create_vnet" boolean is false, provide CIDR to create new vnet
    primary_zone   = optional(string, "zone1") # Choose the availability zones. Else it will be auto-picked
    secondary_zone = optional(string, "zone2")
    vnet_object    = optional(any)
    subnets = object({
      ge1 = object({
        subnet_cidr   = optional(string)
        subnet_name   = optional(string)
        overlay       = optional(string, "public")
        subnet_object = optional(any)
      })
      ge2 = optional(object({
        subnet_cidr   = optional(string)
        subnet_name   = optional(string)
        overlay       = optional(string)
        subnet_object = optional(any)
      }), null)
      ge3 = optional(object({
        subnet_cidr   = optional(string)
        subnet_name   = optional(string)
        overlay       = optional(string)
        subnet_object = optional(any)
      }), null)
      ge4 = optional(object({
        subnet_cidr   = optional(string)
        subnet_name   = optional(string)
        overlay       = optional(string)
        subnet_object = optional(any)
      }), null)
    })
    route_table = optional(object({ # Provide Route Table IDs if need to reuse the existing ones. Otherwise, new Routing table will be created
      public  = optional(string, "")
      private = optional(string, "")
    }), { public = "", private = "" })
  })
}

###########################
## Netskope GW Variables ##
###########################

variable "netskope_tenant" {
  description = "Netskope Tenant Details"
  type = object({
    tenant_id      = string # Netskope Borderless SD-WAN Tenant UID
    tenant_url     = string # Netskope Borderless SD-WAN Tenant URL
    tenant_token   = string # Netskope Borderless SD-WAN Tenant Token
    tenant_bgp_asn = optional(string, "400")
  })
}

variable "netskope_gateway_config" {
  description = "Netskope Gateway Details"
  type = object({
    ha_enabled       = optional(bool, false) # Boolean to control HA GW deployment
    gateway_password = optional(string, "infiot")
    gateway_policy   = optional(string, "400")
    gateway_name     = optional(string, "test")
    gateway_model    = optional(string, "iXVirtual")
    gateway_role     = optional(string, "spoke")
    dns_primary      = optional(string, "8.8.8.8")
    dns_secondary    = optional(string, "8.8.4.4")
    gateway_data     = optional(any)
  })
}

#######################
## Optional Client's ##
#######################

variable "clients" {
  description = "Optional Client / Host vnet configuration"
  type = object({
    create_clients = optional(bool, false) # Blob to deploy optional Client in a new vnet for end to end testing.
    publisher      = optional(string, "Canonical")
    offer          = optional(string, "UbuntuServer")
    sku            = optional(string, "18.04-LTS")
    version        = optional(string, "latest")
    vnet_cidr      = optional(string, "192.168.255.0/28")
    instance_type  = optional(string, "Standard_B2ms")
    password       = optional(string, "infiot")
    ports          = optional(list(string), ["22"])
  })
  default = {
    create_clients = false
  }
}

