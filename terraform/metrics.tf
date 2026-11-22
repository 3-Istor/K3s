# VMSingle serves reads, writes and its admin endpoints (delete, snapshot,
# reload...) on one port. The admin ones only answer with this key.
resource "random_password" "vmsingle_admin_key" {
  length  = 40
  special = false
}

resource "vault_kv_secret_v2" "vmsingle_auth_keys" {
  mount = vault_mount.kvv2.path
  name  = "observability/vmsingle"
  data_json = jsonencode({
    "ADMIN_AUTH_KEY" = random_password.vmsingle_admin_key.result
  })
}

# The CMP derives each project's vmauth password from this key.
resource "random_password" "metrics_project_key" {
  length  = 64
  special = false
}

resource "vault_kv_secret_v2" "arcl_cmp_metrics" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/metrics"
  data_json = jsonencode({
    "metrics-project-key" = random_password.metrics_project_key.result
  })
}
