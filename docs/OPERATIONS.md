# Operations

Day-2 operational procedures for the deployed Netskope SD-WAN gateway infrastructure.

## Scaling Gateways

To add or remove gateways, update `gateway_count` in your `terraform.tfvars` and re-apply.

**Before scaling**: ensure `azure_route_server.route_server_subnet_cidr` is pinned explicitly in `terraform.tfvars`. If it is auto-computed, changing `gateway_count` changes the formula output, causing Route Server destruction.

```hcl
gateway_count = 4   # Scale from 2 to 4 gateways
```

```sh
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

New gateways are assigned the next available subnet CIDRs, zones, and BGP MED values. Existing gateways are not affected.

## Gateway Replacement

To replace a specific gateway VM (e.g. after a firmware upgrade or to change VM size):

```sh
# Force recreation of the VM
terraform apply -replace='azurerm_linux_virtual_machine.gateways["az-gw-1"]' \
  -var-file=terraform.tfvars

# If BGP config also needs to be re-applied, replace it separately after the VM is up:
terraform apply -replace='null_resource.gre_config["az-gw-1"]' \
  -var-file=terraform.tfvars
```

This recreates only the targeted gateway. The Netskope portal configuration (policy, interfaces, BGP) is preserved.

## Rotating the Netskope API Token

1. Generate a new REST API token in the Netskope SD-WAN portal (Accounts → REST API)
2. Update the environment variable: `export TF_VAR_netskope_tenant_token="NEW_TOKEN"`
3. Run `terraform plan` to verify — the plan should show no resource changes (the token is used for provider authentication only, not stored as a resource attribute)

If the token is stored in a secrets manager, update it there and re-run the pipeline.

## Upgrading the Gateway Image

When a new version of the Netskope BWAN Marketplace image is published:

1. Update `azure_vm_config.image_version` in `terraform.tfvars` (or set `"latest"` to auto-select)
2. Run `terraform plan` — the plan shows VM replacement if the image version has changed
3. For a controlled rollout, replace one gateway at a time using `-replace`:
   ```sh
   terraform apply -replace='azurerm_linux_virtual_machine.gateways["az-gw-1"]' \
     -var-file=terraform.tfvars
   ```

**Note**: Check the Netskope release notes for any cloud-init or FRR configuration changes that may require updates to `user-data.sh` or `run_command.tf`.

## Re-Running BGP Configuration

If BGP/networking configuration needs to be re-applied (e.g. after a gateway reboot that cleared routes, or after a firmware upgrade):

```sh
# Re-run BGP/networking config for a specific gateway
terraform apply -replace='null_resource.gre_config["az-gw-1"]' \
  -var-file=terraform.tfvars
```

This re-executes the Azure Run Command on the gateway, which:

1. Re-activates the gateway with the Netskope tenant (`infhostd activate`)
2. Writes the FRR BGP configuration (`frrcmds-user.json`) with Route Server peer IPs and MED values
3. Adds the Route Server subnet route via the LAN interface
4. Adds any `static_routes` via the LAN interface
5. Restarts the `infhost` service and `infiot_spoke` container
6. Verifies BGP neighbors appear in `vtysh show bgp summary`

The activation step is idempotent — if the gateway is already activated, it continues without side effects.

## Re-Deploying the SSE Monitor

The SSE monitor is a separate resource from the BGP config. If the monitor script or FRR JSON files were lost (e.g. disk wiped by firmware upgrade):

```sh
terraform apply -replace='null_resource.sse_monitor["az-gw-1"]' \
  -var-file=terraform.tfvars
```

To re-run both BGP config and SSE monitor on all gateways:

```sh
terraform apply \
  -replace='null_resource.gre_config["az-gw-1"]' \
  -replace='null_resource.gre_config["az-gw-2"]' \
  -replace='null_resource.sse_monitor["az-gw-1"]' \
  -replace='null_resource.sse_monitor["az-gw-2"]' \
  -var-file=terraform.tfvars
```

## Connecting to a Gateway

The gateway OS can be accessed via SSH on the WAN public IP:

```sh
ssh netskope@<wan-public-ip>   # use admin_username from azure_vm_config
```

You can also run ad-hoc commands via Azure Run Command without opening SSH:

```sh
az vm run-command invoke \
  --resource-group <resource-group> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "docker exec infiot_spoke vtysh -c 'show bgp summary'"
```

## BGP Verification

```sh
# Check BGP sessions (must show both Route Server IPs as Established)
sudo docker exec infiot_spoke vtysh -c "show bgp summary"

# Check advertised routes to a Route Server peer
sudo docker exec infiot_spoke vtysh -c "show ip bgp neighbors <RS-peer-IP> advertised-routes"
```

**Expected BGP summary** (2 Netskope overlay peers + 2 Route Server peers):

```
Neighbor        V         AS MsgRcvd MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
169.254.0.10    4        400     155     153        0    0    0 02:20:54            0
169.254.0.11    4        400     155     152        0    0    0 02:20:54            0
10.100.0.68     4      65515      42      41        0    0    0 00:19:36            1
10.100.0.69     4      65515      43      42        0    0    0 00:19:37            1
```

The `169.254.0.x` peers are Netskope overlay peers (iBGP). The `10.100.0.x` peers are the Route Server IPs (eBGP, remote-as 65515).

## Monitoring Recommendations

### Azure Monitor

- **VM Metrics**: CPU utilisation, network in/out, available memory for gateway VMs
- **VM Availability**: `Percentage CPU` and `VM Availability Metric` for alerting on gateway health
- **NSG Flow Logs**: Enable on gateway NSGs for traffic analysis

### Azure Alerts

| Metric | Threshold | Action |
|---|---|---|
| VM CPU Utilisation | > 80% sustained | Consider larger VM size |
| VM Availability | < 100% | Investigate gateway health |

### Netskope Portal

Monitor gateway health, tunnel status, and policy enforcement in the Netskope SD-WAN portal dashboard.

### SSE Monitor

```sh
# Check monitor service status on the gateway
systemctl status sse_monitor

# Recent log entries
journalctl -u sse_monitor --no-pager -n 50
tail -50 /var/log/sse_monitor.log
```

The SSE monitor advertises the default route when at least one IPsec tunnel to Netskope NewEdge is ESTABLISHED, and retracts it when all tunnels go down. Log entries confirm advertisement/retraction events.
