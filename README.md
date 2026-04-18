# Apply kube Config

```bash
kustomize build k8s/ --enable-helm | kubectl apply --server-side --force-conflicts -f -
```

# Get Base64 data:
```bash
kubectl get secret argocd-initial-admin-secret  -n argocd -o json | jq '.data | map_values(@base64d)'
```
