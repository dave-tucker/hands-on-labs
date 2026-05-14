# BGP-EVPN Lab - Day 2 Configuration Guide

This guide covers the Day 2 configuration steps to enable BGP-EVPN on an OpenShift 4.22 cluster.

## Prerequisites

- OpenShift 4.22.0-rc.0 or later with TechPreviewNoUpgrade feature set
- Containerlab topology deployed (spine, leaves, ext-host)
- Cluster nodes connected to leaf switches via extra networks (br-leaf1, br-leaf2)
- `oc` or `kubectl` CLI configured with cluster admin access

## Architecture Overview

```
                    Spine1 (AS 65413)
                    [IPv4 unicast only]
                          |
              +-----------+-----------+
              |                       |
         Leaf1 (AS 65001)       Leaf2 (AS 65002)
         192.168.255.11         192.168.255.12
         EVPN: ↔ nodes          EVPN: ↔ nodes
              |                       |
         +----+----+             +----+----+
         |         |             |         |
      master    worker        master    worker
      (ens4)    (ens4)        (ens5)    (ens5)
```

### Network Addressing

| Component | Loopback | VTEP IP | P2P Links |
|-----------|----------|---------|-----------|
| master | 192.168.255.1/32 | 100.64.0.1/32 | ens4: 10.0.1.1/31, ens5: 10.0.2.1/31 |
| worker | 192.168.255.2/32 | 100.64.0.2/32 | ens4: 10.0.1.3/31, ens5: 10.0.2.3/31 |
| Leaf1 | 192.168.255.11/32 | - | eth2: 10.0.1.0/31, eth3: 10.0.1.2/31 |
| Leaf2 | 192.168.255.12/32 | - | eth2: 10.0.2.0/31, eth3: 10.0.2.2/31 |
| ext-host | 192.168.255.13/32 | 100.64.0.13/32 | - |

### BGP Configuration

- **Underlay**: eBGP IPv4 unicast over loopbacks with BFD
  - Cluster nodes (AS 65000) peer with Leaf1/Leaf2
  - Static routes for loopback reachability via P2P links
- **Overlay**: eBGP L2VPN EVPN over loopbacks
  - VNI 100 for EVPN CUDN (10.50.0.0/24)
  - MAC-VRF only (Type-2 and Type-3 routes)

## Deployment Steps

### Option 1: Automated Deployment

Run the automated deployment script:

```bash
export KUBECONFIG=~/.kcli/clusters/bgp-evpn/auth/kubeconfig
./config/deploy-day2.sh
```

### Option 2: Manual Step-by-Step

#### Step 1: Install NMState Operator

NMState is required for persistent node network configuration.

```bash
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/operator.yaml
```

Create the NMState instance:

```bash
kubectl apply -f - <<EOF
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
```

Wait for handler pods to be ready:

```bash
kubectl rollout status daemonset -n nmstate nmstate-handler --timeout=300s
```

#### Step 2: Configure Node Network

Apply NodeNetworkConfigurationPolicies to configure:
- BGP loopback interfaces (lo-bgp)
- P2P links to leaf switches (ens4, ens5)
- Static routes to leaf loopbacks

```bash
kubectl apply -f config/01-nncps.yaml
kubectl wait nncp --all --for=condition=Available --timeout=120s
```

**Verify:**
```bash
kubectl get nncp
# Should show:
# NAME              STATUS      REASON
# bgp-evpn-master   Available   SuccessfullyConfigured
# bgp-evpn-worker   Available   SuccessfullyConfigured
```

#### Step 3: Enable FRR-K8s

Patch the Network operator to enable FRR-K8s and route advertisements:

```bash
oc patch Network.operator.openshift.io cluster --type=merge \
  -p='{"spec": {"additionalRoutingCapabilities": {"providers": ["FRR"]}, "defaultNetwork": {"ovnKubernetesConfig": {"routeAdvertisements": "Enabled"}}}}'
```

Wait for FRR-K8s pods to be ready:

```bash
kubectl wait --for=condition=ready pod -n openshift-frr-k8s -l app=frr-k8s --timeout=300s
```

**Verify:**
```bash
kubectl get pods -n openshift-frr-k8s
# Should show frr-k8s pods running on each node (7/7 containers)
```

#### Step 4: Create VTEP Resource

Apply the VTEP resource to allocate VXLAN tunnel endpoint IPs:

```bash
kubectl apply -f config/00-vtep.yaml
```

#### Step 5: Create VTEP Dummy Interfaces

Since we're using Unmanaged mode, manually create dummy interfaces with VTEP IPs:

```bash
# Master node
kubectl debug node/bgp-evpn-ctlplane-0.labs.ovn-k8s.local \
  --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host bash -c "
    ip link add evpn-vtep type dummy
    ip link set evpn-vtep up
    ip addr add 100.64.0.1/32 dev evpn-vtep
  "

# Worker node
kubectl debug node/bgp-evpn-worker-0.labs.ovn-k8s.local \
  --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host bash -c "
    ip link add evpn-vtep type dummy
    ip link set evpn-vtep up
    ip addr add 100.64.0.2/32 dev evpn-vtep
  "
```

**Verify:**
```bash
kubectl get vtep evpn-vteps
# Should show:
# NAME         ACCEPTED   REASON
# evpn-vteps   True       Allocated

kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {.metadata.annotations.k8s\.ovn\.org/vteps}{"\n"}{end}'
# Should show VTEP IPs assigned to each node
```

#### Step 6: Configure BGP Peering

Apply FRRConfiguration resources for BGP peering:

```bash
kubectl apply -f config/02-frrconfiguration.yaml
```

Restart FRR pods to apply configuration:

```bash
kubectl delete pod -n openshift-frr-k8s -l app=frr-k8s
kubectl wait --for=condition=ready pod -n openshift-frr-k8s -l app=frr-k8s --timeout=120s
```

**Verify:**
```bash
FRR_POD=$(kubectl get pod -n openshift-frr-k8s -l component=frr-k8s \
  --field-selector spec.nodeName=bgp-evpn-worker-0.labs.ovn-k8s.local \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show bgp summary"
# Should show Established sessions for IPv4 Unicast and L2VPN EVPN
```

#### Step 7: Configure Route Advertisements

Apply RouteAdvertisements to advertise EVPN routes:

```bash
kubectl apply -f config/03-route-advertisements.yaml
```

**Verify:**
```bash
kubectl get routeadvertisements
# Should show:
# NAME                      STATUS
# evpn-cudn-advertisement   Accepted
```

#### Step 8: Create EVPN CUDN

Apply the ClusterUserDefinedNetwork with EVPN transport:

```bash
kubectl apply -f config/04-evpn-cudn.yaml
```

**Verify:**
```bash
kubectl get clusteruserdefinednetwork evpn-l2 -o yaml
# Check status.conditions for:
# - type: TransportAccepted, status: True
# - type: NetworkCreated, status: True
```

#### Step 9: Deploy Workloads

Create namespace and test pods:

```bash
kubectl apply -f config/05-namespaces.yaml
kubectl apply -f config/06-workloads.yaml
```

**Verify:**
```bash
kubectl get pods -n evpn-demo -o wide
# Should show evpn-pod-master and evpn-pod-worker running with IPs from 10.50.0.0/24
```

## Validation

### Check BGP Sessions

Verify IPv4 unicast and L2VPN EVPN sessions are Established:

```bash
FRR_POD=$(kubectl get pod -n openshift-frr-k8s -l component=frr-k8s \
  --field-selector spec.nodeName=bgp-evpn-worker-0.labs.ovn-k8s.local \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show bgp summary"
```

Expected output:
```
IPv4 Unicast Summary (VRF default):
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
192.168.255.11  4      65001        XX        XX        0    0    0 XX:XX:XX           XX
192.168.255.12  4      65002        XX        XX        0    0    0 XX:XX:XX           XX

L2VPN EVPN Summary (VRF default):
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
192.168.255.11  4      65001        XX        XX        0    0    0 XX:XX:XX            X
192.168.255.12  4      65002        XX        XX        0    0    0 XX:XX:XX            X
```

### Check EVPN Routes

View EVPN routes exchanged:

```bash
kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- \
  vtysh -c "show bgp l2vpn evpn route"
```

Should see Type-3 (IMET) routes from other VTEPs.

### Check VNI Status

```bash
kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- \
  vtysh -c "show evpn vni"
```

Expected:
```
VNI        Type VxLAN IF              # MACs   # ARPs   # Remote VTEPs  Tenant VRF
100        L2   evx4-evpn-vteps       X        X        X               default
```

### Test Pod Connectivity

Test L2 connectivity between pods:

```bash
WORKER_IP=$(kubectl get pod evpn-pod-worker -n evpn-demo \
  -o jsonpath='{.status.podIPs[0].ip}')

kubectl exec -n evpn-demo evpn-pod-master -- ping -c 3 $WORKER_IP
```

Should show 0% packet loss.

### Test ext-host Connectivity

Ping from ext-host to cluster pods:

```bash
POD_IP=$(kubectl get pod evpn-pod-master -n evpn-demo \
  -o jsonpath='{.status.podIPs[0].ip}')

docker exec clab-bgp-evpn-ext-host ping -c 3 $POD_IP
```

## Troubleshooting

### BGP Sessions Not Establishing

Check node network configuration:
```bash
kubectl get nncp
kubectl describe nncp bgp-evpn-master
```

Verify loopback and P2P interfaces exist:
```bash
kubectl debug node/bgp-evpn-worker-0.labs.ovn-k8s.local \
  --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host ip addr show lo-bgp
```

Check static routes:
```bash
kubectl debug node/bgp-evpn-worker-0.labs.ovn-k8s.local \
  --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host ip route | grep 192.168.255
```

### VTEP Not Allocated

Check if dummy interfaces exist:
```bash
kubectl debug node/bgp-evpn-worker-0.labs.ovn-k8s.local \
  --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host ip addr show evpn-vtep
```

Check VTEP status:
```bash
kubectl get vtep evpn-vteps -o yaml
```

### RouteAdvertisements Not Accepted

Check FRRConfiguration labels:
```bash
kubectl get frrconfiguration -n openshift-frr-k8s --show-labels
```

Should have `use-for-advertisements=true` label.

Check CUDN labels:
```bash
kubectl get clusteruserdefinednetwork evpn-l2 -o yaml | grep labels -A3
```

Should have `evpn: enabled` label.

### Pod Connectivity Failing

Check EVPN VNI configuration:
```bash
kubectl get clusteruserdefinednetwork evpn-l2 -o jsonpath='{.spec.network.evpn.macVRF.vni}'
```

Check VXLAN interface on node:
```bash
OVN_POD=$(kubectl get pod -n openshift-ovn-kubernetes -l app=ovnkube-node \
  --field-selector spec.nodeName=bgp-evpn-worker-0.labs.ovn-k8s.local \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n openshift-ovn-kubernetes $OVN_POD -c ovnkube-controller -- \
  ip link show evx4-evpn-vteps
```

Check VNI filter:
```bash
kubectl exec -n openshift-ovn-kubernetes $OVN_POD -c ovnkube-controller -- \
  bridge vni show dev evx4-evpn-vteps
```

## Known Limitations

### FRR Version Requirements

EVPN with VNI filtering requires FRR 9+. Check FRR version:

```bash
FRR_POD=$(kubectl get pod -n openshift-frr-k8s -l component=frr-k8s \
  --field-selector spec.nodeName=bgp-evpn-worker-0.labs.ovn-k8s.local \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show version"
```

If FRR version is < 9.0, EVPN routes may not be advertised correctly.

## References

- [OVN-Kubernetes EVPN Documentation](https://ovn-kubernetes.io/features/bgp-integration/evpn/)
- [OpenShift Network Operator Documentation](https://docs.openshift.com/container-platform/latest/networking/cluster-network-operator.html)
- [FRRouting EVPN Documentation](https://docs.frrouting.org/en/latest/evpn.html)
