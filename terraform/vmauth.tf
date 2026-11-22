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

# One writer and one reader per cloud (D22). The cloud's collectors read
# them through its own Vault auth backend, vmauth clouds through
# observability-policy.
resource "random_password" "cloud_observability" {
  for_each = toset(flatten([for c in ["aws", "gcp"] : ["${c}-writer", "${c}-reader"]]))
  length   = 40
  special  = false
}

resource "vault_kv_secret_v2" "cloud_observability" {
  for_each = toset(["aws", "gcp"])
  mount    = vault_mount.kvv2.path
  name     = "observability/clouds/${each.key}"
  data_json = jsonencode({
    "writer_password" = random_password.cloud_observability["${each.key}-writer"].result
    "reader_password" = random_password.cloud_observability["${each.key}-reader"].result
  })
}
