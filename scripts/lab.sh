#!/usr/bin/env bash
# Shared library for network-hol labs.
#
# Source this file to get helper functions for bridge management
# and cluster lifecycle (Day 1 operations).
#
# Day 2 operations (component installation and configuration) are
# performed manually by following the step-by-step instructions in
# each lab's documentation.
#
# Required before sourcing:
#   CLUSTER_TYPE  - "openshift" (default) or "k8s"
#
# After sourcing, REPO_ROOT and CLUSTER_TYPE are exported.

_LAB_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$_LAB_SH_DIR/.." && pwd)}"
export REPO_ROOT

CLUSTER_TYPE="${CLUSTER_TYPE:-openshift}"
export CLUSTER_TYPE

case "$CLUSTER_TYPE" in
  openshift|k8s) ;;
  *)
    echo "Error: CLUSTER_TYPE must be 'openshift' or 'k8s' (got '$CLUSTER_TYPE')." >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Bridge management
#
# Reads BRIDGES (space-separated list) from the environment
# (typically set by the lab's entry script).
# ---------------------------------------------------------------------------

setup_bridges() {
  local br
  for br in ${BRIDGES:-}; do
    if ip link show "$br" &>/dev/null; then
      echo "Bridge $br already exists."
    else
      echo "Creating bridge $br"
      sudo ip link add name "$br" type bridge
      sudo ip link set "$br" up
    fi
  done
  echo "Bridge setup complete."
}

teardown_bridges() {
  local br
  for br in ${BRIDGES:-}; do
    if ip link show "$br" &>/dev/null; then
      echo "Removing bridge $br"
      sudo ip link set "$br" down
      sudo ip link del "$br"
    else
      echo "Bridge $br does not exist; skipping."
    fi
  done
  echo "Bridge teardown complete."
}

# ---------------------------------------------------------------------------
# deploy_cluster <lab_dir> <cluster_name>
# ---------------------------------------------------------------------------
deploy_cluster() {
  local lab_dir="$1"
  local cluster_name="$2"

  case "$CLUSTER_TYPE" in
    openshift)
      echo "=== kcli: deploying OpenShift cluster '$cluster_name' ==="
      cd "$lab_dir"
      kcli create kube openshift --paramfile kcli_openshift.yml "$cluster_name"
      ;;
    k8s)
      echo "=== kcli: deploying generic Kubernetes cluster '$cluster_name' ==="
      cd "$lab_dir"
      kcli create kube generic --paramfile kcli_k8s.yml "$cluster_name"
      ;;
  esac

  echo "export KUBECONFIG=$(get_kubeconfig "$cluster_name")"
}

# ---------------------------------------------------------------------------
# destroy_cluster <cluster_name>
# ---------------------------------------------------------------------------
destroy_cluster() {
  local cluster_name="$1"
  echo "=== kcli: deleting cluster '$cluster_name' ==="
  kcli delete kube "$cluster_name" -y || true
}

# ---------------------------------------------------------------------------
# get_kubeconfig <cluster_name>
# ---------------------------------------------------------------------------
get_kubeconfig() {
  local cluster_name="$1"
  echo "$HOME/.kcli/clusters/${cluster_name}/auth/kubeconfig"
}
