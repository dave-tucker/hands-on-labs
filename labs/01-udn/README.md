# User Defined Networks (UDN)

Hands-on lab demonstrating L2, L3, and Localnet User Defined Networks with
pod and KubeVirt VM workloads.

## Topology

Three UDN topologies across four namespaces. The lab also contrasts
namespace-scoped `UserDefinedNetwork` with cluster-scoped
`ClusterUserDefinedNetwork`.

- **L3 UDN** (`udn-l3`) — Primary `UserDefinedNetwork` with Layer3 topology.
  Each node gets a /24 slice of the 10.30.0.0/16 supernet.
- **L2 ClusterUDN** (`udn-l2-a`, `udn-l2-b`) — Primary
  `ClusterUserDefinedNetwork` with Layer2 topology spanning two namespaces.
  All pods share a flat 10.20.0.0/24 subnet.
- **Localnet ClusterUDN** (`udn-localnet`) — Secondary
  `ClusterUserDefinedNetwork` with Localnet topology. Pods and VMs get a
  secondary interface on the 192.168.100.0/24 segment via `br-vlan100`.

### Containerlab topology

An FRR router (`r1`) connects the cluster's default network (virbr0) to an
external test host (`ext-host`) via a transit link. The lab host acts as the
intermediary — cluster nodes already use it as their default gateway, so a
single host-side route is all that's needed to reach ext-host.

- `r1:eth1` ↔ host namespace (10.99.0.0/31 — host link)
- `r1:eth2` ↔ br-vlan100 (192.168.100.1/24 — localnet gateway)
- `r1:eth3` ↔ ext-host:eth1 (172.16.0.0/31 — transit)

### UDN vs ClusterUDN

A `UserDefinedNetwork` is namespace-scoped — it lives inside a single
namespace and only affects pods in that namespace. A
`ClusterUserDefinedNetwork` is cluster-scoped — it uses a
`namespaceSelector` to span multiple namespaces with the same network,
enabling cross-namespace east-west traffic on the UDN.

### Addressing

| Segment | Subnet | Notes |
|---------|--------|-------|
| Default network (virbr0) | 192.168.122.0/24 | cluster nodes, lab host at .1 |
| Host link (r1 ↔ host) | 10.99.0.0/31 | host at .0, r1 at .1 |
| Transit (r1 ↔ ext-host) | 172.16.0.0/31 | r1 at .0, ext-host at .1 |
| br-vlan100 (localnet) | 192.168.100.0/24 | r1 at .1, pods/VMs secondary iface |
| L3 UDN (pods) | 10.30.0.0/16 | hostSubnet /24 per node |
| L2 ClusterUDN (pods) | 10.20.0.0/24 | flat, shared across nodes & namespaces |

## Deploy

### 1. Deploy the cluster and containerlab topology

From this directory, choose your cluster type:

**OpenShift (default):**

```bash
./lab.sh up
```

**Vanilla Kubernetes:**

```bash
CLUSTER_TYPE=k8s ./lab.sh up
```

After the cluster is up:

```bash
export KUBECONFIG=$HOME/.kcli/clusters/udn/auth/kubeconfig
```

The entry script will:
- Create the `br-vlan100` bridge
- Deploy the containerlab topology (r1, ext-host, host link)
- Provision the cluster via kcli (1 control plane + 1 worker)

### 2. Install platform components

Install the following components in order. See the full lab documentation
(`docs/labs/01-udn/index.md`) for detailed platform-specific instructions
with OpenShift and Kubernetes tabs.

1. OVN-Kubernetes (pre-installed on OpenShift; Helm on k8s)
2. Enable network features (CNO patch on OpenShift; configured at install on k8s)
3. NMState (OLM on OpenShift; upstream manifests on k8s)
4. KubeVirt (OLM on OpenShift; upstream manifests on k8s)

### 3. Apply networking configuration

Once all platform components are installed, apply the manifests in order.
These steps are the same for both OpenShift and vanilla Kubernetes.

#### Create the namespaces

```bash
kubectl apply -f config/00-namespaces.yaml
```

#### Apply the NNCPs

The NNCP creates an OVS bridge mapping for the localnet UDN, connecting
`ens4` (attached to `br-vlan100`) to OVN's `localnet100` mapping. This
must be done **before** creating the Localnet CUDN.

```bash
kubectl apply -f config/02-nncps.yaml
```

Watch for all enactments to become `Available`:

```bash
kubectl get nnce -w
```

#### Create the UDNs

This creates the L3 UDN (namespace-scoped), L2 ClusterUDN, and Localnet
ClusterUDN.

```bash
kubectl apply -f config/01-udns.yaml
```

#### Deploy the test workloads

```bash
kubectl apply -f config/03-workloads.yaml
```

This creates `network-tools` pods in each namespace and KubeVirt VMs in
`udn-l2-a` and `udn-localnet`.

## Validate

### L3 UDN — East-West

Get UDN IPs from the `network-status` annotation (`kubectl get pods -o wide`
shows the default network IP, not the UDN IP). The entry with `"default": true`
is the primary UDN interface:

```bash
L3_POD2_IP=$(kubectl get pod -n udn-l3 l3-pod-2 \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
kubectl exec -n udn-l3 l3-pod-1 -- ping -c 3 "$L3_POD2_IP"
```

### L3 UDN — North-South

Ping ext-host to verify north-south via the UDN gateway:

```bash
kubectl exec -n udn-l3 l3-pod-1 -- ping -c 3 172.16.0.1
```

### L2 ClusterUDN — East-West (same namespace)

```bash
L2_POD2_IP=$(kubectl get pod -n udn-l2-a l2-pod-2 \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 "$L2_POD2_IP"
```

### L2 ClusterUDN — East-West (cross-namespace)

Because the L2 ClusterUDN spans both `udn-l2-a` and `udn-l2-b`, pods in
different namespaces share the same flat network:

```bash
L2_PODB_IP=$(kubectl get pod -n udn-l2-b l2-pod-b \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]')
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 "$L2_PODB_IP"
```

### L2 ClusterUDN — North-South

```bash
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 172.16.0.1
```

### L2 ClusterUDN — VM connectivity

Check the VM is running and get its IP:

```bash
kubectl get vmi -n udn-l2-a
```

Ping from a pod to the VM:

```bash
kubectl exec -n udn-l2-a l2-pod-1 -- ping -c 3 <l2-vm-IP>
```

### Localnet ClusterUDN — North-South

The localnet pod has a secondary interface on 192.168.100.0/24. Ping r1 on
the same L2 segment:

```bash
kubectl exec -n udn-localnet localnet-pod -- ping -c 3 192.168.100.1
```

From ext-host, ping the localnet pod:

```bash
docker exec clab-udn-ext-host ping -c 3 <localnet-pod-IP>
```

### Localnet ClusterUDN — VM connectivity

Check the localnet VM:

```bash
kubectl get vmi -n udn-localnet
```

From ext-host, ping the VM's localnet IP:

```bash
docker exec clab-udn-ext-host ping -c 3 <localnet-vm-IP>
```

## Teardown

```bash
./lab.sh down
# or, for vanilla k8s:
CLUSTER_TYPE=k8s ./lab.sh down
```
