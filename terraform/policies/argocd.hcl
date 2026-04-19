# ArgoCD Policy
path "${mount_path}/data/argocd/*" {
  capabilities = ["read"]
}
