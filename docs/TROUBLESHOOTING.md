# Troubleshooting

## Connecting to a Gateway

Connect via SSH using the WAN public IP (from `terraform output gateways`):

```sh
ssh netskope@<wan-public-ip>
```

Or run commands without SSH via Azure Run Command:

```sh
az vm run-command invoke \
  --resource-group <resource-group> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "ip -br a && docker ps"
```

## Diagnostic Flowchart: Traffic Not Reaching Internet

This flowchart follows the path from a spoke VM to the internet. Start at Step 1 and work forward.

### Step 1: Check Route Server BGP Connections

Work through these three checks in order: Route Server health → BGP connection state → learned/advertised routes.

#### 1a. Route Server health

```sh
az network routeserver show \
  --resource-group <resource-group> \
  --name <route-server-name> \
  --query '{provisioningState:provisioningState, routingState:routingState, asn:virtualRouterAsn, peerIps:virtualRouterIps}' \
  -o json
```

**Pass** — fully provisioned:
```json
{
  "provisioningState": "Succeeded",
  "routingState": "Provisioned",
  "asn": 65515,
  "peerIps": [
    "10.100.0.68",
    "10.100.0.69"
  ]
}
```

**Fail**: `provisioningState` is `Failed` or `Updating`, or `routingState` is not `Provisioned`. If it is still `Updating`, it may still be provisioning (normal for up to ~20 minutes after creation). If `Failed`, check the Azure portal activity log for the error.

The two IPs under `peerIps` are the Route Server BGP peer addresses that each gateway's FRR config must reference. Confirm they match `terraform output route_server_peer_ips`.

#### 1b. BGP connection state

```sh
az network routeserver peering list \
  --resource-group <resource-group> \
  --routeserver <route-server-name> \
  -o table
```

**Pass** — all connections `Succeeded`:
```
Name                           PeerAsn    PeerIp       ProvisioningState    ResourceGroup
-------------------------  ---------  -----------  -------------------  -----------------------
BGP-az-gw-1-my-corp-prod       400        10.100.0.20  Succeeded            rg-netskope-bwan
BGP-az-gw-2-my-corp-prod       400        10.100.0.52  Succeeded            rg-netskope-bwan
```

**Fail**: State is `Failed`, `Updating`, or a gateway is missing from the list.

**If failing**, check:
- Gateway VM is running and BGP sessions are established (Step 2)
- `PeerIp` matches the gateway LAN NIC IP — confirm with `terraform output gateways`
- `PeerAsn` matches `netskope_tenant.tenant_bgp_asn` in your `terraform.tfvars`

#### 1c. Routes learned by the Route Server from each gateway

This confirms the gateway is successfully advertising `0.0.0.0/0` to the Route Server. Run once per BGP connection:

```sh
az network routeserver peering list-learned-routes \
  --resource-group <resource-group> \
  --routeserver <route-server-name> \
  --name <bgp-connection-name> \
  -o json
```

**Pass** — `0.0.0.0/0` present on both Route Server instances (`RouteServiceRole_IN_0` and `RouteServiceRole_IN_1`):
```json
{
  "RouteServiceRole_IN_0": [
    {
      "asPath": "400",
      "localAddress": "10.100.0.68",
      "network": "0.0.0.0/0",
      "nextHop": "10.100.0.20",
      "origin": "EBgp",
      "sourcePeer": "10.100.0.20",
      "weight": 32768
    }
  ],
  "RouteServiceRole_IN_1": [
    {
      "asPath": "400",
      "localAddress": "10.100.0.69",
      "network": "0.0.0.0/0",
      "nextHop": "10.100.0.20",
      "origin": "EBgp",
      "sourcePeer": "10.100.0.20",
      "weight": 32768
    }
  ]
}
```

`RouteServiceRole_IN_0` and `IN_1` are the two Route Server instances (Azure runs them as a redundant pair internally). Both must show the route for full redundancy.

**Fail** — empty arrays mean the gateway has not advertised the default route:
```json
{
  "RouteServiceRole_IN_0": [],
  "RouteServiceRole_IN_1": []
}
```

If empty, the BGP session may be up but the SSE monitor has retracted the default route because no IPsec tunnels to Netskope are ESTABLISHED. Skip ahead to Step 4.

#### 1d. Routes advertised by the Route Server to each gateway

This confirms what the gateway is receiving from the Route Server — normally the VNet CIDR:

```sh
az network routeserver peering list-advertised-routes \
  --resource-group <resource-group> \
  --routeserver <route-server-name> \
  --name <bgp-connection-name> \
  -o json
```

**Pass** — VNet CIDR advertised from both Route Server instances:
```json
{
  "RouteServiceRole_IN_0": [
    {
      "asPath": "65515",
      "localAddress": "10.100.0.68",
      "network": "10.100.0.0/22",
      "nextHop": "10.100.0.68",
      "origin": "Igp",
      "weight": 0
    }
  ],
  "RouteServiceRole_IN_1": [
    {
      "asPath": "65515",
      "localAddress": "10.100.0.69",
      "network": "10.100.0.0/22",
      "nextHop": "10.100.0.69",
      "origin": "Igp",
      "weight": 0
    }
  ]
}
```

The gateway uses this route (VNet CIDR via Route Server) as a return path to reach spoke VMs inside the VNet. If it is missing, check that the gateway's BGP session with the Route Server is `Established` (Step 2) and that the Route Server is fully provisioned (Step 1a).

### Step 2: Check BGP Sessions on Gateway

The gateway must have BGP sessions Established with both Route Server IPs.

```sh
sudo docker exec infiot_spoke vtysh -c "show ip bgp summary"
```

**Pass** — Route Server peers Established:
```
Neighbor        V         AS MsgRcvd MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
169.254.0.10    4        400     155     153        0    0    0 02:20:54            0
169.254.0.11    4        400     155     152        0    0    0 02:20:54            0
10.100.0.68     4      65515      42      41        0    0    0 00:19:36            1
10.100.0.69     4      65515      43      42        0    0    0 00:19:37            1
```

**Fail** — Route Server peers stuck in `Connect`/`Active`:
```
10.100.0.68     4      65515       0       0        0    0    0    never      Connect
10.100.0.69     4      65515       0       0        0    0    0    never      Connect
```

If peers show `Connect` or `Active`, the gateway cannot reach the Route Server IPs. Continue to Step 3.

**Check gateway is advertising the default route to the Route Server**:

```sh
sudo docker exec infiot_spoke vtysh -c "show ip bgp neighbors 10.100.0.68 advertised-routes"
```

**Pass** — default route advertised:
```
   Network          Next Hop            Metric LocPrf Weight Path
*> 0.0.0.0/0        0.0.0.0                 10         32768 ?
```

**Fail** — no routes advertised. The SSE monitor has retracted the default route because no SSE tunnels are established — skip to Step 4.

**Common causes of BGP failure**:
- Route Server subnet route not installed (the gateway cannot reach the RS peer IPs). Check `ip route get 10.100.0.68` — it must route via the LAN interface, not the WAN. If missing, re-run the BGP config: `terraform apply -replace='null_resource.gre_config["az-gw-1"]' -var-file=terraform.tfvars`
- FRR container not running: check `sudo docker ps` — `infiot_spoke` must be listed
- `tenant_bgp_asn` mismatch: the ASN in `frrcmds-user.json` must match `netskope_tenant.tenant_bgp_asn`

### Step 3: Check Route Server Subnet Reachability

The Route Server peer IPs are in the `RouteServerSubnet`, which is in a different subnet from the gateway LAN NIC. A route must be present on the gateway host to reach it via the LAN interface.

```sh
# Check the route to the Route Server subnet
ip route show | grep 10.100.0.64   # or your RouteServerSubnet

# Verify a specific RS peer IP routes via the LAN interface
ip route get 10.100.0.68
```

**Pass** (routes via LAN interface, e.g. `eth1`):
```
10.100.0.68 via 10.100.0.17 dev eth1 src 10.100.0.20
```

**Fail** (routes via WAN interface, or no route):
```
10.100.0.68 dev eth0 src 20.x.x.x
```

If the route is missing or incorrect:

```sh
# Manually re-add (replace with your actual values)
LAN_GW="10.100.0.17"   # first IP of LAN subnet (.1)
LAN_INTF="eth1"         # LAN NIC name (detect with: ip addr | grep 10.100.0.20)
ip route replace 10.100.0.64/27 via $LAN_GW dev $LAN_INTF
```

To persist permanently, re-apply the BGP configuration:

```sh
terraform apply -replace='null_resource.gre_config["az-gw-1"]' -var-file=terraform.tfvars
```

**Common causes**:
- Container restart clears host routes. The BGP config script re-adds the route after container restart, but a later manual restart may have cleared it.
- LAN interface detection failed — the script auto-detects the LAN NIC by matching `LAN_IP`. Check that the LAN NIC has the expected IP: `ip addr show`.

### Step 4: Check SSE Tunnels (IPsec to Netskope)

The gateway establishes IPsec tunnels to Netskope NewEdge POPs. The SSE monitor only advertises the default route via BGP when at least one tunnel is ESTABLISHED.

```sh
sudo docker exec infiot_spoke ikectl show sa 2>/dev/null | grep "^iked_sas:.*ESTABLISHED" | wc -l
```

**Pass**: Count is >= 1. Example output (3 established tunnels):
```
iked_sas: ... 20.x.x.x:4500->34.225.x.x:4500<...> ESTABLISHED ...
iked_sas: ... 20.x.x.x:4500->44.246.x.x:4500<...> ESTABLISHED ...
iked_sas: ... 20.x.x.x:4500->34.68.x.x:4500<...>  ESTABLISHED ...
```

**Fail**: Count is 0 — no tunnels established.

```sh
# Check SSE monitor status
systemctl status sse_monitor
journalctl -u sse_monitor --no-pager -n 50
tail -50 /var/log/sse_monitor.log
```

**Common causes**:
- **Gateway not activated**: Run `infhostd status` or check the Netskope portal — the gateway must show as `Activated`.
- **WAN NSG blocking UDP/4500**: The Public NSG must allow `UDP/4500` inbound and outbound.
- **Docker not running**: `systemctl status docker`
- **Container not started**: `docker ps` — `infiot_spoke` must be running
- **FRR JSON files missing**: Check `ls /root/sse_monitor/`. If missing, re-deploy the SSE monitor: `terraform apply -replace='null_resource.sse_monitor["az-gw-1"]' -var-file=terraform.tfvars`

### Step 5: Check Netskope Overlay Connectivity

If SSE tunnels are up but traffic still doesn't flow, check the Netskope overlay BGP sessions (iBGP inside the container).

```sh
sudo docker exec -it infiot_spoke bash
/opt/infiot/bin/infcli.py --overlays
```

**Pass** — overlay paths up:
```
OverlayIP       Link      LocalIP      RemoteIP             Role   LocalUP   RemoteUP   Latency   PMTU
169.254.0.10    eth0     20.x.x.x    34.225.x.x     SPOKE|CONTROLLER  True    True        10   1500
169.254.0.11    eth0     20.x.x.x    44.246.x.x     SPOKE|CONTROLLER  True    True        10   1500
169.254.0.1     eth0     20.x.x.x    34.68.x.x           SPOKE|DC   True    True        10   1460
```

**Fail**: Empty output, or `LocalUP`/`RemoteUP` showing `False`.

**Check container interfaces** — all should show `L3State UP`:

```sh
/opt/infiot/bin/infcli.py --show_int
```

**Check container routing table**:

```sh
/opt/infiot/bin/infcli.py --rt
```

Key routes to verify:
- `0.0.0.0/0` with `rtype=def` — default route via the overlay (internet traffic goes through Netskope)
- `0.0.0.0/0` with `rtype=wan` — WAN fallback (used for initial SSE tunnel establishment)

## Deployment Issues

### Azure Run Command Fails: `mktemp` Error

**Symptom**: `terraform apply` fails at `null_resource.gre_config` with `mktemp: mkstemp failed: File exists`.

**Cause**: A previous failed Terraform run left a temp file at the path `mktemp` tried to use.

**Resolution**: Clean up stale temp files, then re-apply:

```sh
rm -f "${TMPDIR:-/tmp}"/az_run_*.sh "${TMPDIR:-/tmp}"/az_sse_*.sh
terraform apply -replace='null_resource.gre_config["az-gw-1"]' -var-file=terraform.tfvars
```

### VM Already Exists Error on Apply

**Symptom**: `Error: A resource with the ID ".../virtualMachines/..." already exists — to be managed via Terraform this resource needs to be imported into the State.`

**Cause**: A previous apply created the VM in Azure but failed before writing it to Terraform state.

**Resolution**: Import the existing VM:

```sh
terraform import \
  'azurerm_linux_virtual_machine.gateways["az-gw-1"]' \
  '/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm-name>'
terraform apply -var-file=terraform.tfvars
```

### Marketplace Plan Error

**Symptom**: `VMMarketplaceInvalidInput` or `The plan is required for marketplace images`.

**Cause**: The Marketplace image requires a `plan` block in the VM resource, and the image terms must be accepted before first deployment.

**Resolution**: Accept the Marketplace terms (once per subscription):

```sh
az vm image terms accept \
  --publisher netskopebwan \
  --offer netskope-unified-sase-virtual-gateway \
  --plan netskope-unified-sase-virtual-gateway-r6_2_x
```

Or set `accept_plan = true` in `azure_vm_config` — Terraform creates an `azurerm_marketplace_agreement` resource to accept the terms.

### VM Size Not Available in Zone

**Symptom**: `SkuNotAvailable` error — the requested VM size is not available in the requested zone.

**Resolution**: Check which zones and sizes are available in your subscription:

```sh
az vm list-skus --location westeurope --size Standard_DS11 --zone true -o table
```

Then either select a different zone in `locals.tf` (the `availability_zone` expression) or choose a compatible VM size.

**Important**: The Netskope BWAN image is Gen1. Gen2-only VM SKUs (e.g. many `v6` series) will not work. Filter for Gen1-compatible sizes:

```sh
az vm list-skus --location westeurope --all \
  --query "[?capabilities[?name=='HyperVGenerations' && contains(value,'V1')]].name" \
  -o tsv | grep -i Standard_D
```

### Provider Authentication Errors

**Symptom**: `Error: failed to authenticate` from the `netskopebwan` provider.

**Cause**: Invalid or expired `tenant_token`, incorrect `tenant_url`, or network connectivity issues.

**Verify connectivity**:

```sh
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer <token>" \
  "https://<tenant>.api.infiot.net/api/v1/policy"
```

Expected: `200`. If you see `401`, the token is invalid. If you see a connection error, check network connectivity to the Netskope API endpoint.

### Route Server Provisioning Timeout

**Symptom**: `terraform apply` fails with a timeout during Route Server creation.

**Cause**: Route Server normally takes 15–20 minutes. In some cases it takes longer.

**Resolution**: Check the Route Server status in the Azure portal or CLI:

```sh
az network routeserver show \
  --name RouteServer-<deployment_name> \
  --resource-group <rg> \
  --query provisioningState
```

If `provisioningState` is `Succeeded`, re-run `terraform apply` to pick up where it left off. Terraform will detect the existing Route Server in state and continue.

### Terraform Destroy Failures

**Symptom**: `terraform destroy` fails with dependency errors.

**Common causes**: Resources manually added to the VNet, NICs in use by other resources, or the Route Server has BGP connections not managed by Terraform.

**Resolution**: Remove manually-created resources first, then destroy in stages if needed:

```sh
terraform destroy -target=null_resource.sse_monitor
terraform destroy -target=null_resource.gre_config
terraform destroy -target=azurerm_linux_virtual_machine.gateways
terraform destroy -target=azurerm_route_server.this
```

### Route Server BGP Connection Delete Timeout

**Symptom**: `terraform destroy` fails after ~30 minutes with:

```
Error: deleting Virtual Hub BGP Connection ... polling after VirtualHubBgpConnectionDelete: context deadline exceeded
```

**Cause**: Azure's Route Server BGP connection deletion API is slow and frequently exceeds Terraform's 30-minute polling timeout. This is a known Azure platform issue — the deletion is usually still in progress (or may have actually succeeded) when the timeout fires.

**Resolution**: Delete the stuck BGP connection(s) manually via the CLI, then re-run `terraform destroy`:

```sh
# List BGP connections to find stuck ones
az network routeserver peering list \
  --resource-group <resource-group> \
  --routeserver <route-server-name> \
  --subscription <subscription-id> \
  -o table

# Delete each stuck connection
az network routeserver peering delete \
  --resource-group <resource-group> \
  --routeserver <route-server-name> \
  --name <bgp-connection-name> \
  --subscription <subscription-id> \
  --yes

# Re-run destroy — Terraform will skip already-deleted resources
TF_VAR_netskope_tenant_token="$INFIOT_API_KEY" terraform destroy -auto-approve -var-file=terraform.tfvars
```

For this deployment the values are:

```sh
az network routeserver peering delete \
  --resource-group rg-netskope-bwan-bespin \
  --routeserver RouteServer-azure-irl \
  --name BGP-az-irl-gw-1-azure-irl \
  --subscription c874f635-1e7e-4be6-a807-5fd3bbffe71a \
  --yes

az network routeserver peering delete \
  --resource-group rg-netskope-bwan-bespin \
  --routeserver RouteServer-azure-irl \
  --name BGP-az-irl-gw-2-azure-irl \
  --subscription c874f635-1e7e-4be6-a807-5fd3bbffe71a \
  --yes
```

## Gateway Commands Quick Reference

Commands run on the gateway host after SSH or Azure Run Command.

### Network

```sh
ip -br a                              # interfaces summary
ip route                              # system routing table
ip route get <dest-ip>                # trace route for a specific destination
ip neighbor                           # ARP table
```

### Gateway Management

```sh
infhostd version                      # firmware version
infhostd status                       # gateway activation status
infhostd restart-container            # restart the BWAN container
service infhost restart               # restart the infhost service
```

### Container Diagnostics (without entering container)

```sh
sudo docker exec infiot_spoke vtysh -c "show ip bgp summary"
sudo docker exec infiot_spoke vtysh -c "show ip bgp neighbors <peer-ip> advertised-routes"
sudo docker exec infiot_spoke ikectl show sa 2>/dev/null | grep "^iked_sas:.*ESTABLISHED" | wc -l
sudo docker ps
```

### Container Diagnostics (inside container)

```sh
sudo docker exec -it infiot_spoke bash
/opt/infiot/bin/infcli.py --overlays       # overlay paths and IPsec tunnels
/opt/infiot/bin/infcli.py --show_int       # interfaces
/opt/infiot/bin/infcli.py --rt             # routing table
```

### Flow Inspection

```sh
infhostd click-dump --help             # show flows
```

## Known Limitations

1. **Single policy**: All gateways share one Netskope policy (`gateway_policy`). Per-gateway policy assignment is not supported.
2. **Route Server ASN**: Fixed at 65515 by Azure. The `tenant_bgp_asn` must not be 65515.
3. **Route Server provisioning time**: ~15–20 minutes. Applies to both creation and deletion.
4. **RouteServerSubnet CIDR**: Must be named exactly `RouteServerSubnet` (Azure requirement). Only one Route Server is allowed per VNet.
5. **Run Command output limit**: Azure Run Command output is capped at ~4 KB. Long script outputs are truncated. The scripts write to the gateway's local filesystem for full output.
6. **Sequential Run Command execution**: The `local-exec` provisioner for each gateway's BGP config runs serially (one gateway at a time).
7. **Provider version pinning**: The `netskopebwan` provider is pinned to `0.0.2`. Newer versions may introduce breaking changes.
8. **Host routes cleared on container restart**: The Route Server subnet route added by the BGP config script may be cleared when the `infiot_spoke` container restarts. The script re-adds it after each restart; manual restarts require the route to be re-added manually or by re-running `null_resource.gre_config`.
