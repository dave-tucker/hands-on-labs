#### Install KubeVirt

=== "OpenShift"

    Create the namespace, OperatorGroup, and Subscription:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: openshift-cnv
      labels:
        openshift.io/cluster-monitoring: "true"
    ---
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: kubevirt-hyperconverged-group
      namespace: openshift-cnv
    spec:
      targetNamespaces:
        - openshift-cnv
    ---
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: hco-operatorhub
      namespace: openshift-cnv
    spec:
      source: redhat-operators
      sourceNamespace: openshift-marketplace
      name: kubevirt-hyperconverged
      startingCSV: kubevirt-hyperconverged-operator.v4.20.7
      channel: "stable"
    EOF
    ```

    Wait for the operator CSV to succeed:

    ```bash
    kubectl get csv -n openshift-cnv -w
    ```

    Create the HyperConverged instance:

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: hco.kubevirt.io/v1beta1
    kind: HyperConverged
    metadata:
      name: kubevirt-hyperconverged
      namespace: openshift-cnv
    EOF
    ```

    Wait for the deployment to complete:

    ```bash
    kubectl wait hyperconverged kubevirt-hyperconverged -n openshift-cnv \
      --for=condition=Available --timeout=600s
    ```

=== "Kubernetes"

    Install KubeVirt from upstream release manifests:

    ```bash
    export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | grep tag_name | cut -d '"' -f 4)
    kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
    kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
    ```

    Wait for KubeVirt to be ready:

    ```bash
    kubectl wait kubevirt kubevirt -n kubevirt \
      --for=condition=Available --timeout=600s
    ```
