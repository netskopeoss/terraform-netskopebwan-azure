#------------------------------------------------------------------------------
#  Copyright (c) 2022 Infiot Inc.
#  All rights reserved.
#------------------------------------------------------------------------------

output "nsg_config_output" {
  value = {
    netskope_gateway_config = {
      gateway_data = {
        primary = merge(var.netskope_gateway_config.gateway_data.primary, {
          id    = resource.netskopebwan_gateway.primary.id
          token = resource.netskopebwan_gateway_activate.primary.token
        })
        secondary = merge(var.netskope_gateway_config.gateway_data.secondary, {
          id    = try(resource.netskopebwan_gateway.secondary[0].id, "")
          token = try(resource.netskopebwan_gateway_activate.secondary[0].token, "")
        })
      }
    }
  }
}