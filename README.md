# Netskope SD-WAN Gateway — Azure Terraform Project

Deploys and activates a resilient pair of Netskope SD-WAN (BWAN) gateways in Azure with automated BGP peering through an Azure Route Server. This project handles the full lifecycle: VNet networking, Netskope portal configuration, Azure VM provisioning, and post-launch BGP setup via Azure Run Command.

## When to Use This Project

This project implements Netskope Borderless SD-WAN with BGP — the recommended approach for steering Azure workload traffic through Netskope for security inspection. It is transparent to applications: no agents, no code changes, no per-instance configuration.

### How It Works

BWAN Gateways run as Azure Virtual Machines in a dedicated VNet, with their LAN interfaces peering directly with an Azure Route Server via eBGP. Each gateway establishes IPsec tunnels to Netskope NewEdge Data Planes and runs BGP sessions with the Route Server to exchange routing information. Azure UDRs (route tables) on spoke subnets direct internet-bound traffic to the gateways for inspection by Netskope.

### ECMP and High Availability

Each gateway originates a default route (0.0.0.0/0) over its BGP sessions to the Route Server, advertising it with equal MED values across all gateways. The Route Server learns these routes and propagates them through the VNet. Because both gateways advertise the same prefix with matching BGP attributes, traffic is distributed across gateways using Equal-Cost Multi-Path (ECMP) routing. If a gateway goes down, its BGP sessions drop and traffic automatically reroutes to the remaining healthy gateway.

The default deployment uses 2 gateways distributed across two Azure availability zones. The project supports up to 8 gateways (the Route Server BGP connection limit per Route Server is higher; the soft cap of 8 in `variables.tf` can be raised).

### Applicable Workloads

Any Azure workload that routes outbound traffic via a default route (0.0.0.0/0) through a UDR — application VMs, containers, AKS nodes, Azure Batch — benefits from Netskope inspection without modification.

## Architecture

```
                    ┌──────────────────────────────────────┐
                    │       Netskope SD-WAN Portal         │
                    │  (Policy, Gateways, BGP, Activation) │
                    └──────────┬───────────────────────────┘
                               │ REST API (netskopebwan provider)
    ┌──────────────────────────┼──────────────────────────────────────┐
    │  Azure Region            │                                      │
    │                          │                                      │
    │  ┌───────────────────────▼─────────────────────────────────┐   │
    │  │  VNet (vnet_cidr)                                       │   │
    │  │                                                         │   │
    │  │  ┌────────────────┐    ┌─────────────────┐              │   │
    │  │  │ GW-1 (Zone 3)  │    │ GW-2 (Zone 2)   │             │   │
    │  │  │ ┌────────────┐ │    │ ┌────────────┐  │             │   │
    │  │  │ │ ge1 (WAN)  │◄┼─PIP─►│ ge1 (WAN)  │◄─┼─PIP        │   │
    │  │  │ │ Public NSG │ │    │ │ Public NSG │  │             │   │
    │  │  │ └────────────┘ │    │ └────────────┘  │             │   │
    │  │  │ ┌────────────┐ │    │ ┌────────────┐  │             │   │
    │  │  │ │ ge2 (LAN)  │ │    │ │ ge2 (LAN)  │  │             │   │
    │  │  │ │ Private NSG│ │    │ │ Private NSG│  │             │   │
    │  │  │ └──────┬─────┘ │    │ └──────┬─────┘  │             │   │
    │  │  └────────┼───────┘    └────────┼─────────┘            │   │
    │  │           │ eBGP (ASN 400)      │ eBGP (ASN 400)       │   │
    │  │  ┌────────▼─────────────────────▼──────────────────┐   │   │
    │  │  │  RouteServerSubnet (/27)                         │   │   │
    │  │  │  Azure Route Server  (ASN 65515, fixed)          │   │   │
    │  │  │  ├── Peer IP 1  ←─ BGP sessions from GW-1, GW-2 │   │   │
    │  │  │  └── Peer IP 2  ←─ BGP sessions from GW-1, GW-2 │   │   │
    │  │  └─────────────────────────────────────────────────┘   │   │
    │  └─────────────────────────────────────────────────────────┘   │
    └─────────────────────────────────────────────────────────────────┘
```

Each gateway peers with both Route Server IPs for redundancy. The Route Server ASN (65515) is fixed by Azure and cannot be changed.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed network topology, resource inventory, and BGP design.

## Quick Start

```sh
git clone <repository-url>
cd terraform-netskopebwan-azure
cp example.tfvars terraform.tfvars
# Edit terraform.tfvars — fill in subscription ID, resource group, policy name, passwords

export TF_VAR_netskope_tenant_url="your-tenant.infiot.net"
export TF_VAR_netskope_tenant_token="YOUR_API_TOKEN"

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

See [docs/QUICKSTART.md](docs/QUICKSTART.md) for a step-by-step walkthrough with expected outputs.

## Prerequisites

- **Terraform** >= 1.3 with providers: `azurerm ~> 3.0`, `netskopebwan 0.0.2`, `null ~> 3.0`, `time ~> 0.7`
- **Azure CLI** (`az`) installed and authenticated (`az login`)
- **Azure subscription** with permissions to create VNet, VM, Route Server, NSG, public IP, and run-command resources (see [docs/RBAC_PERMISSIONS.md](docs/RBAC_PERMISSIONS.md))
- **Netskope SD-WAN tenant** with tenant URL and a REST API token
- **Netskope gateway policy** created in the SD-WAN portal before deploying (the policy name is referenced in `terraform.tfvars`)
- **Marketplace terms accepted** for the Netskope BWAN image — either set `accept_plan = true` in `azure_vm_config`, or run:
  ```sh
  az vm image terms accept \
    --publisher netskopebwan \
    --offer netskope-unified-sase-virtual-gateway \
    --plan netskope-unified-sase-virtual-gateway-r6_2_x
  ```

## VM Image

The Netskope BWAN gateway runs from an Azure Marketplace image:

| Field | Value |
|---|---|
| Publisher | `netskopebwan` |
| Offer | `netskope-unified-sase-virtual-gateway` |
| SKU / Plan | `netskope-unified-sase-virtual-gateway-r6_2_x` |
| Version | `6.2.5` |
| Generation | Gen1 |

**Important**: This image is Gen1 only. Gen2-exclusive VM sizes (e.g. D2s_v6 series) are not compatible.

**Tested VM size**: `Standard_DS11_v2` (2 vCPU, 14 GB RAM, Gen1 + Gen2 support). Check availability in your region and availability zone:

```sh
az vm list-skus --location <region> --size Standard_DS11 --zone true -o table
```

## Outputs

| Output | Description |
|---|---|
| `gateways` | Map of gateway keys to VM names, public IPs, LAN IPs, zone, and BGP config status |
| `route_server_peer_ips` | Set of two Route Server BGP peer IPs (Route Server ASN is always 65515) |
| `route_server_id` | Azure Route Server resource ID |
| `computed_gateway_map` | Auto-computed gateway configuration (subnets, zones, BGP metrics) |
| `resource_group_name` | Resource group containing all deployed resources |
| `vnet_id` | VNet resource ID |

## Documentation

| Document | Description |
|---|---|
| [Quick Start](docs/QUICKSTART.md) | Get deployed fast — minimal config, credentials, deploy, and verify |
| [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) | Full variable reference, authentication options, deployment paths, scaling |
| [Architecture](docs/ARCHITECTURE.md) | Network topology, resource inventory, BGP design, security layers |
| [Operations](docs/OPERATIONS.md) | Day-2: scaling, gateway replacement, BGP config re-run, monitoring |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Diagnostic flowchart, BGP verification, SSE tunnel checks, common errors |
| [RBAC Permissions](docs/RBAC_PERMISSIONS.md) | Required Azure roles for the Terraform operator and CI/CD |
| [State Management](docs/STATE_MANAGEMENT.md) | Remote backend setup (Azure Storage) |

## License

This project is licensed under the BSD 3-Clause License — see the [LICENSE](LICENSE) file for details.

## Support

Netskope-provided scripts in this and other GitHub projects do not fall under the regular Netskope technical support scope and are not supported by Netskope support services.
