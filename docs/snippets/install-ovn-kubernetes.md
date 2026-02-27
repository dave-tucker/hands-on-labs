#### Install OVN-Kubernetes

=== "OpenShift"

    OVN-Kubernetes is the default CNI on OpenShift -- no action needed.

=== "Kubernetes"

    Install OVN-Kubernetes via Helm:

    ```bash
    helm repo add ovn-kubernetes https://ovn-kubernetes.github.io/ovn-kubernetes/helm
    helm repo update
    helm install ovn-kubernetes ovn-kubernetes/ovn-kubernetes \
      --namespace ovn-kubernetes --create-namespace \
      --set global.enableMultiNetwork=true \
      --set global.enableUserDefinedNetwork=true
    kubectl rollout status daemonset -n ovn-kubernetes ovnkube-node --timeout=300s
    ```
