# resource "vault_kubernetes_auth_backend_role" "fixme_role" {
#   backend                          = vault_auth_backend.kubernetes.path
#   role_name                        = "fixme-role"
#   bound_service_account_names      = ["vault-secrets-operator"]
#   bound_service_account_namespaces = ["vault-secrets-operator"]
#   token_ttl                        = 86400 # 24h
#   token_policies                   = [vault_policy.fixme_policy.name]
#   audience                         = vault_kubernetes_auth_backend_config.kubernetes_auth.issuer
# }

# -----------------------------------------------------------------------------
# Cert-Manager Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "cert_manager_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cert-manager-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400 # 24h
  token_policies                   = [vault_policy.cert_manager_policy.name]
}

# -----------------------------------------------------------------------------
# Keycloak Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "keycloak_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "keycloak-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.keycloak_policy.name]
}

# -----------------------------------------------------------------------------
# Cloudflared Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "cloudflared_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cloudflared-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.cloudflared_policy.name]
}

# -----------------------------------------------------------------------------
# Demo App Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "demo_app_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "demo-app-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.demo_app_policy.name]
}

# -----------------------------------------------------------------------------
# VSO Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "vault_secrets_operator_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vault-secrets-operator-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400 # 24h
  token_policies                   = [vault_policy.vault_secrets_operator_policy.name]
}

# -----------------------------------------------------------------------------
# ArgoCD Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "argocd_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "argocd-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.argocd_policy.name]
}

# -----------------------------------------------------------------------------
# Vault Admin Roles
# -----------------------------------------------------------------------------

resource "vault_jwt_auth_backend_role" "default" {
  backend        = vault_jwt_auth_backend.keycloak.path
  role_name      = "default"
  token_policies = ["default"]
  user_claim     = "preferred_username"
  role_type      = "oidc"
  groups_claim   = "groups"
  allowed_redirect_uris = [
    "https://vault.${var.base_domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

resource "vault_identity_group" "infra" {
  name     = "infra"
  type     = "external"
  policies = [vault_policy.vault_admin.name]
}

resource "vault_identity_group_alias" "infra_alias" {
  name           = "infra"
  mount_accessor = vault_jwt_auth_backend.keycloak.accessor
  canonical_id   = vault_identity_group.infra.id
}

# -----------------------------------------------------------------------------
# CMP Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "arcl_cmp_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "arcl-cmp-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.arcl_cmp_policy.name]
}
