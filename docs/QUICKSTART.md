# Quick Start

Minimal steps to deploy a resilient pair of Netskope SD-WAN gateways in Azure.

## Prerequisites

- Terraform >= 1.3, Azure CLI configured (`az login`)
- Netskope SD-WAN tenant with a REST API token
- **Netskope gateway policy** — create a policy in the SD-WAN portal before deploying (the policy name is referenced in `terraform.tfvars`)
- **Marketplace terms accepted** for the Netskope BWAN image (one-time, per subscription):
  ```sh
  az vm image terms accept \
    --publisher netskopebwan \
    --offer netskope-unified-sase-virtual-gateway \
    --plan netskope-unified-sase-virtual-gateway-r6_2_x
  ```
  Or set `accept_plan = true` in `azure_vm_config` to have Terraform accept them on first apply.

## 1. Clone and Configure

```sh
git clone <repository-url>
cd terraform-netskopebwan-azure
cp example.tfvars terraform.tfvars
```

Edit `terraform.tfvars` — at minimum, set these values:

```hcl
azure_network_config = {
  subscription_id     = "YOUR-SUBSCRIPTION-ID"
  location            = "westeurope"          # Azure region
  resource_group_name = "rg-netskope-bwan"
  create_vnet         = true
  vnet_cidr           = "10.100.0.0/22"
}

azure_vm_config = {
  accept_plan    = false   # set true if marketplace terms not yet accepted
  vm_size        = "Standard_DS11_v2"
  admin_password = "YOUR-OS-PASSWORD"   # Azure complexity: 12+ chars, 3 of: upper, lower, digit, special
}

azure_route_server = {
  route_server_subnet_cidr = "10.100.0.64/27"   # pin this value explicitly
}

netskope_tenant = {
  deployment_name = "my-corp-prod"   # used in resource names
  tenant_bgp_asn  = "400"
}

netskope_gateway_config = {
  gateway_policy = "my-azure-policy"   # must already exist on the tenant
  gateway_password = "infiot"
  static_routes  = ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"]
}
```

## 2. Set Credentials

### Azure

```sh
# Interactive login
az login

# Set the subscription (required if you have multiple subscriptions)
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

For CI/CD or service principal authentication, see [Deployment Guide — Authentication](DEPLOYMENT_GUIDE.md#authentication).

### Netskope

```sh
export TF_VAR_netskope_tenant_url="your-tenant.infiot.net"
export TF_VAR_netskope_tenant_token="YOUR_API_TOKEN"
```

## 3. Deploy

```sh
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> **Note**: Azure Route Server takes approximately 15–20 minutes to provision. The total apply time is typically 25–35 minutes for a 2-gateway deployment.

## 4. Verify

After a successful apply you will see output like:

```
gateways = {
  "az-gw-1" = {
    availability_zone    = "3"
    bgp_config_applied   = true
    lan_private_ip       = "10.100.0.20"
    sse_monitor_deployed = true
    vm_name              = "az-gw-1-my-corp-prod"
    wan_public_ip        = "20.x.x.x"
  }
  "az-gw-2" = {
    availability_zone    = "3"
    bgp_config_applied   = true
    lan_private_ip       = "10.100.0.52"
    sse_monitor_deployed = true
    vm_name              = "az-gw-2-my-corp-prod"
    wan_public_ip        = "20.x.x.x"
  }
}
route_server_peer_ips = toset([
  "10.100.0.68",
  "10.100.0.69",
])
```

Check gateway status in the Netskope SD-WAN portal — gateways should appear as activated with interfaces up.

Verify BGP sessions on each gateway:

```sh
# SSH to gateway WAN IP, then:
sudo docker exec infiot_spoke vtysh -c "show bgp summary"
```

Both Route Server peer IPs should show `Established`.

## Next Steps

- [Deployment Guide](DEPLOYMENT_GUIDE.md) — All configuration options and variable reference
- [Architecture](ARCHITECTURE.md) — Network topology and BGP design details
- [Operations](OPERATIONS.md) — Day-2 procedures and gateway management
- [Troubleshooting](TROUBLESHOOTING.md) — Diagnostic commands and common issues
