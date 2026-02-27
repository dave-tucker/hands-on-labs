# VRF-Lite Lab

Multi-tenant VRF-Lite lab using Cluster User Defined Networks (CUDNs) and BGP
peering with an upstream router.

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
export KUBECONFIG=$HOME/.kcli/clusters/vrf-lite/auth/kubeconfig
```

### Install platform components

Follow the step-by-step instructions in the
[lab documentation](../../docs/labs/03-vrf-lite/index.md#2-install-platform-components)
to install OVN-Kubernetes (K8s only), enable network features, NMState,
and MetalLB/FRR-K8s.

### Configure and validate

Follow the
[Day 2: Configure & Validate](../../docs/labs/03-vrf-lite/index.md#day-2-configure-validate)
section to apply network configuration and test end-to-end connectivity.

### Teardown

```bash
# OpenShift (default)
./lab.sh down

# Kubernetes
CLUSTER_TYPE=k8s ./lab.sh down
```

## Topology

Two tenants share a single-node cluster. Each tenant has its own CUDN,
VRF, and BGP peering session with an upstream FRR router (R1). External
sites (l1, l2) are directly attached to R1 for end-to-end validation.

## Addressing

| Segment | Subnet | r1 | Nodes / Hosts |
|---|---|---|---|
| BGP peering (both VRFs) | 172.19.0.0/24 | 172.19.0.1 | .10 (ctlplane-0) |
| CUDN tenant1 (pods) | 10.100.1.0/24 | — | Pod IPs |
| CUDN tenant2 (pods) | 10.200.1.0/24 | — | Pod IPs |
| r1 ↔ l1 (tenant1 VRF) | 10.100.2.0/24 | 10.100.2.1 | l1 = 10.100.2.2 |
| r1 ↔ l2 (tenant2 VRF) | 10.200.2.0/24 | 10.200.2.1 | l2 = 10.200.2.2 |
