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

# -----------------------------------------------------------------------------
# CMP Secrets
# -----------------------------------------------------------------------------

variable "os_auth_url" {
  type = string
}

variable "os_project_name" {
  type = string
}

variable "os_username" {
  type      = string
  sensitive = true
}

variable "os_password" {
  type      = string
  sensitive = true
}

variable "os_user_domain_name" {
  type = string
}

variable "os_project_domain_name" {
  type = string
}

variable "os_endpoint_type" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_s3_bucket" {
  type = string
}

variable "aws_s3_key_prefix" {
  type = string
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

variable "avatars_s3_access_key_id" {
  type      = string
  sensitive = true
}

variable "avatars_s3_secret_key" {
  type      = string
  sensitive = true
}

variable "avatars_s3_endpoint" {
  type    = string
  default = "https://s3.3istor.com"
}

variable "avatars_s3_bucket" {
  type    = string
  default = "user-avatars"
}

variable "avatars_s3_region" {
  type    = string
  default = "eu-west-3"
}

variable "avatars_s3_public_url_base" {
  type    = string
  default = "https://avatars-s3.3istor.com"
}

variable "discord_webhook_url" {
  type      = string
  sensitive = true
}



resource "vault_kv_secret_v2" "arcl_cmp_creds" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/credentials"

  data_json = jsonencode({
    "os-auth-url"                  = var.os_auth_url
    "os-project-name"              = var.os_project_name
    "os-username"                  = var.os_username
    "os-password"                  = var.os_password
    "os-project-domain-name"       = var.os_project_domain_name
    "os-endpoint-type"             = var.os_endpoint_type
    "os-user-domain-name"          = var.os_user_domain_name
    "aws-access-key-id"            = var.aws_access_key_id
    "aws-region"                   = var.aws_region
    "aws-s3-bucket"                = var.aws_s3_bucket
    "aws-s3-key-prefix"            = var.aws_s3_key_prefix
    "aws-secret-access-key"        = var.aws_secret_key
    "avatars-s3-access-key-id"     = var.avatars_s3_access_key_id
    "avatars-s3-secret-access-key" = var.avatars_s3_secret_key
    "avatars-s3-endpoint"          = var.avatars_s3_endpoint
    "avatars-s3-bucket"            = var.avatars_s3_bucket
    "avatars-s3-region"            = var.avatars_s3_region
    "avatars-s3-public-url-base"   = var.avatars_s3_public_url_base
    "cloudflare-api-token"         = var.cloudflare_api_token_secret_var
    "cloudflare-zone-id"           = var.cloudflare_zone_id
    "discord-webhook-url"          = var.discord_webhook_url
  })
}

resource "vault_kv_secret_v2" "arcl_cmp_envoy_auth" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/envoy-auth"
  data_json = jsonencode({
    "client-secret" = keycloak_openid_client.openid_client.client_secret
  })
}


variable "nextauth_secret" {
  type      = string
  sensitive = true
}


resource "vault_kv_secret_v2" "arcl_cmp_frontend" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/frontend"
  data_json = jsonencode({
    "nextauth-secret" = var.nextauth_secret
  })
}

# -----------------------------------------------------------------------------
# n8n Secrets
# -----------------------------------------------------------------------------
variable "n8n_db_password" {
  type      = string
  sensitive = true
}

variable "n8n_encryption_key" {
  type      = string
  sensitive = true
}

resource "vault_kv_secret_v2" "n8n_db" {
  mount = vault_mount.kvv2.path
  name  = "n8n/db"
  data_json = jsonencode({
    username = "n8n"
    password = var.n8n_db_password
  })
}

resource "vault_kv_secret_v2" "n8n_encryption_key" {
  mount = vault_mount.kvv2.path
  name  = "n8n/encryption-key"
  data_json = jsonencode({
    key = var.n8n_encryption_key
  })
}
