path "kvv2/data/dockair-sandbox/ci" {
  capabilities = ["read"]
}

path "kvv2/data/dockair-sandbox/*/talos/cluster-secrets" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kvv2/metadata/dockair-sandbox/*" {
  capabilities = ["read", "list", "delete"]
}
