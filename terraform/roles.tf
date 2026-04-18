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
