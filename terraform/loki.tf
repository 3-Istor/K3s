# Basic-auth credentials of the Loki gateway, one per client so a leaked one
# can be revoked alone. Each client reads its own plaintext; the gateway only
# gets the bcrypt hashes. Loki itself has no authentication.
locals {
  loki_clients = ["alloy", "grafana", "archive", "cmp"]
}

resource "random_password" "loki_client" {
  for_each = toset(local.loki_clients)
  length   = 40
  special  = false
}

resource "vault_kv_secret_v2" "loki_gateway" {
  mount = vault_mount.kvv2.path
  name  = "observability/loki-gateway"
  data_json = jsonencode({
    ".htpasswd" = join("", [
      for c in local.loki_clients : "${c}:${random_password.loki_client[c].bcrypt_hash}\n"
    ])
  })
}

resource "vault_kv_secret_v2" "loki_clients" {
  mount = vault_mount.kvv2.path
  name  = "observability/loki-clients"
  data_json = jsonencode({
    "ALLOY_LOKI_PASSWORD"   = random_password.loki_client["alloy"].result
    "GRAFANA_LOKI_PASSWORD" = random_password.loki_client["grafana"].result
    "ARCHIVE_LOKI_PASSWORD" = random_password.loki_client["archive"].result
  })
}

resource "vault_kv_secret_v2" "arcl_cmp_loki" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/loki"
  data_json = jsonencode({
    "loki-password" = random_password.loki_client["cmp"].result
  })
}
