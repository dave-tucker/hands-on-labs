# BGP-EVPN Lab

CLOS-style spine/leaf topology with eBGP-EVPN. Demonstrates L2 ClusterUserDefinedNetwork (CUDN) with EVPN transport. Pods and an external host (ext-host) share a flat L2 network (10.50.0.0/24) with VXLAN encapsulation over a BGP underlay.

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
[Day 2: Configure & Validate](../../docs/labs/03-bgp-evpn/index.md#day-2-configure-validate)
section: apply VTEP resource, NNCPs (loopback + P2P /31 + static routes),
FRRConfiguration (multi-protocol BGP enabled), RouteAdvertisements (EVPN CUDN selector),
EVPN CUDN, namespaces, and workloads. Validate underlay BGP, EVPN sessions, and L2 connectivity.

### Teardown

```bash
# OpenShift (default)
./lab.sh down

# Kubernetes
CLUSTER_TYPE=k8s ./lab.sh down
```

## Topology

Spine1 (AS 65413) - IPv4 unicast only
Leaf1 (AS 65001), Leaf2 (AS 65002) - IPv4 unicast + L2VPN EVPN
ext-host (AS 65003) - IPv4 unicast + L2VPN EVPN, single-homed to Leaf1
Cluster (AS 65000) - IPv4 unicast + L2VPN EVPN

EVPN full mesh: Leaf1 ↔ Leaf2 ↔ ext-host ↔ cluster nodes (master, worker)

## Addressing

| Segment | Subnet | Purpose |
|---------|--------|--------|
| Underlay (inherited from lab 02) | | |
| Spine1–Leaf1 / Spine1–Leaf2 | 10.10.1.0/31, 10.10.2.0/31 | Core eBGP |
| Leaf1–master / Leaf1–worker | 10.0.1.0/31, 10.0.1.2/31 | P2P + static next-hop |
| Leaf2–master / Leaf2–worker | 10.0.2.0/31, 10.0.2.2/31 | P2P + static next-hop |
| **Leaf1–ext-host** | **10.0.3.0/31** | **P2P + static next-hop** |
| Loopbacks | | |
| Cluster nodes | 192.168.255.1/32, 192.168.255.2/32 | BGP router-id |
| Leaf1, Leaf2 | 192.168.255.11/32, 192.168.255.12/32 | BGP router-id |
| **ext-host** | **192.168.255.13/32** | **BGP router-id** |
| VTEPs | | |
| Cluster nodes | 100.64.0.1/32, 100.64.0.2/32 | VXLAN source IP |
| **ext-host** | **100.64.0.13/32** | **VXLAN source IP** |
| EVPN Overlay | | |
| **L2 CUDN** | **10.50.0.0/24** | **Pod IPAM, flat L2 network** |
| **VNI** | **100** | **VXLAN VNI for MAC-VRF** |
| **ext-host SVI** | **10.50.0.100/24** | **Static IP on br-evpn bridge** |

## Key Features

- **EVPN Transport**: L2 CUDN uses EVPN instead of GENEVE
- **MAC-VRF Only**: Type-2 (MAC/IP) and Type-3 (IMET) routes
- **VXLAN Encapsulation**: VNI 100, VTEP IPs advertised via BGP underlay
- **Full Mesh EVPN**: All EVPN speakers peer directly (no route reflection)
- **L2 Connectivity**: Pods and ext-host share same broadcast domain
- **BFD**: Fast failure detection for all BGP sessions
