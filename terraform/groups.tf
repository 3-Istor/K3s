resource "keycloak_group" "infra" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "infra"
}

resource "keycloak_group" "member" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "member"
}

# Just-in-time elevations (CNP-124). Nobody is a member at rest: the CMP adds
# a platform admin after another one approves, and removes them at expiry. It
# also removes, and reports, anyone it finds here without an active grant, so
# these groups take no keycloak_group_memberships.
resource "keycloak_group" "elevated" {
  for_each = toset(["vault-data", "k3s-admin"])
  realm_id = keycloak_realm.kube_lab.id
  name     = "elevated-${each.key}"
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
# listed here, the CMP owns them. cluster-admin kubectl is not standing: it is
# the elevated-k3s-admin grant, brokered by the CMP.
locals {
  platform_admins = ["brian.perret", "hugo.guillet"]

  platform_group_members = {
    infra            = local.platform_admins
    security-auditor = ["demo-auditor"]
    finops           = ["demo-finops"]
    member           = concat(keys(local.team_members), tolist(local.demo_accounts), ["manager.test"])
  }

  platform_groups = {
    infra            = keycloak_group.infra.id
    security-auditor = keycloak_group.security_auditor.id
    finops           = keycloak_group.finops.id
    member           = keycloak_group.member.id
  }

  managed_usernames = merge(
    { for name, user in keycloak_user.team : name => user.username },
    { for name, user in keycloak_user.demo : name => user.username },
    { "manager.test" = keycloak_user.manager_test.username },
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
