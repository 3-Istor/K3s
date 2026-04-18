resource "keycloak_group" "admin" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "admin"
}

resource "keycloak_group" "developer" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "developer"
}

resource "keycloak_group" "sre" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "sre"
}
