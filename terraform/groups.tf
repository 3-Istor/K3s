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

# Platform group members. Each keycloak_group_memberships is authoritative for its group: a
# member added by hand in the console is removed at the next apply. Project groups are not
# listed here, the CMP owns them.
locals {
  platform_admins = ["brian.perret", "hugo.guillet"]

  platform_group_members = {
    infra            = local.platform_admins
    k3s-admin        = local.platform_admins
    security-auditor = ["demo-auditor"]
    finops           = ["demo-finops"]
    member           = concat(keys(local.team_members), tolist(local.demo_accounts))
  }

  platform_groups = {
    infra            = keycloak_group.infra.id
    k3s-admin        = keycloak_group.k3s_admin.id
    security-auditor = keycloak_group.security_auditor.id
    finops           = keycloak_group.finops.id
    member           = keycloak_group.member.id
  }

  managed_usernames = merge(
    { for name, user in keycloak_user.team : name => user.username },
    { for name, user in keycloak_user.demo : name => user.username },
  )
}

resource "keycloak_group_memberships" "platform" {
  for_each = local.platform_groups
  realm_id = keycloak_realm.kube_lab.id
  group_id = each.value
  # Through managed_usernames so a typo fails the plan and users exist before membership.
  members = [for name in local.platform_group_members[each.key] : local.managed_usernames[name]]
}

moved {
  from = keycloak_group_memberships.infra
  to   = keycloak_group_memberships.platform["infra"]
}

moved {
  from = keycloak_group_memberships.k3s_admin
  to   = keycloak_group_memberships.platform["k3s-admin"]
}
