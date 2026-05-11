# AGENTS.md

> Instructions for AI agents working with the OVN-Kubernetes Network Hands-On Labs repository

## Repository Overview

This is a hands-on lab repository for advanced **OVN-Kubernetes networking**, combining:
- **[containerlab](https://containerlab.dev/)** for external network topologies (switches, routers)
- **[kcli](https://kcli.readthedocs.io/)** for cluster provisioning (VMs with libvirt/KVM)
- Support for both **OpenShift** (default) and **vanilla Kubernetes** clusters

The labs demonstrate real-world networking scenarios with physical network integration, BGP, VRF-Lite, and multi-tenancy.

## Key Technologies

- **OVN-Kubernetes**: CNI plugin providing overlay networking
- **containerlab**: Network topology simulation using containers (FRRouting, Arista cEOS, etc.)
- **kcli**: Kubernetes/OpenShift cluster lifecycle management
- **FRRouting (FRR)**: Open-source routing stack for BGP/OSPF/BFD
- **MetalLB / FRR-K8s**: Load balancer implementations
- **NMState**: Declarative node network configuration
- **BFD**: Bidirectional Forwarding Detection for fast failover

## Repository Structure

```
network-hol/
├── labs/
│   ├── 01-udn/          # User Defined Networks
│   ├── 02-bgp/          # BGP CLOS fabric with spine/leaf topology
│   ├── 03-vrf-lite/     # Multi-tenant VRF-Lite with CUDNs
│   └── 04-lb-cudn/      # Load balancer with CUDN
├── docs/
│   ├── labs/            # Lab documentation (mkdocs)
│   └── snippets/        # Reusable installation snippets
├── scripts/             # Helper scripts
└── site/                # Built mkdocs site
```

## Lab Structure Patterns

Each lab typically contains:
- **README.md**: Quick start and topology overview
- **lab.sh** or **deploy.sh**: Automation script (`up`/`down` commands)
- **clab.yml**: containerlab topology definition
- **network/**: FRR configs and network device configurations
- **cluster/**: Kubernetes/OpenShift manifests

## Common Workflows

### Working with Labs

1. **Deploy**: `./lab.sh up` (OpenShift) or `CLUSTER_TYPE=k8s ./lab.sh up` (K8s)
2. **Set kubeconfig**: `export KUBECONFIG=$HOME/.kcli/clusters/<lab-name>/auth/kubeconfig`
3. **Configure**: Apply NNCPs, FRRConfiguration, RouteAdvertisements
4. **Validate**: Check BGP sessions, BFD, routes, connectivity
5. **Teardown**: `./lab.sh down`

### Containerlab Commands

- List topologies: `sudo clab inspect --all`
- Access container: `sudo docker exec -it clab-<topo>-<node> vtysh`
- Check FRR config: `show running-config`
- Destroy topology: `sudo clab destroy -t clab.yml`

### kcli Commands

- List clusters: `kcli list cluster`
- Access node: `kcli ssh -c <cluster> <node>`
- Delete cluster: `kcli delete cluster <name>`

## Important Context

### Network Addressing Patterns

Labs use consistent addressing schemes:
- **10.0.x.0/31**: Point-to-point links (cluster nodes ↔ leaf switches)
- **10.10.x.0/31**: Core links (spine ↔ leaf)
- **192.168.255.0/24**: Loopback addresses for BGP sessions
- **172.16.x.0/24**: Primary cluster network (flat L2)

### BGP Architecture

- **eBGP**: External BGP between different ASNs
- **Loopback-based sessions**: BGP runs over loopbacks, not physical interfaces
- **Static bootstrap**: Static routes to reach leaf loopbacks
- **BFD**: Fast failure detection (requires loopback sessions)
- **ebgpMultiHop**: Required for loopback-based eBGP

### Cluster Types

- **OpenShift**: Default, uses `oc` commands, includes operators
- **Kubernetes**: Vanilla K8s, uses `kubectl`, requires manual component installation

## When Helping Users

### Configuration Files

- **NMState (NNCPs)**: Node network configuration (interfaces, IPs, routes)
- **FRRConfiguration**: BGP/BFD configuration for cluster nodes
- **RouteAdvertisements**: Policy for advertising routes via BGP
- **MetalLB**: IP address pools and BGP advertisement

### Common Tasks

1. **Adding a new lab**: Create lab directory, deploy script, clab.yml, network configs, docs
2. **Debugging connectivity**: Check BGP sessions, BFD status, routes, interface status
3. **Network config changes**: Update NNCPs (declarative), wait for nmstate-handler
4. **Documentation**: Update both lab README and docs/ (mkdocs format)

### Troubleshooting Patterns

- **BGP not establishing**: Check loopbacks, static routes, ebgpMultiHop, BFD compatibility
- **Routes not propagating**: Verify RouteAdvertisements, FRR neighbor status
- **Container networking**: Use `sudo docker exec` for containerlab nodes
- **kcli issues**: Check libvirt pool, ensure passwordless sudo

## Documentation

- Main site built with **mkdocs-material**
- Build: `mkdocs build`
- Serve: `mkdocs serve`
- Snippets in `docs/snippets/` are reused across labs with `--8<--` includes

## Environment Assumptions

- **Linux host**: RHEL/CentOS 9 or equivalent
- **libvirt/KVM**: For VM-based cluster nodes
- **Docker/Podman**: For containerlab
- **Passwordless sudo**: Required by kcli and containerlab
- **OpenShift pull secret**: At `~/pull_secret.json` for OpenShift labs

## Testing and Validation

Labs typically validate:
- BGP session establishment (ESTABLISHED state)
- BFD sessions (Up state)
- Route exchange (leaf and cluster routers see expected prefixes)
- Workload connectivity (pod-to-pod, pod-to-external)
- Failover scenarios (link down, BFD triggers fast reconvergence)

## Code Style

- **Shell scripts**: Use bash with set -euo pipefail
- **YAML**: 2-space indentation
- **Documentation**: Markdown with mkdocs-material extensions
- **Comments**: Explain "why" for non-obvious networking decisions (AS numbers, subnet choices, static routes)
