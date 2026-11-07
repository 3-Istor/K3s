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

# Platform identities of the access matrix (cnp-docs model.yaml, CNP-228).
# The portal and the tools read them from the token's groups claim.

# FinOps: every project's costs, exports and month close; deploys nothing.
resource "keycloak_group" "finops" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "finops"
}

moved {
  from = keycloak_group.cnp_finance
  to   = keycloak_group.finops
}

# Auditor: reads every project except logs and secrets, approves critical
# CVE exceptions.
resource "keycloak_group" "security_auditor" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "security-auditor"
}

# Platform admins (infra and portal alike) and cluster-admin kubectl. These two
# groups are authoritative here: a member added by hand in the console is
# removed at the next apply.
resource "keycloak_group_memberships" "infra" {
  realm_id = keycloak_realm.kube_lab.id
  group_id = keycloak_group.infra.id
  members  = ["brian.perret", "hugo.guillet"]
}

resource "keycloak_group_memberships" "k3s_admin" {
  realm_id = keycloak_realm.kube_lab.id
  group_id = keycloak_group.k3s_admin.id
  members  = ["brian.perret", "hugo.guillet"]
}
