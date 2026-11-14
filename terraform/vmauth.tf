# vmauth serves /metrics, /flags and /debug/pprof on the port it proxies.
# vmagent sends the metrics key when it scrapes; the admin key is for people.
resource "random_password" "vmauth_auth_key" {
  for_each = toset(["metrics", "admin"])
  length   = 40
  special  = false
}

resource "vault_kv_secret_v2" "vmauth_auth_keys" {
  mount = vault_mount.kvv2.path
  name  = "observability/vmauth"
  data_json = jsonencode({
    "METRICS_AUTH_KEY" = random_password.vmauth_auth_key["metrics"].result
    "ADMIN_AUTH_KEY"   = random_password.vmauth_auth_key["admin"].result
  })
}
