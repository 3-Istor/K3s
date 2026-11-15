# VictoriaLogs serves ingestion, queries and its admin endpoints (flags,
# force merge, partitions...) on one port. The admin ones only answer with
# this key.
resource "random_password" "vlogs_admin_key" {
  length  = 40
  special = false
}

resource "vault_kv_secret_v2" "vlogs_auth_keys" {
  mount = vault_mount.kvv2.path
  name  = "observability/vlogs"
  data_json = jsonencode({
    "ADMIN_AUTH_KEY" = random_password.vlogs_admin_key.result
  })
}
