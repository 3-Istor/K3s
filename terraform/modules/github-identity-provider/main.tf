# Account linking only: users must first authenticate to their existing CNP account.
resource "keycloak_oidc_github_identity_provider" "github" {
  realm         = var.realm_id
  alias         = "github"
  display_name  = "GitHub"
  client_id     = var.client_id
  client_secret = var.client_secret

  enabled                       = true
  link_only                     = true
  hide_on_login_page            = true
  trust_email                   = false
  store_token                   = false
  add_read_token_role_on_create = false
  github_json_format            = true
  default_scopes                = "user:email"
  sync_mode                     = "IMPORT"

  lifecycle {
    prevent_destroy = true
  }
}
