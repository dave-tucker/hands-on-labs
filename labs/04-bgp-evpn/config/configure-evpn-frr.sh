#!/bin/bash
# Post-deployment FRR configuration for BGP-EVPN
# This script applies FRR configuration that cannot be set via FRRConfiguration CRD

set -e

export KUBECONFIG=${KUBECONFIG:-~/.kcli/clusters/bgp-evpn/auth/kubeconfig}

echo "=== Configuring BGP-EVPN on cluster nodes ==="

# Get FRR pod names
FRR_MASTER=$(kubectl get pods -n openshift-frr-k8s --field-selector spec.nodeName=bgp-evpn-ctlplane-0.labs.ovn-k8s.local -o name | head -1)
FRR_WORKER=$(kubectl get pods -n openshift-frr-k8s --field-selector spec.nodeName=bgp-evpn-worker-0.labs.ovn-k8s.local -o name | head -1)

echo "Master FRR pod: $FRR_MASTER"
echo "Worker FRR pod: $FRR_WORKER"

# Configure master node
echo "Configuring master node..."
kubectl exec -n openshift-frr-k8s $FRR_MASTER -c frr -- vtysh -c 'configure terminal' \
  -c 'router bgp 65000' \
  -c 'address-family ipv4 unicast' \
  -c 'network 100.64.0.1/32' \
  -c 'neighbor 192.168.255.11 allowas-in 1' \
  -c 'neighbor 192.168.255.12 allowas-in 1' \
  -c 'no neighbor 192.168.255.11 route-map 192.168.255.11-out out' \
  -c 'no neighbor 192.168.255.12 route-map 192.168.255.12-out out' \
  -c 'exit-address-family' \
  -c 'address-family l2vpn evpn' \
  -c 'neighbor 192.168.255.11 allowas-in 1' \
  -c 'neighbor 192.168.255.12 allowas-in 1' \
  -c 'exit-address-family' \
  -c 'end'

# Configure worker node
echo "Configuring worker node..."
kubectl exec -n openshift-frr-k8s $FRR_WORKER -c frr -- vtysh -c 'configure terminal' \
  -c 'router bgp 65000' \
  -c 'address-family ipv4 unicast' \
  -c 'network 100.64.0.2/32' \
  -c 'neighbor 192.168.255.11 allowas-in 1' \
  -c 'neighbor 192.168.255.12 allowas-in 1' \
  -c 'no neighbor 192.168.255.11 route-map 192.168.255.11-out out' \
  -c 'no neighbor 192.168.255.12 route-map 192.168.255.12-out out' \
  -c 'exit-address-family' \
  -c 'address-family l2vpn evpn' \
  -c 'neighbor 192.168.255.11 allowas-in 1' \
  -c 'neighbor 192.168.255.12 allowas-in 1' \
  -c 'exit-address-family' \
  -c 'end'

echo "=== Configuring BGP-EVPN on leaf switches ==="

# Configure Leaf1
echo "Configuring Leaf1..."
docker exec clab-bgp-evpn-leaf1 vtysh -c 'configure terminal' \
  -c 'router bgp 65001' \
  -c 'address-family l2vpn evpn' \
  -c 'neighbor 192.168.255.1 allowas-in 1' \
  -c 'neighbor 192.168.255.2 allowas-in 1' \
  -c 'end' \
  -c 'write memory'

# Configure Leaf2
echo "Configuring Leaf2..."
docker exec clab-bgp-evpn-leaf2 vtysh -c 'configure terminal' \
  -c 'router bgp 65002' \
  -c 'address-family l2vpn evpn' \
  -c 'neighbor 192.168.255.1 allowas-in 1' \
  -c 'neighbor 192.168.255.2 allowas-in 1' \
  -c 'end' \
  -c 'write memory'

# Clear BGP sessions to apply changes
echo "Clearing BGP sessions..."
kubectl exec -n openshift-frr-k8s $FRR_MASTER -c frr -- vtysh -c 'clear bgp *'
kubectl exec -n openshift-frr-k8s $FRR_WORKER -c frr -- vtysh -c 'clear bgp *'

echo "=== Configuration complete ==="
echo "Waiting 10 seconds for BGP sessions to re-establish..."
sleep 10

echo "=== Verification ==="
echo "Master EVPN routes:"
kubectl exec -n openshift-frr-k8s $FRR_MASTER -c frr -- vtysh -c 'show bgp l2vpn evpn summary'

echo ""
echo "Worker EVPN routes:"
kubectl exec -n openshift-frr-k8s $FRR_WORKER -c frr -- vtysh -c 'show bgp l2vpn evpn summary'

echo ""
echo "Done! EVPN configuration applied successfully."
