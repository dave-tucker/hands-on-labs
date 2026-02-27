# Getting Started

## Prerequisites

### Host requirements

- Linux host (RHEL/CentOS 9 or equivalent) with libvirt/KVM
- Passwordless sudo
- [Docker](https://docs.docker.com/engine/install/) (or Podman with Docker compatibility)
- [containerlab](https://containerlab.dev/installation/)

=== "OpenShift"

    No additional tools required beyond the base prerequisites.

=== "Kubernetes"

    - [Helm](https://helm.sh/docs/intro/install/) — used to install OVN-Kubernetes,
      NMState, and MetalLB on vanilla Kubernetes clusters.

### kubectl plugins

Install [krew](https://krew.sigs.k8s.io/docs/user-guide/setup/install/),
the kubectl plugin manager:

```bash
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
```

Then install the `virt` plugin (used to interact with KubeVirt VMs):

```bash
kubectl krew install virt
```

This provides the `kubectl virt` command for interacting with KubeVirt VMs
(e.g. `kubectl virt console`).

### kcli

[kcli](https://kcli.readthedocs.io/) is used to provision both OpenShift and
vanilla Kubernetes clusters on libvirt/KVM.

```bash
curl https://raw.githubusercontent.com/karmab/kcli/main/install.sh | sudo bash
```

### Pull secret (OpenShift only)

!!! info "Not needed for vanilla Kubernetes"
    Skip this step if you only plan to deploy vanilla Kubernetes clusters.

Download your pull secret from
[console.redhat.com](https://console.redhat.com/openshift/install/pull-secret)
and place it where kcli expects it:

```bash
cp ~/Downloads/pull-secret.json ~/pull_secret.json
```

## Cluster provisioning

Each lab includes a `lab.sh` script that handles bridge setup, containerlab
topology deployment, and cluster provisioning via kcli.

=== "OpenShift"

    ```bash
    cd labs/<lab-name>
    ./lab.sh up
    ```

=== "Kubernetes"

    ```bash
    cd labs/<lab-name>
    CLUSTER_TYPE=k8s ./lab.sh up
    ```

Set your kubeconfig after the cluster is up:

```bash
export KUBECONFIG=$HOME/.kcli/clusters/<cluster-name>/auth/kubeconfig
```

## Platform components

After Day 1 deployment, each lab's documentation walks you through
installing the required platform components (OVN-Kubernetes, NMState,
MetalLB, KubeVirt, etc.) with step-by-step commands for both OpenShift
and vanilla Kubernetes.
