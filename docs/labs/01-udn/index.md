# User Defined Networks (UDN)

Hands-on lab demonstrating L2, L3, and Localnet User Defined Networks with
pod and KubeVirt VM workloads.

## Overview

This lab walks through three UDN topologies across four namespaces. It also
contrasts namespace-scoped `UserDefinedNetwork` with cluster-scoped
`ClusterUserDefinedNetwork`.

- **L3 UDN** (`udn-l3`) -- Primary `UserDefinedNetwork` (namespace-scoped)
  with Layer3 topology. Each node gets a /24 slice of the 10.30.0.0/16
  supernet.
- **L2 ClusterUDN** (`udn-l2-a`, `udn-l2-b`) -- Primary
  `ClusterUserDefinedNetwork` (cluster-scoped) with Layer2 topology spanning
  two namespaces. All pods share a flat 10.20.0.0/24 subnet.
- **Localnet ClusterUDN** (`udn-localnet`) -- Secondary
  `ClusterUserDefinedNetwork` with Localnet topology. Pods and VMs get a
  secondary interface on the 192.168.100.0/24 segment via `br-vlan100`.

!!! info "UDN vs ClusterUDN"

    A **UserDefinedNetwork** is namespace-scoped -- it lives inside a single
    namespace and only affects pods in that namespace.

    A **ClusterUserDefinedNetwork** is cluster-scoped -- it uses a
    `namespaceSelector` to span multiple namespaces with the same network,
    enabling cross-namespace east-west traffic on the UDN.

    In this lab the L3 network uses a UDN (single namespace), while the L2
    and Localnet networks use ClusterUDNs to illustrate the difference.

### Topology

The containerlab topology provides an FRR router (`r1`) that connects the
cluster's default network (virbr0) to an external test host (`ext-host`) via
a transit link. This enables realistic north-south testing without modifying
cluster node routes -- the lab host already serves as the default gateway for
cluster nodes on virbr0 and simply forwards traffic to r1.

```
                 ┌───────────┐
                 │ ext-host  │
                 │ 172.16.0.1│
                 └─────┬─────┘
                  eth1 │ 172.16.0.0/31
                  eth3 │
                 ┌─────┴─────┐
                 │    r1     │
                 │   (FRR)   │
          eth1 ──┤           ├── eth2
                 └──┬─────┬──┘
     10.99.0.0/31   │     │  192.168.100.0/24
         host link  │     │  br-vlan100
                    │     │
         ┌──────────┘     └──────────┐
         │                           │
  ┌──────┴──────┐          ┌─────────┴─────────┐
  │  lab host   │          │  localnet pods/VMs │
  │ virbr0      │          │  secondary iface   │
  │ 192.168.122.1│         └───────────────────┘
  └──────┬──────┘
         │ 192.168.122.0/24
  ┌──────┴──────┐
  │cluster nodes│
  │ default gw: │
  │ 192.168.122.1│
  └─────────────┘
```

### Addressing

| Segment | Subnet | Notes |
|---------|--------|-------|
| Default network (virbr0) | 192.168.122.0/24 | cluster nodes, lab host at .1 |
| Host link (r1 ↔ host) | 10.99.0.0/31 | host at .0, r1 at .1 |
| Transit (r1 ↔ ext-host) | 172.16.0.0/31 | r1 at .0, ext-host at .1 |
| br-vlan100 (localnet) | 192.168.100.0/24 | r1 at .1, pods/VMs on secondary iface |
| L3 UDN (pods) | 10.30.0.0/16 | hostSubnet /24 per node |
| L2 ClusterUDN (pods) | 10.20.0.0/24 | flat, shared across nodes and namespaces |

---

## Day 1: Deploy

### 1. Deploy the cluster and containerlab topology

From the `labs/01-udn` directory:

=== "OpenShift"

    ```bash
    ./lab.sh up
    ```

=== "Kubernetes"

    ```bash
    CLUSTER_TYPE=k8s ./lab.sh up
    ```

The entry script will:

- Create the `br-vlan100` bridge
- Deploy the containerlab topology (r1 router, ext-host, host link)
- Provision a 2-node cluster via kcli (1 control plane + 1 worker)

Once the cluster is up, set your kubeconfig:

```bash
export KUBECONFIG=$HOME/.kcli/clusters/udn/auth/kubeconfig
```

### 2. Install platform components

Install the following components in order. Each section has platform-specific
instructions — select the tab matching your cluster type.

--8<-- "install-ovn-kubernetes.md"

--8<-- "enable-network-features.md"

--8<-- "install-nmstate.md"

--8<-- "install-kubevirt.md"

---

## Day 2: Configure & Validate

### Apply networking configuration

#### Create the namespaces

```bash
kubectl apply -f config/00-namespaces.yaml
```

This creates four namespaces:

| Namespace | Labels | Purpose |
|-----------|--------|---------|
| `udn-l3` | `primary-user-defined-network` | L3 UDN (namespace-scoped) |
| `udn-l2-a` | `primary-user-defined-network`, `network-role: l2-udn` | L2 ClusterUDN |
| `udn-l2-b` | `primary-user-defined-network`, `network-role: l2-udn` | L2 ClusterUDN |
| `udn-localnet` | `network-role: localnet` | Localnet ClusterUDN (secondary) |

#### Apply the NNCPs

The NNCP creates an OVS bridge (`ovs-br-vlan100`) with the node's `ens4`
interface (connected to `br-vlan100`) and maps it to OVN's `localnet100`
bridge mapping.

!!! warning "NNCPs must be applied before the Localnet CUDN"
    The OVS bridge mapping must exist on the nodes before the Localnet
    `ClusterUserDefinedNetwork` is created. Apply the NNCPs first and wait
    for them to succeed.

```bash
kubectl apply -f config/02-nncps.yaml
```

Watch for all enactments to become `Available`:

```bash
kubectl get nnce -w
```

#### Create the UDNs

```bash
kubectl apply -f config/01-udns.yaml
```

This creates three network resources:

- **`l3-primary`** -- a `UserDefinedNetwork` in `udn-l3` (Layer3, Primary)
- **`l2-primary`** -- a `ClusterUserDefinedNetwork` selecting namespaces with
  `network-role: l2-udn` (Layer2, Primary)
- **`localnet-secondary`** -- a `ClusterUserDefinedNetwork` selecting
  namespaces with `network-role: localnet` (Localnet, Secondary)

Verify the UDNs are ready:

```bash
kubectl get userdefinednetwork -A
kubectl get clusteruserdefinednetwork
```

#### Deploy the test workloads

```bash
kubectl apply -f config/03-workloads.yaml
```

This creates:

- 2 pods in `udn-l3` (one per node for east-west testing)
- 2 pods in `udn-l2-a` (one per node) + 1 pod in `udn-l2-b` (cross-namespace)
- 1 KubeVirt VM in `udn-l2-a`
- 2 KubeVirt VMs in `udn-localnet` (static IPs via cloud-init: `.20` and `.21`)

Wait for all pods to be running:

```bash
kubectl get pods -A -l app=network-tools -o wide
```

Wait for VMs to be ready:

```bash
kubectl get vmi -A
```

---

### Validate

#### L3 UDN -- East-West

`kubectl get pods -o wide` shows the default network IP, not the UDN IP.
Use the `network-status` annotation to get the UDN IP (the entry with
`"default": true` is the primary UDN interface):

```bash
L3_POD1_IP=$(kubectl get pod -n udn-l3 l3-pod-1 \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
L3_POD2_IP=$(kubectl get pod -n udn-l3 l3-pod-2 \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
echo "l3-pod-1: $L3_POD1_IP  l3-pod-2: $L3_POD2_IP"
```

Ping between the two pods:

```bash
kubectl exec -n udn-l3 l3-pod-1 -- ping -c 3 "$L3_POD2_IP"
```

The pods are on different nodes and communicate over the L3 UDN. Each node
has its own /24 subnet, so traffic is routed through OVN.

#### L3 UDN -- North-South

Ping ext-host to verify north-south via the UDN gateway. Traffic exits OVN,
is SNATed to the node IP, routed through the lab host to r1, then to
ext-host:

```bash
kubectl exec -n udn-l3 l3-pod-1 -- ping -c 3 172.16.0.1
```



#### L2 ClusterUDN -- East-West (same namespace)

```bash
L2_POD1_IP=$(kubectl get pod -n udn-l2-a l2-pod-1 \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
L2_POD2_IP=$(kubectl get pod -n udn-l2-a l2-pod-2 \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
echo "l2-pod-1: $L2_POD1_IP  l2-pod-2: $L2_POD2_IP"
```

```bash
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 "$L2_POD2_IP"
```

Both pods share the flat 10.20.0.0/24 subnet. Traffic between nodes is
bridged at Layer 2 by OVN.

#### L2 ClusterUDN -- East-West (cross-namespace)

Because the L2 ClusterUDN spans both `udn-l2-a` and `udn-l2-b`, pods in
different namespaces share the same flat network:

```bash
L2_PODB_IP=$(kubectl get pod -n udn-l2-b l2-pod-b \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 "$L2_PODB_IP"
```

!!! success "ClusterUDN cross-namespace connectivity"

    This demonstrates the key difference from a namespace-scoped UDN: pods
    in `udn-l2-a` and `udn-l2-b` can communicate directly because the
    ClusterUDN spans both namespaces.

#### L2 ClusterUDN -- North-South

```bash
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 172.16.0.1
```

#### L2 ClusterUDN -- VM connectivity

Check the VM is running and get its IP:

```bash
kubectl get vmi -n udn-l2-a
```

Ping from a pod to the VM (replace `<l2-vm-IP>` with the VMI IP):

```bash
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 <l2-vm-IP>
```

#### Localnet ClusterUDN -- VM connectivity

IPAM is disabled on the localnet CUDN. Both VMs have statically assigned
IPs via cloud-init: `localnet-vm-1` at `192.168.100.20` and `localnet-vm-2`
at `192.168.100.21`.

Check both VMs are running:

```bash
kubectl get vmi -n udn-localnet
```

!!! tip "VM credentials"
    All VMs in this lab are configured via cloud-init with user `ovnkube`
    and password `ovnrocks!`.

##### East-west between VMs

Console into `localnet-vm-1` and ping `localnet-vm-2`:

```bash
kubectl virt console localnet-vm-1 -n udn-localnet
# once logged in:
ping -c 3 192.168.100.21
```

##### North-south via r1

Ping r1 from `localnet-vm-1` to verify the bridge mapping:

```bash
kubectl virt console localnet-vm-1 -n udn-localnet
# once logged in:
ping -c 3 192.168.100.1
```

Ping ext-host (through r1) to verify north-south routing:

```bash
ping -c 3 172.16.0.1
```

From ext-host, ping the VMs to verify bidirectional connectivity:

```bash
docker exec clab-udn-ext-host ping -c 3 192.168.100.20
docker exec clab-udn-ext-host ping -c 3 192.168.100.21
```

---

## Teardown

From the `labs/01-udn` directory:

=== "OpenShift"

    ```bash
    ./lab.sh down
    ```

=== "Kubernetes"

    ```bash
    CLUSTER_TYPE=k8s ./lab.sh down
    ```

This will:

1. Destroy the containerlab topology (r1, ext-host, host link auto-cleaned)
2. Delete the kcli cluster and its VMs
3. Remove the `br-vlan100` bridge
