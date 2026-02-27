#### Install NMState

=== "OpenShift"

    Create the namespace, OperatorGroup, Subscription, and NMState instance:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: openshift-nmstate
    ---
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: openshift-nmstate
      namespace: openshift-nmstate
    spec:
      targetNamespaces:
        - openshift-nmstate
    ---
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: kubernetes-nmstate-operator
      namespace: openshift-nmstate
    spec:
      source: redhat-operators
      sourceNamespace: openshift-marketplace
      name: kubernetes-nmstate-operator
      channel: stable
    EOF
    ```

    Wait for the operator CSV to succeed:

    ```bash
    kubectl get csv -n openshift-nmstate -w
    ```

    Create the NMState instance:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: nmstate.io/v1
    kind: NMState
    metadata:
      name: nmstate
    EOF
    ```

    Wait for the handler pods to be ready:

    ```bash
    kubectl rollout status daemonset -n openshift-nmstate nmstate-handler --timeout=300s
    ```

=== "Kubernetes"

    Install NMState from upstream manifests:

    ```bash
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/nmstate.io_nmstates.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/namespace.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/service_account.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/role.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/role_binding.yaml
    kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/latest/download/operator.yaml
    ```

    Create the NMState instance:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: nmstate.io/v1
    kind: NMState
    metadata:
      name: nmstate
    EOF
    ```

    Wait for the handler pods to be ready:

    ```bash
    kubectl rollout status daemonset -n nmstate nmstate-handler --timeout=300s
    ```
