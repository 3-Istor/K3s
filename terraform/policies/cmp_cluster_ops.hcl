# CMP cluster up/down: what the cluster-addons module reads and writes in Vault.
path "${mount_path}/data/argocd/clusters/*" {
  capabilities = ["create", "update", "read"]
}

path "${mount_path}/data/cnp-vpn/*" {
  capabilities = ["read"]
}

# Vault globs only match a trailing "*": one explicit path per cloud.
path "auth/kubernetes-aws/config" {
  capabilities = ["create", "update", "read"]
}

path "auth/kubernetes-gcp/config" {
  capabilities = ["create", "update", "read"]
}
