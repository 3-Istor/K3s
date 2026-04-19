# Reference manual vars: https://developer.hashicorp.com/terraform/language/block/variable#specification

# variable "fixme_var" {
#   description = "An example of a var"
#   type        = string
#   sensitive   = true # Specifies if terraform hides this value in CLI output
# }

# Doc: https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/kv_secret_v2
# resource "vault_kv_secret_v2" "fixme_secret" {
#   mount               = vault_mount.kvv2.path
#   name                = "fixme/path"
#   cas                 = 1
#   delete_all_versions = true
#   data_json = jsonencode({
#     FIXME_KEY = var.fixme_var
#   })
# }


# -----------------------------------------------------------------------------
# Cloudflare Secrets
# -----------------------------------------------------------------------------

variable "cloudflare_api_token_secret_var" {
  description = "Cloudflare API token with permissions to manage DNS records."
  type        = string
  sensitive   = true
}

resource "vault_kv_secret_v2" "cloudflared_token" {
  mount = vault_mount.kvv2.path
  name  = "cloudflared/token"
  data_json = jsonencode({
    token = local.generated_tunnel_token
  })
}

# -----------------------------------------------------------------------------
# Cert-Manager Secrets
# -----------------------------------------------------------------------------

resource "vault_kv_secret_v2" "cert_manager_cloudflare_api_token_secret" {
  mount = vault_mount.kvv2.path
  name  = "cert-manager/cloudflare-api-token"
  data_json = jsonencode({
    api-token = var.cloudflare_api_token_secret_var
  })
}

# -----------------------------------------------------------------------------
# Keycloak Secrets
# -----------------------------------------------------------------------------

variable "keycloak_db_password" {
  type      = string
  sensitive = true
}

resource "vault_kv_secret_v2" "keycloak_db" {
  mount     = vault_mount.kvv2.path
  name      = "keycloak/db"
  data_json = jsonencode({ password = var.keycloak_db_password })
}

resource "vault_kv_secret_v2" "keycloak_admin" {
  mount     = vault_mount.kvv2.path
  name      = "keycloak/admin"
  data_json = jsonencode({ password = var.keycloak_admin_password })
}

# -----------------------------------------------------------------------------
# ArgoCD Secrets
# -----------------------------------------------------------------------------

variable "argocd_admin_password" {
  type      = string
  sensitive = true
}

resource "vault_kv_secret_v2" "argocd_oidc" {
  mount = vault_mount.kvv2.path
  name  = "argocd/oidc"
  data_json = jsonencode({
    "oidc.keycloak.clientSecret" = keycloak_openid_client.argocd.client_secret
  })
}


# -----------------------------------------------------------------------------
# Demo App Secrets
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "demo_app_envoy_auth" {
  mount = vault_mount.kvv2.path
  name  = "demo-app/envoy-auth"
  data_json = jsonencode({
    "client-secret" = keycloak_openid_client.openid_client.client_secret
  })
}
