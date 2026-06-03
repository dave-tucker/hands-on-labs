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
    kubectl patch Network.operator.openshift.io cluster --type=merge \
      -p='{"spec": {"additionalRoutingCapabilities": {"providers": ["FRR"]}, "defaultNetwork": {"ovnKubernetesConfig": {"routeAdvertisements": "Enabled", "gatewayConfig": {"routingViaHost": true}}}}}'

    echo "  Waiting for FRR-K8s pods to be ready..."
    sleep 30
    kubectl wait --for=condition=ready pod -n openshift-frr-k8s -l app=frr-k8s --timeout=300s
fi

echo ""
echo "Step 4: Creating VTEP resource..."
kubectl apply -f "${CONFIG_DIR}/00-vtep.yaml"

echo ""
echo "Step 5: VTEP dummy interfaces..."
echo "  (Created by NMState NNCPs in Step 2: lo-vtep on each node with 100.64.0.x/32)"
echo "  Verifying lo-vtep exists on nodes..."
kubectl get nncp -o jsonpath='{range .items[*]}{.metadata.name}: {.status.conditions[?(@.type=="Available")].status}{"\n"}{end}'

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
echo "  WORKER_IP=\$(kubectl get pod evpn-pod-worker -n evpn-demo -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq -r '.[] | select(.default == true) | .ips[0]')"
echo "  kubectl exec -n evpn-demo evpn-pod-master -- ping -c 3 \$WORKER_IP"
