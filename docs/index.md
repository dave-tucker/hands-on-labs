# OVN-Kubernetes Network Hands-On Labs

Hands-on labs for advanced OVN-Kubernetes networking, using
[containerlab](https://containerlab.dev/) for external network topologies and
[kcli](https://kcli.readthedocs.io/) for cluster provisioning.

Supports both **OpenShift** (default) and **vanilla Kubernetes** clusters.

## Labs

| Lab | Description |
|---|---|
| [User Defined Networks (UDN)](labs/01-udn/index.md) | L2, L3, and Localnet UDN topologies with KubeVirt VMs |
| [BGP](labs/02-bgp/index.md) | CLOS spine/leaf eBGP over loopbacks with BFD |
| [VRF-Lite](labs/03-vrf-lite/index.md) | Multi-tenant VRF isolation with CUDNs and BGP peering |

## Quick start

See [Getting Started](getting-started.md) for prerequisites and setup,
then pick a lab above.
