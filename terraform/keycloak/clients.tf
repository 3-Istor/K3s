# -----------------------------------------------------------------------------
# OIDC CLIENT: DEMO APP
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "envoy_demo_app" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = "envoy-demo-app"

  name    = "Envoy Proxy - Demo App"
  enabled = true

  access_type                               = "CONFIDENTIAL"
  standard_flow_enabled                     = true
  direct_access_grants_enabled              = false
  implicit_flow_enabled                     = false
  service_accounts_enabled                  = false
  standard_token_exchange_enabled           = false
  oauth2_device_authorization_grant_enabled = false

  valid_redirect_uris = [
    "https://demo.${var.base_domain}/oauth2/callback"
  ]

  valid_post_logout_redirect_uris = [
    "https://demo.${var.base_domain}/"
  ]

  web_origins = [
    "https://demo.${var.base_domain}"
  ]

  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.browser_demo_app.id
  }
}

# -----------------------------------------------------------------------------
# OIDC CLIENT: ARGOCD
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "argocd" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = "argocd"

  name    = "ArgoCD SSO"
  enabled = true

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true

  valid_redirect_uris = [
    "https://argocd.${var.base_domain}/auth/callback",
    "https://argocd.${var.base_domain}/api/dex/callback"
  ]

  web_origins = [
    "https://argocd.${var.base_domain}"
  ]
}
