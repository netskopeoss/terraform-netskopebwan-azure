# Deployment Guide

Comprehensive configuration reference and deployment instructions for Netskope SD-WAN gateways in Azure. For a minimal "get deployed fast" walkthrough, see the [Quick Start](QUICKSTART.md).

## Prerequisites

- **Terraform** >= 1.3
- **Azure CLI** (`az`) installed and authenticated
- **Azure subscription** with sufficient permissions (see [RBAC Permissions](RBAC_PERMISSIONS.md))
- **Netskope SD-WAN tenant** with a REST API token (created in the SD-WAN portal under Accounts → REST API)
- **Netskope gateway policy** — create a policy in the SD-WAN portal before deploying. The policy name is set in `gateway_policy` and must already exist; Terraform will fail at plan time if it cannot find it.
- **Marketplace terms accepted** for the Netskope BWAN image (once per subscription):
  ```sh
  az vm image terms accept \
    --publisher netskopebwan \
    --offer netskope-unified-sase-virtual-gateway \
    --plan netskope-unified-sase-virtual-gateway-r6_2_x
  ```
  Or set `accept_plan = true` in `azure_vm_config` to have Terraform accept them on first apply.

## Authentication

### Azure

The `azurerm` provider uses the standard Azure SDK credential chain. Use any of these methods:

| Method | Setup |
|---|---|
| **Interactive login** (recommended for development) | `az login`, then `az account set --subscription <id>` |
| **Service Principal — Client Secret** | `export ARM_CLIENT_ID=... ARM_CLIENT_SECRET=... ARM_TENANT_ID=... ARM_SUBSCRIPTION_ID=...` |
| **Service Principal — Client Certificate** | Set `ARM_CLIENT_CERTIFICATE_PATH` and `ARM_TENANT_ID` |
| **Managed Identity** | No configuration needed when running from an Azure VM or container with a managed identity |
| **subscription_id in tfvars** | Set `azure_network_config.subscription_id` — the provider uses this to select the subscription |

### Netskope

Set the tenant URL and API token as environment variables to keep secrets out of version control:

```sh
export TF_VAR_netskope_tenant_url="your-tenant.infiot.net"
export TF_VAR_netskope_tenant_token="YOUR_API_TOKEN"
```

The `https://` scheme on `tenant_url` is optional — the provider handles it. `netskope_tenant_token` is marked `sensitive = true`, so Terraform redacts it from plan output.

These override the corresponding fields in the `netskope_tenant` object. The remaining fields (`deployment_name`, `tenant_bgp_asn`) are set in `terraform.tfvars`.

## Configuration Reference

Copy the example file as your starting point:

```sh
cp example.tfvars terraform.tfvars
```

### `azure_network_config`

| Field | Required | Default | Description |
|---|---|---|---|
| `subscription_id` | No | `""` | Azure subscription ID. Can be set via `ARM_SUBSCRIPTION_ID` env var instead. |
| `location` | Yes | — | Azure region (e.g. `"westeurope"`, `"eastus"`) |
| `resource_group_name` | Yes | — | Resource group to create or use |
| `create_resource_group` | No | `true` | `false` to use an existing resource group |
| `create_vnet` | No | `true` | `false` to use an existing VNet (requires `vnet_id`) |
| `vnet_id` | When `create_vnet = false` | `""` | Resource ID of existing VNet |
| `vnet_cidr` | When `create_vnet = true` | `""` | VNet CIDR block; gateway subnets are auto-carved from this |

### `azure_vm_config`

| Field | Required | Default | Description |
|---|---|---|---|
| `vm_size` | No | `"Standard_D2s_v3"` | Azure VM size. The Netskope BWAN image is Gen1 — use Gen1-compatible sizes only. Confirmed working: `Standard_DS11_v2`. |
| `admin_username` | No | `"netskope"` | OS-level admin username |
| `admin_password` | When `ssh_public_key` is empty | `""` | OS-level admin password. Azure complexity: 12–123 chars, must include 3 of: uppercase, lowercase, digit, special character. Distinct from `netskope_gateway_config.gateway_password`. |
| `ssh_public_key` | No | `""` | SSH public key for OS-level access (alternative to password) |
| `image_publisher` | No | `"netskopebwan"` | Marketplace image publisher |
| `image_offer` | No | `"netskope-unified-sase-virtual-gateway"` | Marketplace image offer |
| `image_sku` | No | `"netskope-unified-sase-virtual-gateway-r6_2_x"` | Marketplace image SKU |
| `image_version` | No | `"6.2.5"` | Image version. Use `"latest"` to auto-select newest. |
| `accept_plan` | No | `true` | `true` to create an `azurerm_marketplace_agreement` resource accepting Marketplace terms |

**VM size selection**: The Netskope BWAN image is Generation 1 (BIOS boot). Gen2-only VM sizes (identified by Hyper-V Generation 2 only in `az vm list-skus` output) will fail with a `VMMarketplaceInvalidInput` error. Check availability in your target region and zone:

```sh
az vm list-skus --location westeurope --size Standard_DS11 --zone true -o table
```

Availability zone capacity varies by subscription. If a zone shows `NotAvailableForSubscription`, try an adjacent zone or a different VM size.

### `azure_route_server`

| Field | Required | Default | Description |
|---|---|---|---|
| `route_server_subnet_cidr` | No | `""` (auto-computed) | CIDR for `RouteServerSubnet` (/27 minimum, required name). **Pin this explicitly** — the auto-computed value shifts if `gateway_count` changes, which would force Route Server recreation. |
| `branch_to_branch_traffic` | No | `true` | Enable branch-to-branch traffic propagation on the Route Server |

**Auto-computed formula**: `cidrsubnet(vnet_cidr, 27 - vnet_prefix_len, gateway_count)`

With `vnet_cidr = 10.100.0.0/22` and `gateway_count = 2`: the auto-computed value is `10.100.0.64/27`. If you later change `gateway_count`, this formula produces a different CIDR, forcing Route Server destruction. Pin it to prevent this.

### `netskope_tenant`

| Field | Required | Default | Description |
|---|---|---|---|
| `deployment_name` | Yes | — | Free-form string used in resource naming (e.g. `"my-corp-prod"`) |
| `tenant_bgp_asn` | No | `"400"` | BGP ASN for the gateways. Must not be 65515 (reserved by Azure Route Server). |

> **Note**: `tenant_url` and `tenant_token` are set via environment variables (`TF_VAR_netskope_tenant_url`, `TF_VAR_netskope_tenant_token`), not in tfvars.

### `netskope_gateway_config`

| Field | Required | Default | Description |
|---|---|---|---|
| `gateway_policy` | Yes | `"test"` | Name of an existing policy on the Netskope tenant. Must be created in the SD-WAN portal before deployment — all gateways in the deployment share this single policy. |
| `gateway_password` | No | `"infiot"` | Netskope application console password (separate from the OS admin password) |
| `gateway_model` | No | `"iXVirtual"` | Gateway model type |
| `dns_primary` | No | `"8.8.8.8"` | Primary DNS server |
| `dns_secondary` | No | `"8.8.4.4"` | Secondary DNS server |
| `static_routes` | No | `[]` | CIDRs to route via the LAN interface on each gateway. Include Azure VNet CIDRs, on-prem CIDRs, or RFC 1918 ranges the gateway needs to reach via its LAN NIC (not via the default WAN route). |
| `wan_mtu` | No | `1500` | MTU for the Netskope overlay/WAN interface |

### Standalone Variables

| Variable | Default | Description |
|---|---|---|
| `gateway_count` | `2` | Number of gateways (1–8). Default is 2 for a resilient pair. The soft cap of 8 can be raised in `variables.tf`. |
| `gateway_prefix` | `"az-gw"` | Naming prefix for gateway identifiers (`{prefix}-1`, `{prefix}-2`, etc.) |
| `gateway_role` | `"hub"` | Gateway role (`hub` or `spoke`) |
| `subnet_size` | `28` | Prefix length for auto-generated gateway subnets |

### `tags`

Common tags applied to all Azure resources:

```hcl
tags = {
  ManagedBy   = "terraform"
  Environment = "production"
  Project     = "netskope-bwan-azure"
}
```

## Deployment Paths

### Option 1: New VNet (standard)

Use when deploying into a fresh Azure environment:

```hcl
azure_network_config = {
  subscription_id       = "YOUR-SUBSCRIPTION-ID"
  location              = "westeurope"
  resource_group_name   = "rg-netskope-bwan"
  create_resource_group = true
  create_vnet           = true
  vnet_cidr             = "10.100.0.0/22"
}
```

Terraform creates the resource group, VNet, all subnets, NSGs, route tables, and the Route Server.

### Option 2: Existing VNet

Use when the VNet already exists:

```hcl
azure_network_config = {
  subscription_id       = "YOUR-SUBSCRIPTION-ID"
  location              = "westeurope"
  resource_group_name   = "rg-netskope-bwan"
  create_resource_group = false
  create_vnet           = false
  vnet_id               = "/subscriptions/.../providers/Microsoft.Network/virtualNetworks/my-vnet"
  vnet_cidr             = "10.100.0.0/22"   # must match the actual VNet CIDR
}
```

Terraform creates gateway subnets, NSGs, route tables, public IPs, NICs, VMs, and the Route Server within the existing VNet. It does not modify the VNet itself.

**Important**: The `RouteServerSubnet` must not already exist in the VNet — Terraform creates it. If it already exists (e.g. from a prior deployment), import it into state:

```sh
terraform import 'azurerm_subnet.route_server' \
  '/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/RouteServerSubnet'
```

### Option 3: Existing Resource Group

Any of the options above can use an existing resource group by setting `create_resource_group = false`. The resource group must exist in the specified `location` before deployment.

## Availability Zone Considerations

**Always check zone availability before deploying**, as VM size availability per zone varies by subscription:

```sh
az vm list-skus --location westeurope --size Standard_DS11 --zone true -o table
```

The output shows which zones have `NotAvailableForSubscription` restrictions. Set `availability_zone` in `locals.tf` to zones that show no restriction for your chosen VM size.

For example, if only Zone 3 is available (as with `Standard_DS11_v2` in some subscriptions), set all gateways to Zone 3 in `locals.tf`:

```hcl
availability_zone = "3"  # Only Zone 3 available for this VM size in this subscription
```

For zone-redundant deployments where multiple zones are available, distribute gateways across zones, e.g.:

```hcl
availability_zone = tostring((i % 2) + 1)  # alternates Zone 1, Zone 2, Zone 1, ...
```

If a deployment fails with `SkuNotAvailable`, check zone availability and update `locals.tf` accordingly before re-running `terraform apply`.

## Step-by-Step Deployment

1. Clone the repository and create `terraform.tfvars` (see [Quick Start](QUICKSTART.md))
2. Set Azure and Netskope credentials (see [Authentication](#authentication) above)
3. Run `terraform init`
4. Run `terraform plan -var-file=terraform.tfvars` to preview changes
5. Run `terraform apply -var-file=terraform.tfvars` to deploy

The deployment creates resources in this order:

1. Resource group and VNet (if creating new)
2. NSGs, route tables, subnets (including RouteServerSubnet)
3. Route Server — **this takes ~15–20 minutes**
4. Netskope portal: policy lookup, gateways, interfaces, static routes, BGP config, activation tokens
5. Public IPs and NICs
6. Azure VMs with cloud-init (activation credentials in user-data)
7. BGP/networking configuration via Azure Run Command (activation, FRR BGP config, route setup)
8. SSE monitor deployment via Azure Run Command

The BGP configuration step polls for VM agent readiness and then executes the setup script synchronously. BGP session establishment is verified before completion.

## Scaling

### ECMP Architecture

Both gateways advertise `0.0.0.0/0` to the Route Server with identical MED values and BGP attributes. The Route Server propagates both routes, and Azure ECMP distributes traffic across both gateways. If a gateway's IPsec tunnels go down, the SSE monitor retracts the default route and all traffic reroutes to the remaining healthy gateway.

### Changing Gateway Count

Adjust `gateway_count` in `terraform.tfvars` and re-apply:

```hcl
gateway_count = 4
```

**Critical**: Before changing `gateway_count`, ensure `azure_route_server.route_server_subnet_cidr` is explicitly pinned in your tfvars (see the [azure_route_server section](#azure_route_server) above). If not pinned, the RouteServerSubnet CIDR auto-formula will produce a different value for the new count, causing Route Server destruction and recreation.

Terraform automatically:
- Creates new gateway subnets, NICs, public IPs, and VMs
- Adds new Route Server BGP connections for the additional gateways
- Runs BGP configuration and SSE monitor deployment on new gateways

Existing gateways are not affected.

## Destruction

To tear down the entire deployment:

```sh
terraform destroy -var-file=terraform.tfvars
```

This removes all Azure resources and Netskope gateway configuration created by the project. The Netskope gateway entries are deactivated and deleted via the provider. The gateway policy is not deleted — it was created outside of Terraform and remains on the tenant.

**Caution**: If resources were manually added to the VNet or Route Server outside of Terraform (e.g. additional subnets, BGP connections), remove them before running `terraform destroy` to avoid dependency errors.

**Route Server**: Route Server deletion takes approximately 5–10 minutes. `terraform destroy` waits for it to complete before proceeding.
