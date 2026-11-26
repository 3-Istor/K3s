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
# member added by hand in the console is removed at the next apply. finops and
# security-auditor are managed from the CMP portal; Terraform only adds the demo
# accounts (demo_portal). Project groups are not listed here, the CMP owns them. cluster-admin kubectl is not standing: it is
# the elevated-k3s-admin grant, brokered by the CMP.
locals {
  platform_admins = ["brian.perret", "hugo.guillet"]

  platform_group_members = {
    infra  = local.platform_admins
    member = concat(keys(local.team_members), tolist(local.demo_accounts), ["manager.test"])
  }

  platform_groups = {
    infra  = keycloak_group.infra.id
    member = keycloak_group.member.id
  }

  portal_groups = {
    auditor = keycloak_group.security_auditor.id
    finops  = keycloak_group.finops.id
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

# Non-exhaustive: the portal adds and removes other members. Remove the old
# platform["finops"] and platform["security-auditor"] from the state before applying.
resource "keycloak_user_groups" "demo_portal" {
  for_each = {
    for pair in setproduct(keys(local.portal_groups), local.demo_people) :
    "demo-${pair[0]}-${pair[1]}" => local.portal_groups[pair[0]]
  }
  realm_id   = keycloak_realm.kube_lab.id
  user_id    = keycloak_user.demo[each.key].id
  group_ids  = [each.value]
  exhaustive = false
}

moved {
  from = keycloak_group_memberships.infra
  to   = keycloak_group_memberships.platform["infra"]
}
