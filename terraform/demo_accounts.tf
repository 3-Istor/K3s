# Demo accounts, one per identity of the access matrix and per person (CNP-228):
# demo-<role>-<person>. Personal so each one carries its owner's passkey and
# TOTP, which a shared account cannot. Passwords are in Vault at
# kvv2/demo-accounts-<person>, readable by every team member.
# demo-auditor-* is in security-auditor, so flow v6 also asks it for a passkey.
# No demo platform admin: Brian and Hugo already are platform admins.
# Platform groups are in groups.tf; the CMP adds the project groups.
locals {
  demo_roles  = ["auditor", "finops", "owner", "admin", "dev", "guest"]
  demo_people = ["brian", "hugo"]

  demo_accounts = toset([
    for pair in setproduct(local.demo_roles, local.demo_people) : "demo-${pair[0]}-${pair[1]}"
  ])
  demo_accounts_of_role = {
    for role in local.demo_roles : role => [for person in local.demo_people : "demo-${role}-${person}"]
  }
}

resource "random_password" "demo" {
  for_each = local.demo_accounts

  length  = 24
  special = false
}

resource "keycloak_user" "demo" {
  for_each       = local.demo_accounts
  realm_id       = keycloak_realm.kube_lab.id
  username       = each.key
  email          = "${each.key}@${var.base_domain}"
  first_name     = "Demo"
  last_name      = trimprefix(each.key, "demo-")
  enabled        = true
  email_verified = true

  initial_password {
    value     = random_password.demo[each.key].result
    temporary = false
  }

  lifecycle {
    ignore_changes = [required_actions, initial_password, attributes]
  }
}

# Replaced by keycloak_group_memberships.platform. destroy = false: destroying it would have
# removed the demo accounts from member and their platform group.
removed {
  from = keycloak_user_groups.demo

  lifecycle {
    destroy = false
  }
}

resource "vault_kv_secret_v2" "demo_accounts" {
  for_each = toset(local.demo_people)
  mount    = vault_mount.kvv2.path
  name     = "demo-accounts-${each.key}"
  data_json = jsonencode({
    for role in local.demo_roles : "demo-${role}-${each.key}" => random_password.demo["demo-${role}-${each.key}"].result
  })

  lifecycle {
    # TOTP secrets are added by hand after each account's first login.
    ignore_changes = [data_json]
  }
}

resource "vault_policy" "demo_accounts_read" {
  name   = "demo-accounts-read"
  policy = <<-EOT
    path "${vault_mount.kvv2.path}/data/demo-accounts-*" {
      capabilities = ["read", "update", "patch"]
    }
  EOT
}

resource "vault_identity_group" "member" {
  name     = "member"
  type     = "external"
  policies = [vault_policy.demo_accounts_read.name]
}

resource "vault_identity_group_alias" "member_alias" {
  name           = "member"
  mount_accessor = vault_jwt_auth_backend.keycloak.accessor
  canonical_id   = vault_identity_group.member.id
}
