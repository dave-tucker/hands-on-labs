# VRF-Lite

Multi-tenant VRF-Lite lab using Cluster User Defined Networks (CUDNs).

## Overview

Two tenants share the same cluster but are isolated into separate VRFs.
The isolation within the cluster is achieved by using Cluster User Defined
Networks (CUDNs). In order to extend that isolation to the external network,
we peer with an upstream router (R1) over BGP, ensuring the routes are only
advertised within the VRFs.

In summary, we need a dedicated network interface, bound to a VRF, for every
CUDN. For the purposes of this lab, we use a bridge between the cluster and R1.
In a production environment, you would normally use a VLAN subinterface on the
node's NIC.

Each tenant has a second "site" (l1 and l2) directly attached to R1, used to
validate end-to-end connectivity to the pods in the other tenant.

## Addressing

| Segment | Subnet | r1 | Nodes / Hosts |
|---|---|---|---|
| BGP peering (both VRFs) | 172.19.0.0/24 | 172.19.0.1 | .10 (ctlplane-0) |
| CUDN tenant1 (pods) | 10.100.1.0/24 | — | Pod IPs |
| CUDN tenant2 (pods) | 10.200.1.0/24 | — | Pod IPs |
| r1 ↔ l1 (tenant1 VRF) | 10.100.2.0/24 | 10.100.2.1 | l1 = 10.100.2.2 |
| r1 ↔ l2 (tenant2 VRF) | 10.200.2.0/24 | 10.200.2.1 | l2 = 10.200.2.2 |

## BGP

| Speaker | ASN | VRFs | Peers |
|---|---|---|---|
| r1 (FRR) | 65000 | tenant1, tenant2 | 172.19.0.10 (cluster node) |
| Cluster (FRR-K8s) | 65001 | tenant1, tenant2 | 172.19.0.1 (r1) |

r1 uses `redistribute connected` to advertise the l1/l2 subnets
(10.100.2.0/24, 10.200.2.0/24) to the cluster. The cluster uses
RouteAdvertisements to advertise CUDN pod subnets (10.100.1.0/24,
10.200.1.0/24) to r1.

---

## Day 1: Deploy

### 1. Deploy the cluster and containerlab topology

From the `labs/03-vrf-lite` directory:

=== "OpenShift"

    ```bash
    ./lab.sh up
    ```

=== "Kubernetes"

    ```bash
    CLUSTER_TYPE=k8s ./lab.sh up
    ```

The deploy script will:

- Create the `br-tenant1` and `br-tenant2` bridges
- Deploy the containerlab topology (r1, l1, l2)
- Provision a single-node cluster via kcli

Once the cluster is up, set your kubeconfig:

```bash
export KUBECONFIG=$HOME/.kcli/clusters/vrf-lite/auth/kubeconfig
```

### 2. Install platform components

Install the components in order.

--8<-- "install-ovn-kubernetes.md"

#### Enable network features

=== "OpenShift"

    Patch the Cluster Network Operator to enable FRR, `routingViaHost`,
    `ipForwarding`, and `routeAdvertisements`:

    ```bash
    kubectl patch network.operator.openshift.io cluster --type=merge \
      --patch '{
        "spec": {
          "defaultNetwork": {
            "ovnKubernetesConfig": {
              "routingViaHost": true,
              "ipForwarding": "Always",
              "routeAdvertisements": "Enabled"
            }
          },
          "additionalNetworks": [],
          "useMultiNetworkPolicy": true
        }
      }'
    ```

    Wait for the cluster network operator to roll out:

    ```bash
    kubectl rollout status daemonset -n openshift-ovn-kubernetes ovnkube-node --timeout=600s
    ```

=== "Kubernetes"

    These features were configured at OVN-Kubernetes install time. Nothing to
    do here.

--8<-- "install-nmstate.md"

#### Install MetalLB / FRR-K8s

=== "OpenShift"

    FRR-K8s is enabled via the Cluster Network Operator (handled by
    `enable_network_features`). No separate install needed.

=== "Kubernetes"

    Install MetalLB with FRR-K8s mode via Helm:

    ```bash
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    kubectl create namespace metallb-system || true
    helm install metallb metallb/metallb -n metallb-system \
      --set frrk8s.enabled=true
    kubectl rollout status deployment -n metallb-system metallb-controller --timeout=300s
    ```

---

## Day 2: Configure & Validate

### Apply networking configuration

All commands below use `kubectl`. On OpenShift you can substitute `oc`
if preferred.

#### Create the namespaces

```bash
kubectl apply -f config/00-namespaces.yaml
```

#### Apply the FRRConfiguration

This configures BGP peering with the R1 router in both tenant VRFs.

```bash
kubectl apply -f config/01-frrconfiguration.yaml
```

#### Create the CUDNs and RouteAdvertisements

!!! warning "Order matters"
    CUDNs must be applied **before** NNCPs so that OVN creates the tenant
    VRFs on each node first. RouteAdvertisements must be applied **after**
    the CUDNs so that the CUDN pod subnets are advertised to R1.

```bash
kubectl apply -f config/02-cudns.yaml
kubectl apply -f config/03-route-advertisements.yaml
```

Verify the VRFs have been created on the node:

=== "OpenShift"

    ```bash
    oc debug node/vrf-lite-ctlplane-0.labs.ovn-k8s.local -- \
      chroot /host ip link show tenant1
    oc debug node/vrf-lite-ctlplane-0.labs.ovn-k8s.local -- \
      chroot /host ip link show tenant2
    ```

=== "Kubernetes"

    ```bash
    kubectl node-shell vrf-lite-ctlplane-0 -- ip link show tenant1
    kubectl node-shell vrf-lite-ctlplane-0 -- ip link show tenant2
    ```

#### Apply the NNCPs

Once both VRFs exist, apply the NodeNetworkConfigurationPolicies:

```bash
kubectl apply -f config/04-nncps.yaml
```

Watch for all enactments to become `Available`:

```bash
kubectl get nnce -w
```

#### Deploy the test workloads

```bash
kubectl apply -f config/05-deployments.yaml
```

This creates a `network-tools` pod in each tenant namespace for connectivity
testing.

---

### Validate

#### Check FRR is running

=== "OpenShift"

    ```bash
    oc get pods -n openshift-frr-k8s
    ```

=== "Kubernetes"

    FRR runs inside MetalLB speaker pods:

    ```bash
    kubectl get pods -n metallb-system
    ```

#### Check the NNCPs

```bash
kubectl get nncp
kubectl get nnce
```

All enactments should show `Available`.

#### Verify BGP sessions

##### From the cluster

=== "OpenShift"

    ```bash
    FRR_POD=$(oc get pods -n openshift-frr-k8s -o name | head -1)
    oc exec -n openshift-frr-k8s "$FRR_POD" -c frr -- \
      vtysh -c "show ip bgp vrf tenant1 summary"
    ```

=== "Kubernetes"

    ```bash
    FRR_POD=$(kubectl get pods -n metallb-system -l component=speaker -o name | head -1)
    kubectl exec -n metallb-system "$FRR_POD" -c frr -- \
      vtysh -c "show ip bgp vrf tenant1 summary"
    ```

You should see the BGP session established to R1:

```
IPv4 Unicast Summary (VRF tenant1):
BGP router identifier 172.19.0.10, local AS number 65001 vrf-id 117
BGP table version 5
RIB entries 5, using 960 bytes of memory
Peers 1, using 725 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
172.19.0.1      4      65000       279       278        0    0    0 04:16:35            2        1 N/A

Total number of neighbors 1
```

##### From R1

```bash
docker exec clab-vrf-lite-r1 vtysh -c "show ip bgp vrf tenant1 summary"
```

Expected output:

```
IPv4 Unicast Summary:
BGP router identifier 172.19.0.1, local AS number 65000 VRF tenant1 vrf-id 3
BGP table version 7
RIB entries 5, using 640 bytes of memory
Peers 1, using 17 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
172.19.0.10     4      65001       263       265        7    0    0 04:19:09            1        3 N/A

Total number of neighbors 1
```

#### Inspect BGP routes

##### From the cluster

=== "OpenShift"

    ```bash
    FRR_POD=$(oc get pods -n openshift-frr-k8s -o name | head -1)
    oc exec -n openshift-frr-k8s "$FRR_POD" -c frr -- \
      vtysh -c "show ip bgp vrf tenant1"
    ```

=== "Kubernetes"

    ```bash
    FRR_POD=$(kubectl get pods -n metallb-system -l component=speaker -o name | head -1)
    kubectl exec -n metallb-system "$FRR_POD" -c frr -- \
      vtysh -c "show ip bgp vrf tenant1"
    ```

Expected output:

```
BGP table version is 5, local router ID is 172.19.0.10, vrf id 117
Default local pref 100, local AS 65001
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

    Network          Next Hop            Metric LocPrf Weight Path
 *> 10.100.1.0/24    0.0.0.0                  0         32768 i
 *> 10.100.2.0/24    172.19.0.1               0             0 65000 ?
 *> 172.19.0.0/24    172.19.0.1               0             0 65000 ?

Displayed  3 routes and 3 total paths
```

You should see the CUDN subnets (10.100.1.0/24, 10.200.1.0/24) advertised by
the cluster, and the site subnets (10.100.2.0/24, 10.200.2.0/24) received from
R1.

##### From R1

```bash
docker exec clab-vrf-lite-r1 vtysh -c "show ip bgp vrf tenant1"
```

```
BGP table version is 7, local router ID is 172.19.0.1, vrf id 3
Default local pref 100, local AS 65000
Status codes:  s suppressed, d damped, h history, u unsorted, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

     Network          Next Hop            Metric LocPrf Weight Path
 *>  10.100.1.0/24    172.19.0.10              0             0 65001 i
 *>  10.100.2.0/24    0.0.0.0                  0         32768 ?
 *>  172.19.0.0/24    0.0.0.0                  0         32768 ?

Displayed 3 routes and 3 total paths
```

#### Test end-to-end connectivity

Get the tenant1 pod's CUDN IP from the network annotations:

```bash
kubectl get pod -n tenant1 network-tools \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
  | jq -r '.[] | select(.default == true) | .ips[0]'
```

##### Ping from external site to cluster pod

```bash
docker exec clab-vrf-lite-l1 ping -c 3 10.100.1.5
```

```
PING 10.100.1.5 (10.100.1.5) 56(84) bytes of data.
64 bytes from 10.100.1.5: icmp_seq=1 ttl=61 time=2.03 ms
64 bytes from 10.100.1.5: icmp_seq=2 ttl=61 time=1.11 ms
64 bytes from 10.100.1.5: icmp_seq=3 ttl=61 time=0.630 ms

--- 10.100.1.5 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2002ms
rtt min/avg/max/mdev = 0.630/1.258/2.034/0.582 ms
```

##### Ping from cluster pod to external site

```bash
kubectl exec -n tenant1 network-tools -c network-tools -- \
  ping -c 3 10.100.2.2
```

```
PING 10.100.2.2 (10.100.2.2) 56(84) bytes of data.
64 bytes from 10.100.2.2: icmp_seq=1 ttl=62 time=0.928 ms
64 bytes from 10.100.2.2: icmp_seq=2 ttl=62 time=0.452 ms
64 bytes from 10.100.2.2: icmp_seq=3 ttl=62 time=0.592 ms

--- 10.100.2.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2060ms
rtt min/avg/max/mdev = 0.452/0.657/0.928/0.199 ms
```

##### Verify VRF isolation

Confirm that tenant1 **cannot** reach tenant2's external site:

```bash
kubectl exec -n tenant1 network-tools -c network-tools -- \
  ping -c 3 10.200.2.2
```

```
PING 10.200.2.2 (10.200.2.2) 56(84) bytes of data.
From 10.100.1.2 icmp_seq=1 Destination Host Unreachable
From 10.100.1.2 icmp_seq=2 Destination Host Unreachable
From 10.100.1.2 icmp_seq=3 Destination Host Unreachable

--- 10.200.2.2 ping statistics ---
3 packets transmitted, 0 received, +3 errors, 100% packet loss, time 2060ms
```

!!! success "VRF isolation confirmed"
    Traffic is correctly confined to its VRF. Repeat the same tests for
    tenant2 and l2 to fully validate both directions.

---

## Teardown

From the `labs/03-vrf-lite` directory:

=== "OpenShift"

    ```bash
    ./lab.sh down
    ```

=== "Kubernetes"

    ```bash
    CLUSTER_TYPE=k8s ./lab.sh down
    ```

This will:

1. Destroy the containerlab topology
2. Delete the kcli cluster and its VMs
3. Remove the `br-tenant1` and `br-tenant2` bridges
