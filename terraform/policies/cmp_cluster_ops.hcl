# CMP cluster up/down: what the cluster-addons module reads and writes in Vault.
path "kvv2/data/argocd/clusters/*" {
  capabilities = ["create", "update", "read"]
}

path "kvv2/data/cnp-vpn/*" {
  capabilities = ["read"]
}

path "auth/kubernetes-*/config" {
  capabilities = ["create", "update", "read"]
}
