# -----------------------------------------------------------------------------
# OIDC CLIENT: 3-Istor OpenID Client
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "openid_client" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = "3-istor-openid"

  name    = "3-Istor OpenID Client"
  enabled = true

  access_type                               = "CONFIDENTIAL"
  standard_flow_enabled                     = true
  direct_access_grants_enabled              = false
  implicit_flow_enabled                     = false
  service_accounts_enabled                  = true
  standard_token_exchange_enabled           = false
  oauth2_device_authorization_grant_enabled = false

  valid_redirect_uris = [
    "https://demo.${var.base_domain}/oauth2/callback",
    "https://roadmap.${var.base_domain}/oauth2/callback",
    "https://offhours-guard.${var.base_domain}/oauth2/callback",
    "https://cmp.${var.base_domain}/oauth2/callback",
    "https://cmp.${var.base_domain}/api/auth/callback/keycloak",
    "https://mepa.${var.base_domain}/oauth2/callback",
    "https://qcm.${var.base_domain}/api/auth/callback/keycloak",
    "http://localhost:3000/api/auth/callback/keycloak",
    "http://localhost:3001/api/auth/callback/keycloak",
    "https://grafana.${var.base_domain}/login/generic_oauth"
  ]

  valid_post_logout_redirect_uris = [
    "https://demo.${var.base_domain}/",
    "https://roadmap.${var.base_domain}/",
    "https://offhours-guard.${var.base_domain}/",
    "https://cmp.${var.base_domain}/",
    "https://mepa.${var.base_domain}/",
    "https://qcm.${var.base_domain}/",
    "http://localhost:3000/",
    "http://localhost:3001/",
    "https://grafana.${var.base_domain}/"
  ]

  web_origins = [
    "https://demo.${var.base_domain}",
    "https://roadmap.${var.base_domain}",
    "https://offhours-guard.${var.base_domain}",
    "https://cmp.${var.base_domain}",
    "https://mepa.${var.base_domain}",
    "https://qcm.${var.base_domain}",
    "http://localhost:3000",
    "http://localhost:3001",
    "https://grafana.${var.base_domain}"
  ]

  extra_config = {
    "acr.loa.map" = local.acr_loa_map
  }

  # Flow v6 (step-up) once the theme serving the passkey scripts is deployed: swap the two
  # browser_id lines, here and on the vault client, together with STEP_UP_ENABLED in
  # k8s/config/arcl-cmp/cmp-values.yaml.
  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.browser_v6.id
  }
}


# -----------------------------------------------------------------------------
# OIDC CLIENT: ArgoCD
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "argocd" {
  realm_id                     = keycloak_realm.kube_lab.id
  client_id                    = "argocd"
  name                         = "ArgoCD"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false

  valid_redirect_uris = [
    "https://argocd.${var.base_domain}/auth/callback"
  ]

  valid_post_logout_redirect_uris = [
    "https://argocd.${var.base_domain}/"
  ]
}

resource "keycloak_openid_client_default_scopes" "argocd_scopes" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = keycloak_openid_client.argocd.id
  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    keycloak_openid_client_scope.groups.name
  ]
}

# -----------------------------------------------------------------------------
# OIDC CLIENT: Vault
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "vault" {
  realm_id                     = keycloak_realm.kube_lab.id
  client_id                    = "vault"
  name                         = "Vault"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false

  valid_redirect_uris = [
    "https://vault.${var.base_domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]

  extra_config = {
    "acr.loa.map" = local.acr_loa_map
  }

  # Flow v6: switch with the 3-istor-openid client above.
  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.browser_v6.id
  }
}

resource "keycloak_openid_client_default_scopes" "vault_scopes" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = keycloak_openid_client.vault.id
  default_scopes = [
    "profile",
    "email",
    "groups"
  ]
}


resource "keycloak_openid_client_service_account_role" "cmp_manage_users" {
  realm_id                = keycloak_realm.kube_lab.id
  service_account_user_id = keycloak_openid_client.openid_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = "manage-users"
}

# Access reviews read login events to date each user's last login.
resource "keycloak_openid_client_service_account_role" "cmp_view_events" {
  realm_id                = keycloak_realm.kube_lab.id
  service_account_user_id = keycloak_openid_client.openid_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = "view-events"
}
data "keycloak_openid_client" "realm_management" {
  # A literal, not keycloak_realm.kube_lab.id: any pending realm change would defer this read
  # to apply time and force a replacement of cmp_manage_users, removing the role meanwhile.
  realm_id  = "3istor"
  client_id = "realm-management"
}

# -----------------------------------------------------------------------------
# OIDC CLIENT: kubeLogin (used for kubectl OIDC authentication)
# -----------------------------------------------------------------------------

resource "keycloak_openid_client" "k3s_api" {
  realm_id                     = keycloak_realm.kube_lab.id
  client_id                    = "k3s-cluster"
  name                         = "K3s Cluster API"
  enabled                      = true
  access_type                  = "PUBLIC"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true

  # kube-apiserver reads the groups from the ID token on every call, so an
  # ended elevated-k3s-admin grant lasts until the token expires: 5 minutes
  # instead of the realm's hour (CNP-124). kubelogin refreshes silently.
  access_token_lifespan = "300"

  valid_redirect_uris = [
    "http://localhost:8000",
    "http://localhost:18000"
  ]
}

resource "keycloak_openid_client_default_scopes" "k3s_api_scopes" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = keycloak_openid_client.k3s_api.id
  default_scopes = [
    "profile",
    "email",
    "groups",
    keycloak_openid_client_scope.groups.name
  ]
}
