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
    ssh_key       = string # Provide the public key for ssh access
    instance_type = optional(string, "Standard_DS2_v2")
    publisher     = optional(string, "infiotinc1614034091460")
    offer         = optional(string, "infiot-vedge")
    sku           = optional(string, "infiot_virtual_edge")
    version       = optional(string, "latest")
  })
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

#######################
## azurerm vnet Variables ##
#######################

variable "azurerm_network_config" {
  description = "Existing azurerm vnet Details"
  type = object({
    vnet_name      = optional(string) # Provide the existing Virtual Network Name to reuse
    vnet_rg_name   = optional(string) # Provide the existing Resource Group in which existing Virtual Network available
    location       = string           # Location in which GW to be deployed.
    vnet_cidr      = optional(string) # Provide Virtual Network address space, if new one to be created. 
    primary_zone   = optional(string, "zone1")
    secondary_zone = optional(string, "zone2")
    vnet_object    = optional(any)
    subnets = object({
      ge1 = object({
        subnet_name   = optional(string)           # Provide the existing subnet name to reuse
        subnet_cidr   = optional(string)           # Provide CIDR to create a new subnet
        overlay       = optional(string, "public") # Overlay setting
        subnet_object = optional(any)              # It will be auto-computed
      })
      ge2 = optional(object({
        subnet_name   = optional(string)
        subnet_cidr   = optional(string)
        overlay       = optional(string)
        subnet_object = optional(any)
      }), null)
      ge3 = optional(object({
        subnet_name   = optional(string)
        subnet_cidr   = optional(string)
        overlay       = optional(string)
        subnet_object = optional(any)
      }), null)
      ge4 = optional(object({
        subnet_name   = optional(string)
        subnet_cidr   = optional(string)
        overlay       = optional(string)
        subnet_object = optional(any)
      }), null)
    })
    route_table = optional(object({ # Possible future usecase to re-use existing routing table
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
    tenant_id      = string                  # Netskope Borderless SD-WAN Tenant UID
    tenant_url     = string                  # Netskope Borderless SD-WAN Tenant URL
    tenant_token   = string                  # Netskope Borderless SD-WAN Tenant Token
    tenant_bgp_asn = optional(string, "400") # Default Netskope SD-WAN BGP ASN
  })
}

variable "netskope_gateway_config" {
  description = "Netskope Gateway Details"
  type = object({
    ha_enabled       = optional(bool, false)         # Boolean to control HA GW deployment
    gateway_password = optional(string, "infiot")    # Default password to be useful for console login
    gateway_policy   = optional(string, "test")      # New Gateway Policy name to create
    gateway_name     = optional(string, "test")      # New Gateway name to create
    gateway_model    = optional(string, "iXVirtual") # Gateway Model
    gateway_role     = optional(string, "spoke")     # Gateway Role "spoke" or "hub"
    dns_primary      = optional(string, "8.8.8.8")   # Primary DNS
    dns_secondary    = optional(string, "8.8.4.4")   # Secondary DNS
    gateway_data     = optional(any)                 # It will be auto-computed
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

###################
## Optional Tags ##
###################

variable "tags" {
  description = "Optional Tags to inherit"
  type = any
  default = { }
}
