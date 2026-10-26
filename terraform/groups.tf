resource "keycloak_group" "infra" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "infra"
}

resource "keycloak_group" "member" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "member"
}

resource "keycloak_group" "k3s_admin" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "k3s-admin"
}

resource "keycloak_group" "k3s_dev" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "k3s-dev"
}

resource "keycloak_group" "k3s_view" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "k3s-view"
}

# FinOps finance role (plan FinOps I5): read and export every project's costs
# in the CMP, close months, deploy nothing.
resource "keycloak_group" "cnp_finance" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "cnp-finance"
}
