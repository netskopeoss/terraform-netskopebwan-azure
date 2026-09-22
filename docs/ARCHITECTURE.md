# Architecture

## Network Topology

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
    │  │  ┌─────────────────────┐  ┌─────────────────────┐       │   │
    │  │  │   GW-1 (Zone 3)     │  │   GW-2 (Zone 3)     │       │   │
    │  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │       │   │
    │  │  │  │  ge1  (WAN)   │◄─┼PIP  │  ge1  (WAN)   │◄─┼PIP   │   │
    │  │  │  │  Public NSG   │  │  │  │  Public NSG   │  │       │   │
    │  │  │  └───────────────┘  │  │  └───────────────┘  │       │   │
    │  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │       │   │
    │  │  │  │  ge2  (LAN)   │  │  │  │  ge2  (LAN)   │  │       │   │
    │  │  │  │  Private NSG  │  │  │  │  Private NSG  │  │       │   │
    │  │  │  └───────┬───────┘  │  │  └───────┬───────┘  │       │   │
    │  │  └──────────┼──────────┘  └──────────┼──────────┘       │   │
    │  │             │ eBGP                    │ eBGP             │   │
    │  │             │ (ASN 400 → 65515)       │ (ASN 400 → 65515)│   │
    │  │  ┌──────────▼─────────────────────────▼──────────────┐  │   │
    │  │  │  RouteServerSubnet (/27)                           │  │   │
    │  │  │  Azure Route Server  (ASN 65515, Azure-managed)   │  │   │
    │  │  │  ├── Peer IP 1  (e.g. 10.100.0.68)                │  │   │
    │  │  │  └── Peer IP 2  (e.g. 10.100.0.69)                │  │   │
    │  │  └───────────────────────────────────────────────────┘  │   │
    │  └─────────────────────────────────────────────────────────┘   │
    └─────────────────────────────────────────────────────────────────┘
```

Each gateway's LAN NIC (ge2) peers with both Route Server IPs. Each gateway therefore
maintains four BGP sessions total: two to the Route Server (one per RS peer IP), and
two Netskope overlay sessions to Netskope NewEdge POPs.

## Traffic Flow

1. **Outbound (spoke VM → Internet)**: Spoke VM → UDR default route → gateway ge1 (WAN) → IPsec tunnel → Netskope NewEdge → Internet
2. **BGP control plane**: Gateway ge2 (LAN IP) ↔ Route Server (both peer IPs) — gateway advertises `0.0.0.0/0` when SSE tunnels are up; Route Server propagates the route into the VNet
3. **Inbound management**: Operator → Public IP → ge1 (SSH) or via Azure Run Command from the Terraform runner
4. **Netskope overlay**: Gateway ge1 (WAN IP) ↔ Netskope NewEdge POPs via IPsec/UDP 4500

## Subnet Layout

With default settings (`vnet_cidr = 10.100.0.0/22`, `subnet_size = 28`, `gateway_count = 2`):

| Subnet | CIDR | Purpose |
|---|---|---|
| az-gw-1-GE1 | 10.100.0.0/28 | GW-1 WAN (public) |
| az-gw-1-GE2 | 10.100.0.16/28 | GW-1 LAN (private) |
| az-gw-2-GE1 | 10.100.0.32/28 | GW-2 WAN (public) |
| az-gw-2-GE2 | 10.100.0.48/28 | GW-2 LAN (private) |
| RouteServerSubnet | 10.100.0.64/27 | Azure Route Server (required name, /27 minimum) |

The RouteServerSubnet CIDR is auto-computed as the next `/27` block after the gateway subnets. **Pin it explicitly** via `azure_route_server.route_server_subnet_cidr` — the auto-formula shifts if `gateway_count` changes, which would force Route Server destruction and recreation.

## File Responsibilities

| File | Purpose | Key References |
|---|---|---|
| `vnet.tf` | VNet, subnets, NSGs, route tables, Route Server, BGP connections | `local.gateways`, `var.azure_network_config`, `var.azure_route_server` |
| `interfaces.tf` | NICs and Public IPs (per gateway × interface) | `local.gateway_subnets`, `local.gw_public_interfaces` |
| `vm.tf` | Azure VMs with cloud-init (activation token, tenant URL, password) | `local.gateways`, NIC IDs, activation tokens, `var.azure_vm_config` |
| `nsg_config.tf` | Netskope portal: policy, gateways, interfaces, static routes, activation, BGP config | `local.gateways`, NIC private IPs, `var.netskope_gateway_config` |
| `run_command.tf` | Azure Run Command: BGP/networking config and SSE monitor deployment per gateway | VM names, LAN IPs, Route Server peer IPs, activation tokens |
| `locals.tf` | Gateway map auto-computed from `gateway_count`, subnet CIDRs, interface keys | `var.gateway_count`, `var.gateway_prefix`, `var.azure_network_config.vnet_cidr` |
| `output.tf` | Outputs: gateways, Route Server IPs, VNet ID, resource group | All deployed resource IDs |
| `provider.tf` | `azurerm`, `netskopebwan`, `null` provider configurations | `var.azure_network_config.subscription_id` |
| `versions.tf` | Provider version constraints | — |
| `variables.tf` | All input variable declarations with types and defaults | — |
| `scripts/user-data.sh` | Cloud-init: gateway admin password, tenant URL, activation token | Rendered by `templatefile()` in `vm.tf` |
| `scripts/azure_run_command.sh` | Run Command helper: polls VM running state, invokes script synchronously | Called by `local-exec` provisioners in `run_command.tf` |
| `scripts/sse_monitor.sh` | IPsec tunnel health monitor — BGP default route advertisement control | Deployed to `/root/sse_monitor/` on each gateway |
| `scripts/sse_monitor.service` | systemd unit for `sse_monitor.sh` | Deployed to `/etc/systemd/system/` |

## Resource Inventory

### Azure Resources (per deployment)

| Resource | Count | Notes |
|---|---|---|
| Resource Group | 0–1 | Conditional (`create_resource_group`) |
| Virtual Network | 0–1 | Conditional (`create_vnet`) |
| Subnets | 2 × gateway_count + 1 | WAN + LAN per gateway, plus RouteServerSubnet |
| Network Security Groups | 2 | Public (WAN) and Private (LAN) |
| NSG Associations | 2 × gateway_count | Per-NIC associations |
| Route Tables | 2 | Public (→ Internet) and Private |
| Public IPs | gateway_count + 1 | One per WAN NIC (zone-redundant) + one for Route Server |
| NICs | 2 × gateway_count | ge1 (WAN) + ge2 (LAN) per gateway |
| Azure VMs | gateway_count | Netskope BWAN Marketplace image |
| Route Server | 1 | Provisioned in RouteServerSubnet; ~15–20 min to create |
| Route Server BGP Connections | gateway_count | One per gateway (Route Server side) |

### Netskope Portal Resources

| Resource | Count | Notes |
|---|---|---|
| Policy | 1 | Pre-existing; shared across all gateways |
| Gateway | gateway_count | One per deployed VM |
| Gateway Interface | 2 × gateway_count | ge1 + ge2 per gateway |
| Static Route | gateway_count | Instance metadata route (169.254.169.254/32) |
| BGP Config | 2 × gateway_count | Two Route Server peer IPs per gateway |

## BGP Configuration

### Route Server

- **Azure Route Server ASN**: 65515 (fixed — not configurable)
- **Route Server peer IPs**: Two IPs allocated from RouteServerSubnet (e.g. `.68` and `.69`); known only after creation
- **BGP connection**: One `azurerm_route_server_bgp_connection` per gateway, using the gateway's LAN NIC IP as the peer address and `tenant_bgp_asn` as the peer ASN

### Gateway FRR (Free Range Routing)

- **Gateway ASN**: `tenant_bgp_asn` (default: 400; must not be 65515)
- **Peers per gateway**: 2 — both Route Server peer IPs
- **Remote AS**: 65515 (Route Server)
- **Features**: `ebgp-multihop 2`, `disable-connected-check` (required because Route Server IPs are in a different subnet)
- **MED**: Equal across all gateways (ECMP load balancing)
- **Default route advertisement**: Controlled by the SSE monitor — `0.0.0.0/0` is advertised only when at least one IPsec tunnel to Netskope NewEdge is ESTABLISHED

### Route for Route Server Subnet

Because the Route Server peer IPs are in the RouteServerSubnet (a different subnet from the LAN NIC), a host route is required on the gateway to ensure BGP traffic exits via the LAN interface rather than the default WAN route:

```sh
ip route replace <RouteServerSubnet> via <LAN-gateway> dev <LAN-intf>
```

This route is added by the `gre_config` Run Command script (Step 3) and re-added after container restarts.

## Security Layers

### Network Security Groups

| NSG | Direction | Rule | Purpose |
|---|---|---|---|
| Public (WAN) | Ingress | TCP/22 from Internet | SSH management |
| Public (WAN) | Ingress | UDP/4500 from Internet | IPsec NAT-T (SSE tunnels) |
| Public (WAN) | Egress | All | Outbound connectivity |
| Private (LAN) | Ingress | All | Trusted LAN segment |
| Private (LAN) | Egress | All | Trusted LAN segment |

### Public IP Addresses

Public IPs are provisioned as Standard SKU, Static allocation, zone-redundant (`zones = ["1", "2", "3"]`). Zone-redundant IPs remain reachable regardless of which availability zone the attached VM is running in.

## Provider Versions

| Provider | Source | Version | Purpose |
|---|---|---|---|
| `azurerm` | hashicorp/azurerm | ~> 3.0 | Azure infrastructure |
| `netskopebwan` | netskopeoss/netskopebwan | 0.0.2 | Netskope portal configuration |
| `null` | hashicorp/null | ~> 3.0 | Run Command local-exec provisioners |
| `time` | hashicorp/time | ~> 0.7 | API propagation delays |
| Terraform | — | >= 1.3 | Core |
