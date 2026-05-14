#!/bin/bash
set -e

KUBECONFIG="${KUBECONFIG:-$HOME/.kcli/clusters/bgp-evpn/auth/kubeconfig}"
export KUBECONFIG

CONFIG_DIR="$(dirname "$0")"

echo "=== OpenShift 4.22 BGP-EVPN Day 2 Configuration ==="
echo ""

# Step 1: Install NMState operator
echo "Step 1: Installing NMState operator..."
if kubectl get namespace nmstate &>/dev/null; then
    echo "  NMState already installed, skipping..."
else
    echo "  Installing from upstream..."
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/nmstate.io_nmstates.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/namespace.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/service_account.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/role.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/role_binding.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/operator.yaml

    echo "  Creating NMState instance..."
    kubectl apply -f - <<EOF
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

    echo "  Waiting for handler pods to be ready..."
    kubectl rollout status daemonset -n nmstate nmstate-handler --timeout=300s
fi

echo ""
echo "Step 2: Configuring node network (loopbacks, P2P links, static routes)..."
kubectl apply -f "${CONFIG_DIR}/01-nncps.yaml"
echo "  Waiting for NNCPs to be configured..."
sleep 10
kubectl wait nncp --all --for=condition=Available --timeout=120s

echo ""
echo "Step 3: Enabling FRR-K8s via Network operator..."
if kubectl get namespace openshift-frr-k8s &>/dev/null; then
    echo "  FRR-K8s already enabled, skipping..."
else
    oc patch Network.operator.openshift.io cluster --type=merge \
      -p='{"spec": {"additionalRoutingCapabilities": {"providers": ["FRR"]}, "defaultNetwork": {"ovnKubernetesConfig": {"routeAdvertisements": "Enabled"}}}}'

    echo "  Waiting for FRR-K8s pods to be ready..."
    sleep 30
    kubectl wait --for=condition=ready pod -n openshift-frr-k8s -l app=frr-k8s --timeout=300s
fi

echo ""
echo "Step 4: Creating VTEP resource..."
kubectl apply -f "${CONFIG_DIR}/00-vtep.yaml"

echo ""
echo "Step 5: Creating VTEP dummy interfaces on nodes..."
echo "  Creating evpn-vtep interface on master (100.64.0.1)..."
kubectl debug node/bgp-evpn-ctlplane-0.labs.ovn-k8s.local --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host bash -c "
    ip link add evpn-vtep type dummy 2>/dev/null || true
    ip link set evpn-vtep up
    ip addr add 100.64.0.1/32 dev evpn-vtep 2>/dev/null || true
  " 2>&1 | grep -v "profile\|Warning\|metadata" || true

echo "  Creating evpn-vtep interface on worker (100.64.0.2)..."
kubectl debug node/bgp-evpn-worker-0.labs.ovn-k8s.local --image=registry.access.redhat.com/ubi9/ubi:latest -- \
  chroot /host bash -c "
    ip link add evpn-vtep type dummy 2>/dev/null || true
    ip link set evpn-vtep up
    ip addr add 100.64.0.2/32 dev evpn-vtep 2>/dev/null || true
  " 2>&1 | grep -v "profile\|Warning\|metadata" || true

echo "  Waiting for VTEP allocation..."
sleep 10

echo ""
echo "Step 6: Configuring BGP peering..."
kubectl apply -f "${CONFIG_DIR}/02-frrconfiguration.yaml"
echo "  Restarting FRR pods to apply configuration..."
kubectl delete pod -n openshift-frr-k8s -l app=frr-k8s
kubectl wait --for=condition=ready pod -n openshift-frr-k8s -l app=frr-k8s --timeout=120s
sleep 10

echo ""
echo "Step 7: Configuring Route Advertisements..."
kubectl apply -f "${CONFIG_DIR}/03-route-advertisements.yaml"
sleep 5

echo ""
echo "Step 8: Creating EVPN ClusterUserDefinedNetwork..."
kubectl apply -f "${CONFIG_DIR}/04-evpn-cudn.yaml"
sleep 5

echo ""
echo "Step 9: Creating namespace and workloads..."
kubectl apply -f "${CONFIG_DIR}/05-namespaces.yaml"
sleep 2
kubectl apply -f "${CONFIG_DIR}/06-workloads.yaml"

echo ""
echo "=== Configuration Summary ==="
echo ""
echo "VTEP Status:"
kubectl get vtep evpn-vteps
echo ""
echo "RouteAdvertisements Status:"
kubectl get routeadvertisements
echo ""
echo "CUDN Status:"
kubectl get clusteruserdefinednetwork
echo ""
echo "Pod Status:"
kubectl get pods -n evpn-demo -o wide
echo ""
echo "Day 2 configuration complete!"
echo ""
echo "To verify BGP sessions:"
echo "  FRR_POD=\$(kubectl get pod -n openshift-frr-k8s -l component=frr-k8s --field-selector spec.nodeName=bgp-evpn-worker-0.labs.ovn-k8s.local -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl exec -n openshift-frr-k8s \$FRR_POD -c frr -- vtysh -c 'show bgp summary'"
echo ""
echo "To test connectivity:"
echo "  kubectl exec -n evpn-demo evpn-pod-master -- ping -c 3 \$(kubectl get pod evpn-pod-worker -n evpn-demo -o jsonpath='{.status.podIPs[0].ip}')"
