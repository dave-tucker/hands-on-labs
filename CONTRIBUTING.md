# Contributing

## Repository layout

```
network-hol/
├── docs/                      # MkDocs documentation source
│   ├── index.md               # Home page
│   ├── getting-started.md     # Prerequisites and setup
│   ├── labs/                  # Per-lab documentation
│   │   ├── 01-udn/
│   │   │   └── index.md
│   │   └── 03-vrf-lite/
│   │       └── index.md
│   └── snippets/              # Reusable markdown snippets (pymdownx.snippets)
│       ├── install-ovn-kubernetes.md
│       ├── enable-network-features.md
│       ├── install-nmstate.md
│       ├── install-kubevirt.md
│       └── install-metallb.md
├── labs/                      # Lab source (configs, scripts, topologies)
│   ├── 01-udn/
│   │   ├── lab.sh             # Entry script (up / down)
│   │   ├── kcli_openshift.yml
│   │   ├── kcli_k8s.yml
│   │   ├── topology.clab.yml
│   │   └── config/            # Kubernetes manifests
│   └── 03-vrf-lite/
│       ├── lab.sh
│       ├── kcli_openshift.yml
│       ├── kcli_k8s.yml
│       ├── topology.clab.yml
│       └── config/
├── scripts/
│   └── lab.sh                 # Shared library (bridge mgmt, cluster lifecycle)
├── mkdocs.yml                 # MkDocs configuration
└── CONTRIBUTING.md            # This file
```

## Adding a new lab

1. **Create the lab directory** under `labs/<number>-<name>/`:
   - `lab.sh` — entry script sourcing `scripts/lab.sh`, defining `CLUSTER_NAME`
     and `BRIDGES`, then implementing `cmd_up` and `cmd_down`.
   - `kcli_openshift.yml` and `kcli_k8s.yml` — cluster parameter files.
   - `topology.clab.yml` — containerlab topology.
   - `config/` — Kubernetes manifests applied during Day 2.

2. **Create the documentation** under `docs/labs/<number>-<name>/index.md`:
   - Overview and addressing tables.
   - Day 1 (deploy) section using `lab.sh up`.
   - Day 2 (configure & validate) section with step-by-step commands.
   - Use `--8<-- "snippet-name.md"` for common install steps.
   - Use tabbed content (`=== "OpenShift"` / `=== "Kubernetes"`) for
     platform-specific instructions.
   - Teardown section using `lab.sh down`.

3. **Add nav entry** in `mkdocs.yml`.

## Lab entry script pattern

Each lab's `lab.sh` follows this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$LAB_DIR/../.." && pwd)"

export CLUSTER_NAME="my-lab"
export BRIDGES="br-example"

source "$REPO_ROOT/scripts/lab.sh"

cmd_up() {
  setup_bridges
  # containerlab deploy ...
  deploy_cluster "$LAB_DIR" "$CLUSTER_NAME"
}

cmd_down() {
  # containerlab destroy ...
  destroy_cluster "$CLUSTER_NAME"
  teardown_bridges
}

case "${1:-}" in
  up)   cmd_up ;;
  down) cmd_down ;;
  *)    echo "Usage: $0 {up|down}"; exit 1 ;;
esac
```

## Day 2 operations

Day 2 component installation (OVN-Kubernetes, NMState, MetalLB, KubeVirt)
is documented as explicit, step-by-step manual commands in each lab's
documentation. Common installation steps live in `docs/snippets/` and are
included via `pymdownx.snippets`.

This approach lets users perform and understand each step themselves,
rather than hiding operations behind helper scripts.

## Snippets

Reusable markdown fragments in `docs/snippets/` are included into lab
docs using the `pymdownx.snippets` extension:

```markdown
--8<-- "install-nmstate.md"
```

Each snippet uses tabbed content to show platform-specific instructions.

## Conventions

- **Domain**: `labs.ovn-k8s.local` for all kcli clusters.
- **Node interface naming**: kcli attaches extra networks as `ens4`, `ens5`,
  etc. (in order of `extra_networks` in the kcli parameter file).
- **CLUSTER_TYPE**: `openshift` (default) or `k8s`.
- **Images**: Use `quay.io/openshift/origin-network-tools:latest` for test
  pods and `quay.io/frrouting/frr:10.5.1` for FRR routers.
