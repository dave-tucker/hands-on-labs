# OVN-Kubernetes Network Hands-On Labs

Hands-on labs for advanced OVN-Kubernetes networking, using [containerlab](https://containerlab.dev/) for external network topologies and [kcli](https://kcli.readthedocs.io/) for cluster provisioning. Supports both **OpenShift** (default) and **vanilla Kubernetes** clusters.

## Prerequisites

### Host requirements

- Linux host (RHEL/CentOS 9 or equivalent) with libvirt/KVM
- Passwordless sudo
- [Docker](https://docs.docker.com/engine/install/) (or Podman with Docker compatibility)
- [containerlab](https://containerlab.dev/installation/)
- [Helm](https://helm.sh/docs/intro/install/) (required for vanilla k8s; optional for OpenShift)

### kcli

Install kcli:

```bash
curl https://raw.githubusercontent.com/karmab/kcli/main/install.sh | sudo bash
```

### Pull secret (OpenShift only)

Download your pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) and place it where kcli expects it:

```bash
cp ~/Downloads/pull-secret.json ~/pull_secret.json
```

## Labs

| Lab | Description |
|-----|-------------|
| [VRF-Lite](labs/03-vrf-lite/) | Multi-tenant VRF-Lite with CUDNs |

## Quick start

### OpenShift (default)

```bash
cd labs/03-vrf-lite
./deploy.sh

# Teardown
./destroy.sh
```

### Vanilla Kubernetes

```bash
cd labs/03-vrf-lite
CLUSTER_TYPE=k8s ./deploy.sh
`
# Teardown
CLUSTER_TYPE=k8s ./destroy.sh
```

See the lab's [README](labs/03-vrf-lite/README.md) for topology details, networking config steps, and validation.
