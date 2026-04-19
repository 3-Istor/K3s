# Vault Secrets Operator Policy
path "kvv2/data/*" {
  capabilities = ["read"]
}
path "kvv2/metadata/*" {
  capabilities = ["list", "read"]
}
