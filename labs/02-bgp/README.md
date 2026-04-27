# BGP (CLOS fabric) Lab

CLOS-style spine/leaf topology with eBGP. BGP sessions run over loopbacks (with
static-route bootstrap) so BFD works correctly. Each cluster node is
multi-homed to both leaves.

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
export KUBECONFIG=$HOME/.kcli/clusters/bgp/auth/kubeconfig
```

### Install platform components

Follow the
[lab documentation](../../docs/labs/02-bgp/index.md#2-install-platform-components)
to install OVN-Kubernetes (K8s only), enable network features (including
routeAdvertisements), NMState, and MetalLB/FRR-K8s.

### Configure and validate

Follow the
[Day 2: Configure & Validate](../../docs/labs/02-bgp/index.md#day-2-configure-validate)
section: apply NNCPs (loopback + P2P /31 + static routes to leaf loopbacks),
then FRRConfiguration (neighbors = leaf loopbacks, ebgpMultiHop, BFD), then
RouteAdvertisements. Validate BGP and BFD sessions.

### Teardown

```bash
# OpenShift (default)
./lab.sh down

# Kubernetes
CLUSTER_TYPE=k8s ./lab.sh down
```

## Topology

Spine1 (AS 65413), Leaf1 (AS 65001), Leaf2 (AS 65002). Cluster AS 65000; each
node peers with both leaves over loopbacks. Primary network remains flat L2;
BGP uses secondary interfaces only.

## Addressing

| Segment | Subnet | Purpose |
|---------|--------|--------|
| Spine1–Leaf1 / Spine1–Leaf2 | 10.10.1.0/31, 10.10.2.0/31 | Core eBGP |
| Leaf1/Leaf2 ↔ OCP nodes | 10.0.1.0/31, 10.0.1.2/31, 10.0.2.0/31, 10.0.2.2/31 | P2P + static next-hop to loopbacks |
| OCP loopbacks | 192.168.255.1/32, 192.168.255.2/32 | BGP session endpoint |
| Leaf loopbacks | 192.168.255.11/32, 192.168.255.12/32 | BGP session endpoint |
