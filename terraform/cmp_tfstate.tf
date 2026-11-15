# -----------------------------------------------------------------------------
# CMP: identity federated to AWS STS for the Terraform state bucket
# -----------------------------------------------------------------------------
# Replaces the static key of IAM user cmp-tfstate. The CMP trades a
# client-credentials token of this client for a one-hour session of role
# cnp-tfstate-cmp (Cloud repo, terraform/public/aws/cmp-iam), which trusts only
# aud=cnp-tfstate and this service account's sub.
#
# A client apart from cnp-finops: the billing reader's secret must not open
# write access to every project state, and each can be revoked on its own.

resource "keycloak_openid_client" "cnp_tfstate" {
  realm_id                     = keycloak_realm.kube_lab.id
  client_id                    = "cnp-tfstate"
  name                         = "CMP Terraform state (AWS)"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = true
  access_token_lifespan        = "300"
}

# AWS STS rejects a token whose aud is a list: "basic" only, as for cnp-finops.
resource "keycloak_openid_client_default_scopes" "cnp_tfstate" {
  realm_id       = keycloak_realm.kube_lab.id
  client_id      = keycloak_openid_client.cnp_tfstate.id
  default_scopes = ["basic"]
}

resource "keycloak_openid_client_optional_scopes" "cnp_tfstate" {
  realm_id        = keycloak_realm.kube_lab.id
  client_id       = keycloak_openid_client.cnp_tfstate.id
  optional_scopes = []
}

resource "keycloak_openid_audience_protocol_mapper" "cnp_tfstate" {
  realm_id                 = keycloak_realm.kube_lab.id
  client_id                = keycloak_openid_client.cnp_tfstate.id
  name                     = "audience-cnp-tfstate"
  included_custom_audience = "cnp-tfstate"
  add_to_access_token      = true
  add_to_id_token          = false
}

resource "vault_kv_secret_v2" "arcl_cmp_tfstate_oidc" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/tfstate-oidc"
  data_json = jsonencode({
    "client-id"     = keycloak_openid_client.cnp_tfstate.client_id
    "client-secret" = keycloak_openid_client.cnp_tfstate.client_secret
  })
}

# Goes to oidc_subject of the Cloud cmp-iam root.
output "cnp_tfstate_subject" {
  value = keycloak_openid_client.cnp_tfstate.service_account_user_id
}
