path "kvv2/data/*" {
  capabilities = ["read"]
}
path "kvv2/metadata/*" {
  capabilities = ["list", "read"]
}

path "project-*/data/*" {
  capabilities = ["read"]
}
path "project-*/metadata/*" {
  capabilities = ["list", "read"]
}
