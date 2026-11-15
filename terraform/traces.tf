# VictoriaTraces serves reads, writes and its admin endpoints (delete, force
# merge, partitions...) on one port. The admin ones only answer with this key.
resource "random_password" "vtraces_admin_key" {
  length  = 40
  special = false
}

resource "vault_kv_secret_v2" "vtraces_auth_keys" {
  mount = vault_mount.kvv2.path
  name  = "observability/vtraces"
  data_json = jsonencode({
    "ADMIN_AUTH_KEY" = random_password.vtraces_admin_key.result
  })
}
