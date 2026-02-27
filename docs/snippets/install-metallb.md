#### Install MetalLB (Kubernetes only)

=== "OpenShift"

    MetalLB is not required for this lab on OpenShift.

=== "Kubernetes"

    Install MetalLB via Helm:

    ```bash
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    kubectl create namespace metallb-system || true
    helm install metallb metallb/metallb -n metallb-system
    kubectl rollout status deployment -n metallb-system metallb-controller --timeout=300s
    ```
