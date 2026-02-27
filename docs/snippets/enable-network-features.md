#### Enable network features

=== "OpenShift"

    Patch the Cluster Network Operator to enable User Defined Networks:

    ```bash
    kubectl patch network.operator.openshift.io cluster --type=merge \
      --patch '{"spec":{"additionalNetworks":[],"useMultiNetworkPolicy":true}}'
    ```

=== "Kubernetes"

    Features are enabled at install time via the Helm values above -- no
    additional action needed.
