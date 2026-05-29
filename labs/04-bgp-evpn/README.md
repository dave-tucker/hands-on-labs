# BGP-EVPN Lab

CLOS-style spine/leaf topology with iBGP-EVPN. Demonstrates multi-tenant L2/L3 ClusterUserDefinedNetwork (CUDN) with EVPN transport:

- **Tenant 1 (evpn-l2)**: L2-only MAC-VRF (VNI 100) - pods and ext-host share flat L2 network (10.50.0.0/24)
- **Tenant 2 (evpn-l3)**: L2 MAC-VRF (VNI 200) + L3 IP-VRF (VNI 201) - pods communicate via L2 with ext-host2 (10.60.0.0/24) and L3 with ext-host3 (10.70.0.0/24)

## Quick start

### Deploy

```bash
# OpenShift (default)
./lab.sh up

# Kubernetes
CLUSTER_TYPE=k8s ./lab.sh up
```

### Set kubeconfig

```bash
export KUBECONFIG=$HOME/.kcli/clusters/bgp-evpn/auth/kubeconfig
```

### Install platform components

Follow the
[lab documentation](../../docs/labs/04-bgp-evpn/index.md#2-install-platform-components)
to install OVN-Kubernetes (K8s only), enable network features (including
routeAdvertisements), NMState, and MetalLB/FRR-K8s.

### Configure and validate

Follow the
[Day 2: Configure & Validate](../../docs/labs/04-bgp-evpn/index.md#day-2-configure-validate)
section: apply VTEP resource, NNCPs (loopback + P2P /31 + static routes),
FRRConfiguration (multi-protocol BGP enabled, iBGP AS 65000), RouteAdvertisements (EVPN CUDN selector),
EVPN CUDNs for both tenants, namespaces, and workloads. Validate underlay BGP, EVPN sessions, L2 connectivity (both tenants), and L3 routing (tenant 2 via Type-5 routes).

### Teardown

```bash
# OpenShift (default)
./lab.sh down

# Kubernetes
CLUSTER_TYPE=k8s ./lab.sh down
```

## Topology

All devices use AS 65000 (iBGP throughout):
- **Spine1** - Route reflector for leaves and cluster nodes (L2VPN EVPN), advertises Type-5 routes for ext-host3's network
- **Leaf1, Leaf2** - Route reflectors for cluster nodes and external hosts (IPv4 unicast + L2VPN EVPN)
- **Cluster nodes** (master, worker) - EVPN endpoints for pod networks, route reflector clients
- **ext-host** - L2-only endpoint, single-homed to Leaf1 (Tenant 1, 10.50.0.100/24)
- **ext-host2** - L2-only endpoint, single-homed to Leaf2 (Tenant 2 L2, 10.60.0.100/24)
- **ext-host3** - L3-only endpoint, iBGP with Spine1, advertises 10.70.0.0/24 (Tenant 2 L3)

**iBGP Route Reflection Hierarchy**:
- L2VPN EVPN: Spine1 (RR) ↔ Leaves (RR) ↔ cluster nodes (clients) + ext-hosts (clients)
- IPv4 Unicast: Leaves (RR) ↔ cluster nodes (clients) + ext-hosts (clients)
- Spine1 learns ext-host3's 10.70.0.0/24 via IPv4 unicast and re-advertises as Type-5 EVPN to leaves

## Addressing

| Segment | Subnet | Purpose |
|---------|--------|--------|
| **Underlay** | | |
| Spine1–Leaf1 / Spine1–Leaf2 | 10.10.1.0/31, 10.10.2.0/31 | Core eBGP |
| Spine1–ext-host3 | 10.10.3.0/31 | Tenant 2 L3 endpoint |
| Leaf1–master / Leaf1–worker | 10.0.1.0/31, 10.0.1.2/31 | P2P + static next-hop |
| Leaf2–master / Leaf2–worker | 10.0.2.0/31, 10.0.2.2/31 | P2P + static next-hop |
| Leaf1–ext-host | 10.0.3.0/31 | Tenant 1 L2 endpoint |
| Leaf2–ext-host2 | 10.0.4.0/31 | Tenant 2 L2 endpoint |
| **Loopbacks** | | |
| Cluster nodes | 192.168.255.1/32, 192.168.255.2/32 | BGP router-id |
| Spine1 | 192.168.255.10/32 | BGP router-id |
| Leaf1, Leaf2 | 192.168.255.11/32, 192.168.255.12/32 | BGP router-id |
| ext-host3 | 192.168.255.15/32 | BGP router-id |
| **VTEPs** | | |
| Cluster nodes | 100.64.0.1/32, 100.64.0.2/32 | VXLAN source IP |
| Leaf1, Leaf2 | 100.64.0.11/32, 100.64.0.12/32 | VXLAN source IP |
| ext-host | 100.64.0.13/32 | VXLAN source IP (Tenant 1) |
| ext-host2 | 100.64.0.14/32 | VXLAN source IP (Tenant 2) |
| **Tenant 1 (evpn-l2)** | | |
| L2 CUDN subnet | 10.50.0.0/24 | Pod IPAM, flat L2 network |
| MAC-VRF VNI | 100 | VXLAN VNI |
| IP-VRF VNI | 101 | Type-5 route VNI |
| ext-host | 10.50.0.100/24 | L2-only endpoint on eth1 |
| **Tenant 2 (evpn-l3)** | | |
| L2 CUDN subnet | 10.60.0.0/24 | Pod IPAM, flat L2 network |
| MAC-VRF VNI | 200 | VXLAN VNI |
| IP-VRF VNI | 201 | Type-5 route VNI |
| ext-host2 | 10.60.0.100/24 | L2-only endpoint on eth1 |
| ext-host3 subnet | 10.70.0.0/24 | L3 network (Type-5 EVPN) |

## Key Features

- **EVPN Transport**: L2 CUDNs use EVPN instead of GENEVE
- **Multi-Tenancy**: Two isolated tenants with separate VNIs and route targets
- **MAC-VRF (Type-2/3)**: L2 switching for tenant 1 (VNI 100) and tenant 2 (VNI 200)
- **IP-VRF (Type-5)**: L3 routing for tenant 2 external network (VNI 201)
- **VXLAN Encapsulation**: VTEPs advertised via BGP underlay
- **iBGP with Route Reflection**: 
  - Spine1 is a route reflector for leaves and cluster nodes (L2VPN EVPN only)
  - Leaves are route reflectors for cluster nodes and external hosts (IPv4 unicast + L2VPN EVPN)
  - All devices use AS 65000 to simplify configuration
- **BFD**: Fast failure detection for all BGP sessions
