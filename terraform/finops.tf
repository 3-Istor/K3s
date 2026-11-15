# -----------------------------------------------------------------------------
# FinOps: identity the CMP federates to AWS STS and GCP Workload Identity
# -----------------------------------------------------------------------------
# The CMP reads the AWS and GCP invoices without any static cloud key: it gets
# a client-credentials token from this client and exchanges it at AWS STS
# (role cnp-finops-reader) and Google STS (pool cnp-finops). Both clouds trust
# the token only for aud=cnp-finops and this service account's sub
# (Cloud repo, terraform/public/{aws,gcp}/billing).

resource "keycloak_openid_client" "cnp_finops" {
  realm_id                     = keycloak_realm.kube_lab.id
  client_id                    = "cnp-finops"
  name                         = "CNP FinOps billing reader"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = true
  access_token_lifespan        = "300"
}

# AWS STS rejects a token whose aud is a list, so the token must carry no
# other audience: "basic" only (it holds the sub mapper), no "roles" scope,
# which would add "account".
resource "keycloak_openid_client_default_scopes" "cnp_finops" {
  realm_id       = keycloak_realm.kube_lab.id
  client_id      = keycloak_openid_client.cnp_finops.id
  default_scopes = ["basic"]
}

resource "keycloak_openid_client_optional_scopes" "cnp_finops" {
  realm_id        = keycloak_realm.kube_lab.id
  client_id       = keycloak_openid_client.cnp_finops.id
  optional_scopes = []
}

resource "keycloak_openid_audience_protocol_mapper" "cnp_finops" {
  realm_id                 = keycloak_realm.kube_lab.id
  client_id                = keycloak_openid_client.cnp_finops.id
  name                     = "audience-cnp-finops"
  included_custom_audience = "cnp-finops"
  add_to_access_token      = true
  add_to_id_token          = false
}

resource "vault_kv_secret_v2" "arcl_cmp_finops_oidc" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/finops-oidc"
  data_json = jsonencode({
    "client-id"     = keycloak_openid_client.cnp_finops.client_id
    "client-secret" = keycloak_openid_client.cnp_finops.client_secret
  })
}

# Goes to finops_oidc_subject of both billing roots.
output "cnp_finops_subject" {
  value = keycloak_openid_client.cnp_finops.service_account_user_id
}
