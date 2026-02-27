#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$LAB_DIR/../.." && pwd)"

export CLUSTER_NAME="vrf-lite"
export BRIDGES="br-tenant1 br-tenant2"

# shellcheck source=../../scripts/lab.sh
source "$REPO_ROOT/scripts/lab.sh"

# ---------------------------------------------------------------------------
cmd_up() {
  if [[ "${SKIP_BRIDGE:-0}" -ne 1 ]]; then
    echo "=== Bridge setup (${BRIDGES}) ==="
    setup_bridges
  fi

  if [[ "${SKIP_CONTAINERLAB:-0}" -ne 1 ]]; then
    echo "=== Containerlab deploy ==="
    cd "$LAB_DIR"
    containerlab deploy -t topology.clab.yml
    docker exec clab-vrf-lite-l1 ip addr add 10.100.2.2/24 dev eth1 2>/dev/null || true
    docker exec clab-vrf-lite-l2 ip addr add 10.200.2.2/24 dev eth1 2>/dev/null || true
    docker exec clab-vrf-lite-l1 ip route add 10.100.1.0/24 via 10.100.2.1 dev eth1 2>/dev/null || true
    docker exec clab-vrf-lite-l2 ip route add 10.200.1.0/24 via 10.200.2.1 dev eth1 2>/dev/null || true
    cd "$REPO_ROOT"
  fi

  if [[ "${SKIP_CLUSTER:-0}" -ne 1 ]]; then
    deploy_cluster "$LAB_DIR" "$CLUSTER_NAME"
  fi

  echo "=== Deploy complete ==="
  echo "export KUBECONFIG=$(get_kubeconfig "$CLUSTER_NAME")"
  echo "Once the cluster is up, follow the lab docs for Day 2 configuration."
}

# ---------------------------------------------------------------------------
cmd_down() {
  if [[ "${SKIP_CONTAINERLAB:-0}" -ne 1 ]]; then
    echo "=== Containerlab destroy ==="
    cd "$LAB_DIR"
    containerlab destroy -t topology.clab.yml --cleanup || true
    cd "$REPO_ROOT"
  fi

  if [[ "${SKIP_CLUSTER:-0}" -ne 1 ]]; then
    destroy_cluster "$CLUSTER_NAME"
  fi

  if [[ "${SKIP_BRIDGE:-0}" -ne 1 ]]; then
    echo "=== Bridge teardown ==="
    teardown_bridges
  fi

  echo "Lab teardown complete."
}

# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  up     Deploy bridges, containerlab, and cluster
  down   Tear down containerlab, cluster, and bridges

Environment:
  CLUSTER_TYPE      openshift (default) or k8s
  SKIP_BRIDGE       1 to skip bridge setup/teardown
  SKIP_CONTAINERLAB 1 to skip containerlab deploy/destroy
  SKIP_CLUSTER      1 to skip kcli cluster create/delete
EOF
  exit 1
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  up)   cmd_up ;;
  down) cmd_down ;;
  *)    usage ;;
esac
