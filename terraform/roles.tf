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
# Wireguard Roles
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "wireguard_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "wireguard-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.wireguard_policy.name]
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

resource "vault_kubernetes_auth_backend_role" "vault_secrets_operator_role_cloud" {
  for_each                         = toset(["aws", "gcp"])
  backend                          = vault_auth_backend.kubernetes_cloud[each.key].path
  role_name                        = "vault-secrets-operator-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400 # 24h
  token_policies                   = [vault_policy.vault_secrets_operator_policy.name]
}

resource "vault_kubernetes_auth_backend_role" "observability_cloud" {
  for_each                         = vault_auth_backend.kubernetes_cloud
  backend                          = each.value.path
  role_name                        = "observability-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400 # 24h
  token_policies                   = [vault_policy.cloud_observability_policy.name]
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
  # External group membership is read at login only, so an elevation ended in
  # Keycloak lasts in Vault until the token dies: the max TTL bounds that lag
  # (CNP-124). Renewals do not re-read the groups.
  token_ttl     = 900
  token_max_ttl = 3600
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

# Just-in-time vault-data elevation (CNP-124): the alias matches the Keycloak
# group the CMP fills while a grant is active.
resource "vault_identity_group" "elevated_vault_data" {
  name     = "elevated-vault-data"
  type     = "external"
  policies = [vault_policy.vault_data_admin.name]
}

resource "vault_identity_group_alias" "elevated_vault_data" {
  name           = keycloak_group.elevated["vault-data"].name
  mount_accessor = vault_jwt_auth_backend.keycloak.accessor
  canonical_id   = vault_identity_group.elevated_vault_data.id
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

# -----------------------------------------------------------------------------
# n8n Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "n8n_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "n8n-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.n8n_policy.name]
}

# -----------------------------------------------------------------------------
# Roadmap Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "roadmap_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "roadmap-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.roadmap_policy.name]
}

# -----------------------------------------------------------------------------
# Offhours-Guard Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "offhours_guard_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "offhours-guard-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.offhours_guard_policy.name]
}

# -----------------------------------------------------------------------------
# MEPA Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "mepa_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "mepa-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.mepa_policy.name]
}

# -----------------------------------------------------------------------------
# QCM Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "qcm_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "qcm-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.qcm_policy.name]
}


# -----------------------------------------------------------------------------
# Status Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "status_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "status-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.status_policy.name]
}


# -----------------------------------------------------------------------------
# GitHub Actions Roles
# -----------------------------------------------------------------------------
resource "vault_jwt_auth_backend_role" "github_actions_dockair" {
  backend        = vault_jwt_auth_backend.github.path
  role_name      = "github-actions-dockair"
  token_policies = [vault_policy.github_actions_dockair.name]

  role_type = "jwt"
  token_ttl = 3600

  bound_audiences = ["https://github.com/TheGostsniperfr"]

  bound_claims_type = "glob"
  bound_claims = {
    sub = "repo:TheGostsniperfr/infra-dockair-sandbox:*"
  }

  user_claim = "actor"
}

# -----------------------------------------------------------------------------
# Linmap-Bot Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "linmap_bot_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "linmap-bot-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.linmap_bot_policy.name]
}

# -----------------------------------------------------------------------------
# Observability Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "observability_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "observability-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.observability_policy.name]
}

# The secret-age CronJob (observability) logs in as its own service account,
# not through the operator: it reads KV metadata, which no VaultSecret needs.
resource "vault_kubernetes_auth_backend_role" "secret_age" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "secret-age"
  bound_service_account_names      = ["secret-age"]
  bound_service_account_namespaces = ["observability"]
  token_ttl                        = 300
  token_max_ttl                    = 600
  token_policies                   = [vault_policy.secret_age.name]
}

# -----------------------------------------------------------------------------
# Rook Ceph Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "rook_ceph_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "rook-ceph-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.rook_ceph_policy.name]
}

# -----------------------------------------------------------------------------
# 3istor Sessions Roles
# -----------------------------------------------------------------------------
resource "vault_kubernetes_auth_backend_role" "trois_istor_sessions_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "3istor-sessions-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.trois_istor_sessions_policy.name]
}

# -----------------------------------------------------------------------------
# CMP backend: its own Vault identity, in place of a static token
# -----------------------------------------------------------------------------
locals {
  cmp_backend_role_name = "cmp-backend"

  # The CMP manages app auth roles on these mounts, named "<project>-<app>-role"
  # with no prefix of their own: every platform role there is denied to it by
  # name. A role added to one of these mounts must be listed here.
  cmp_backend_auth_mounts = concat(
    [vault_auth_backend.kubernetes.path],
    [for mount in vault_auth_backend.kubernetes_cloud : mount.path],
  )
  platform_kubernetes_roles = concat(
    [
      vault_kubernetes_auth_backend_role.cert_manager_role,
      vault_kubernetes_auth_backend_role.keycloak_role,
      vault_kubernetes_auth_backend_role.cloudflared_role,
      vault_kubernetes_auth_backend_role.wireguard_role,
      vault_kubernetes_auth_backend_role.demo_app_role,
      vault_kubernetes_auth_backend_role.vault_secrets_operator_role,
      vault_kubernetes_auth_backend_role.argocd_role,
      vault_kubernetes_auth_backend_role.arcl_cmp_role,
      vault_kubernetes_auth_backend_role.n8n_role,
      vault_kubernetes_auth_backend_role.roadmap_role,
      vault_kubernetes_auth_backend_role.offhours_guard_role,
      vault_kubernetes_auth_backend_role.mepa_role,
      vault_kubernetes_auth_backend_role.qcm_role,
      vault_kubernetes_auth_backend_role.status_role,
      vault_kubernetes_auth_backend_role.linmap_bot_role,
      vault_kubernetes_auth_backend_role.observability_role,
      vault_kubernetes_auth_backend_role.rook_ceph_role,
      vault_kubernetes_auth_backend_role.trois_istor_sessions_role,
      vault_kubernetes_auth_backend_role.secret_age,
    ],
    values(vault_kubernetes_auth_backend_role.vault_secrets_operator_role_cloud),
    values(vault_kubernetes_auth_backend_role.observability_cloud),
  )
  # Out of the CMP's reach in cmp_backend.hcl: it may not edit them or alias
  # anything to them.
  platform_identity_groups = [
    vault_identity_group.infra,
    vault_identity_group.member,
    vault_identity_group.elevated_vault_data,
  ]
}

resource "vault_kubernetes_auth_backend_role" "cmp_backend" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = local.cmp_backend_role_name
  bound_service_account_names      = ["arcl-cmp"]
  bound_service_account_namespaces = ["arcl-cmp"]
  token_ttl                        = 3600
  # Renewed by the CMP up to this, then it logs in again.
  token_max_ttl  = 14400
  token_policies = [vault_policy.cmp_backend.name]
}
