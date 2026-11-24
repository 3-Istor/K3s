resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"

  # Caps the roles' 24h token_ttl. vault-secrets-operator logs in on every
  # reconcile and never revokes, so 24h tokens piled up by the tens of
  # thousands in vault.db. Clients here re-login on expiry (CMP, secret-age).
  # The CMP needs 45 min for a Terraform run, so not below 1h.
  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "1h"
  }
}

resource "vault_kubernetes_auth_backend_config" "kubernetes_auth" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = var.k8s_host_url
  # kubernetes_ca_cert     = "" # TODO Check the goal of CA cert configuration
  # token_reviewer_jwt     = "" # TODO Check the goal of token reviewer JWT configuration
  issuer                 = var.k8s_host_url
  disable_iss_validation = "true"
}

# Config is written by Cloud cluster-addons on each cluster up; never destroy
# these mounts, as destroying them also removes the CMP roles.
resource "vault_auth_backend" "kubernetes_cloud" {
  for_each = toset(["aws", "gcp"])
  type     = "kubernetes"
  path     = "kubernetes-${each.key}"

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# OIDC Auth Backend for Vault
# -----------------------------------------------------------------------------
resource "vault_jwt_auth_backend" "keycloak" {
  description        = "OIDC backend via Keycloak"
  path               = "oidc"
  type               = "oidc"
  oidc_discovery_url = "${var.keycloak_url}/realms/${keycloak_realm.kube_lab.realm}"
  oidc_client_id     = keycloak_openid_client.vault.client_id
  oidc_client_secret = keycloak_openid_client.vault.client_secret
  default_role       = "default"
}

# -----------------------------------------------------------------------------
# OIDC Auth Backend for GitHub Actions
# -----------------------------------------------------------------------------
resource "vault_jwt_auth_backend" "github" {
  description        = "OIDC backend for GitHub Actions"
  path               = "jwt"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"
}
