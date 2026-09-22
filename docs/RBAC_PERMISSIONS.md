# RBAC Permissions

## Azure Resources Created by the Module

This module creates no IAM or managed identity resources — the gateway VMs do not need access to the Azure API. The Terraform operator principal is the only entity that requires Azure permissions.

## Terraform Operator Permissions

The Azure principal running `terraform apply` needs permissions to create and manage all resources in the module. The built-in **Contributor** role at the subscription or resource group scope covers all required operations.

For least-privilege deployments, the following specific permissions are required:

### Required Azure RBAC Actions

```
# Resource Groups
Microsoft.Resources/subscriptions/resourceGroups/read
Microsoft.Resources/subscriptions/resourceGroups/write
Microsoft.Resources/subscriptions/resourceGroups/delete

# Virtual Networks and Subnets
Microsoft.Network/virtualNetworks/read
Microsoft.Network/virtualNetworks/write
Microsoft.Network/virtualNetworks/delete
Microsoft.Network/virtualNetworks/subnets/read
Microsoft.Network/virtualNetworks/subnets/write
Microsoft.Network/virtualNetworks/subnets/delete
Microsoft.Network/virtualNetworks/subnets/join/action

# Network Security Groups
Microsoft.Network/networkSecurityGroups/read
Microsoft.Network/networkSecurityGroups/write
Microsoft.Network/networkSecurityGroups/delete
Microsoft.Network/networkSecurityGroups/join/action

# Route Tables
Microsoft.Network/routeTables/read
Microsoft.Network/routeTables/write
Microsoft.Network/routeTables/delete
Microsoft.Network/routeTables/join/action

# Public IPs
Microsoft.Network/publicIPAddresses/read
Microsoft.Network/publicIPAddresses/write
Microsoft.Network/publicIPAddresses/delete
Microsoft.Network/publicIPAddresses/join/action

# Network Interfaces
Microsoft.Network/networkInterfaces/read
Microsoft.Network/networkInterfaces/write
Microsoft.Network/networkInterfaces/delete
Microsoft.Network/networkInterfaces/join/action
Microsoft.Network/networkInterfaces/ipConfigurations/read

# Virtual Machines
Microsoft.Compute/virtualMachines/read
Microsoft.Compute/virtualMachines/write
Microsoft.Compute/virtualMachines/delete
Microsoft.Compute/virtualMachines/start/action
Microsoft.Compute/virtualMachines/runCommand/action   # required for Azure Run Command
Microsoft.Compute/virtualMachines/instanceView/read   # required for VM agent readiness check

# Marketplace (only required if accept_plan = true)
Microsoft.MarketplaceOrdering/agreements/read
Microsoft.MarketplaceOrdering/agreements/write
Microsoft.MarketplaceOrdering/offertypes/publishers/offers/plans/agreements/read
Microsoft.MarketplaceOrdering/offertypes/publishers/offers/plans/agreements/write

# Route Server (Virtual Hub)
Microsoft.Network/virtualHubs/read
Microsoft.Network/virtualHubs/write
Microsoft.Network/virtualHubs/delete
Microsoft.Network/virtualHubs/bgpConnections/read
Microsoft.Network/virtualHubs/bgpConnections/write
Microsoft.Network/virtualHubs/bgpConnections/delete
Microsoft.Network/virtualHubs/routeTables/read
Microsoft.Network/virtualRouters/read
Microsoft.Network/virtualRouters/write
```

### Custom Role Definition (JSON)

```json
{
  "Name": "Netskope BWAN Terraform Operator",
  "Description": "Minimum permissions to deploy the Netskope BWAN Azure gateway project",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/*",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Network/routeTables/*",
    "Microsoft.Network/publicIPAddresses/*",
    "Microsoft.Network/networkInterfaces/*",
    "Microsoft.Network/virtualHubs/*",
    "Microsoft.Network/virtualRouters/*",
    "Microsoft.Compute/virtualMachines/*",
    "Microsoft.MarketplaceOrdering/agreements/*",
    "Microsoft.MarketplaceOrdering/offertypes/*"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/YOUR-SUBSCRIPTION-ID"
  ]
}
```

Create the custom role:

```sh
az role definition create --role-definition custom-role.json
az role assignment create \
  --role "Netskope BWAN Terraform Operator" \
  --assignee <service-principal-or-user-object-id> \
  --scope /subscriptions/<subscription-id>
```

## Marketplace Terms

Accepting Marketplace image terms requires the `Microsoft.MarketplaceOrdering/agreements/write` permission. This is a one-time operation per subscription. If your operator principal does not have this permission, a subscription Owner or Administrator can pre-accept the terms:

```sh
az vm image terms accept \
  --publisher netskopebwan \
  --offer netskope-unified-sase-virtual-gateway \
  --plan netskope-unified-sase-virtual-gateway-r6_2_x
```

After pre-accepting, set `accept_plan = false` in `azure_vm_config` so Terraform does not attempt to create the marketplace agreement resource (which would fail if the principal lacks `MarketplaceOrdering/agreements/write`).

## CI/CD Pipeline Considerations

When running this module from a CI/CD pipeline:

1. **Credentials**: Use a Service Principal with the custom role above. Assign at the resource group scope for tighter control:
   ```sh
   az role assignment create \
     --role "Netskope BWAN Terraform Operator" \
     --assignee <sp-object-id> \
     --scope /subscriptions/<sub-id>/resourceGroups/<rg>
   ```

2. **Netskope API token**: Store `TF_VAR_netskope_tenant_token` as a pipeline secret (GitHub Actions secret, Azure Key Vault, HashiCorp Vault). Do not commit it to version control.

3. **Run Command**: The `local-exec` provisioners in `run_command.tf` call `scripts/azure_run_command.sh`, which runs `az vm run-command invoke` from the Terraform runner. The pipeline environment must have:
   - Azure CLI installed
   - The same Service Principal credentials set as environment variables (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`)
   - Network access to the Azure management endpoint (`management.azure.com`)

4. **State file access**: The Terraform runner needs read/write access to the state backend. See [State Management](STATE_MANAGEMENT.md).
