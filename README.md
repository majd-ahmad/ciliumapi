# 1. Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# 2. Cleanup conflicting Calico resources
kubectl delete ns calico-system tigera-operator --ignore-not-found

# 3. Apply the Gateway and Route manifests
kubectl apply -f cilium-gateway-setup.yaml

# 4. Restart Operator to initialize Gateway Controller
kubectl rollout restart deployment cilium-operator -n kube-system
