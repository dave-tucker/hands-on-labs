#!/bin/bash

KUBECONFIG="${KUBECONFIG:-$HOME/.kcli/clusters/bgp-evpn/auth/kubeconfig}"
export KUBECONFIG

echo "=== BGP-EVPN Validation ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check 1: NMState
echo "1. NMState Operator"
if kubectl get deployment nmstate-operator -n nmstate &>/dev/null; then
    if kubectl get daemonset nmstate-handler -n nmstate &>/dev/null; then
        READY=$(kubectl get daemonset nmstate-handler -n nmstate -o jsonpath='{.status.numberReady}')
        DESIRED=$(kubectl get daemonset nmstate-handler -n nmstate -o jsonpath='{.status.desiredNumberScheduled}')
        if [ "$READY" == "$DESIRED" ]; then
            pass "NMState handler running ($READY/$DESIRED nodes)"
        else
            fail "NMState handler not ready ($READY/$DESIRED nodes)"
        fi
    else
        fail "NMState handler not found"
    fi
else
    fail "NMState operator not installed"
fi
echo ""

# Check 2: NNCPs
echo "2. Node Network Configuration"
if kubectl get nncp bgp-evpn-master &>/dev/null; then
    MASTER_STATUS=$(kubectl get nncp bgp-evpn-master -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    WORKER_STATUS=$(kubectl get nncp bgp-evpn-worker -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$MASTER_STATUS" == "True" ]; then
        pass "Master NNCP configured"
    else
        fail "Master NNCP not configured"
    fi
    if [ "$WORKER_STATUS" == "True" ]; then
        pass "Worker NNCP configured"
    else
        fail "Worker NNCP not configured"
    fi
else
    fail "NNCPs not found"
fi
echo ""

# Check 3: FRR-K8s
echo "3. FRR-K8s"
if kubectl get namespace openshift-frr-k8s &>/dev/null; then
    FRR_READY=$(kubectl get pods -n openshift-frr-k8s -l app=frr-k8s -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c "True")
    FRR_TOTAL=$(kubectl get pods -n openshift-frr-k8s -l app=frr-k8s --no-headers | wc -l)
    if [ "$FRR_READY" == "$FRR_TOTAL" ]; then
        pass "FRR-K8s pods running ($FRR_READY/$FRR_TOTAL)"

        # Check FRR version
        FRR_POD=$(kubectl get pod -n openshift-frr-k8s -l component=frr-k8s -o jsonpath='{.items[0].metadata.name}')
        FRR_VERSION=$(kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show version" 2>/dev/null | grep "FRRouting" | awk '{print $2}')
        if [[ $(echo "$FRR_VERSION" | cut -d. -f1) -ge 9 ]]; then
            pass "FRR version $FRR_VERSION (>= 9.0 required for EVPN)"
        else
            warn "FRR version $FRR_VERSION (< 9.0 may not support VNI filtering)"
        fi
    else
        fail "FRR-K8s pods not ready ($FRR_READY/$FRR_TOTAL)"
    fi
else
    fail "FRR-K8s namespace not found"
fi
echo ""

# Check 4: VTEP
echo "4. VTEP Resource"
if kubectl get vtep evpn-vteps &>/dev/null; then
    VTEP_STATUS=$(kubectl get vtep evpn-vteps -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')
    if [ "$VTEP_STATUS" == "True" ]; then
        pass "VTEP allocated"
        kubectl get nodes -o jsonpath='{range .items[*]}  {.metadata.name}: {.metadata.annotations.k8s\.ovn\.org/vteps}{"\n"}{end}' | grep evpn-vteps
    else
        REASON=$(kubectl get vtep evpn-vteps -o jsonpath='{.status.conditions[?(@.type=="Accepted")].reason}')
        fail "VTEP not allocated ($REASON)"
    fi
else
    fail "VTEP resource not found"
fi
echo ""

# Check 5: BGP Sessions
echo "5. BGP Sessions"
FRR_POD=$(kubectl get pod -n openshift-frr-k8s -l component=frr-k8s -o jsonpath='{.items[0].metadata.name}')
if [ -n "$FRR_POD" ]; then
    echo "  IPv4 Unicast:"
    kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show bgp ipv4 unicast summary" 2>/dev/null | grep "192.168.255" | while read line; do
        NEIGHBOR=$(echo $line | awk '{print $1}')
        STATE=$(echo $line | awk '{print $10}')
        if [ "$STATE" -gt 0 ] 2>/dev/null; then
            pass "  $NEIGHBOR: Established ($STATE prefixes)"
        else
            fail "  $NEIGHBOR: $STATE"
        fi
    done

    echo "  L2VPN EVPN:"
    kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show bgp l2vpn evpn summary" 2>/dev/null | grep "192.168.255" | while read line; do
        NEIGHBOR=$(echo $line | awk '{print $1}')
        STATE=$(echo $line | awk '{print $10}')
        if [ "$STATE" -gt 0 ] 2>/dev/null || [ "$STATE" == "0" ]; then
            pass "  $NEIGHBOR: Established ($STATE prefixes)"
        else
            fail "  $NEIGHBOR: $STATE"
        fi
    done
else
    fail "No FRR pods found"
fi
echo ""

# Check 6: RouteAdvertisements
echo "6. Route Advertisements"
if kubectl get routeadvertisements evpn-cudn-advertisement &>/dev/null; then
    RA_STATUS=$(kubectl get routeadvertisements evpn-cudn-advertisement -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')
    if [ "$RA_STATUS" == "True" ]; then
        pass "RouteAdvertisements accepted"
    else
        REASON=$(kubectl get routeadvertisements evpn-cudn-advertisement -o jsonpath='{.status.conditions[?(@.type=="Accepted")].reason}')
        fail "RouteAdvertisements not accepted ($REASON)"
    fi
else
    fail "RouteAdvertisements not found"
fi
echo ""

# Check 7: CUDN
echo "7. EVPN CUDN"
if kubectl get clusteruserdefinednetwork evpn-l2 &>/dev/null; then
    TRANSPORT_STATUS=$(kubectl get clusteruserdefinednetwork evpn-l2 -o jsonpath='{.status.conditions[?(@.type=="TransportAccepted")].status}')
    NETWORK_STATUS=$(kubectl get clusteruserdefinednetwork evpn-l2 -o jsonpath='{.status.conditions[?(@.type=="NetworkCreated")].status}')
    if [ "$TRANSPORT_STATUS" == "True" ]; then
        pass "EVPN transport accepted"
    else
        fail "EVPN transport not accepted"
    fi
    if [ "$NETWORK_STATUS" == "True" ]; then
        pass "Network created"
    else
        fail "Network not created"
    fi
else
    fail "CUDN not found"
fi
echo ""

# Check 8: Workloads
echo "8. Test Workloads"
if kubectl get namespace evpn-demo &>/dev/null; then
    MASTER_POD=$(kubectl get pod evpn-pod-master -n evpn-demo -o jsonpath='{.status.phase}' 2>/dev/null)
    WORKER_POD=$(kubectl get pod evpn-pod-worker -n evpn-demo -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$MASTER_POD" == "Running" ]; then
        MASTER_IP=$(kubectl get pod evpn-pod-master -n evpn-demo -o jsonpath='{.status.podIPs[0].ip}')
        pass "evpn-pod-master running ($MASTER_IP)"
    else
        fail "evpn-pod-master not running ($MASTER_POD)"
    fi
    if [ "$WORKER_POD" == "Running" ]; then
        WORKER_IP=$(kubectl get pod evpn-pod-worker -n evpn-demo -o jsonpath='{.status.podIPs[0].ip}')
        pass "evpn-pod-worker running ($WORKER_IP)"
    else
        fail "evpn-pod-worker not running ($WORKER_POD)"
    fi

    # Test connectivity
    if [ "$MASTER_POD" == "Running" ] && [ "$WORKER_POD" == "Running" ]; then
        echo "  Testing pod-to-pod connectivity..."
        if kubectl exec -n evpn-demo evpn-pod-master -- ping -c 1 -W 2 $WORKER_IP &>/dev/null; then
            pass "  Connectivity: master → worker"
        else
            fail "  Connectivity: master → worker"
        fi
    fi
else
    warn "evpn-demo namespace not found (workloads not deployed)"
fi
echo ""

# Check 9: EVPN VNI
echo "9. EVPN VNI Status"
if [ -n "$FRR_POD" ]; then
    VNI_OUTPUT=$(kubectl exec -n openshift-frr-k8s $FRR_POD -c frr -- vtysh -c "show evpn vni" 2>/dev/null)
    if echo "$VNI_OUTPUT" | grep -q "100"; then
        pass "VNI 100 configured"
        echo "$VNI_OUTPUT" | grep "^100" | sed 's/^/  /'
    else
        warn "VNI 100 not found (may indicate FRR version < 9.0)"
        echo "$VNI_OUTPUT" | grep "^0" | sed 's/^/  /'
    fi
fi
echo ""

echo "=== Validation Complete ==="
