# Shared demo accounts, one per identity of the access matrix (CNP-228). The
# whole team uses them to show the segregation; passwords are in Vault at
# kvv2/demo-accounts, readable by every team member. MFA stays mandatory: the
# first login sets up TOTP, then its secret is stored next to the password.
# demo-auditor is in security-auditor, so flow v6 also asks it for a passkey: it
# has to live in a password manager the team shares.
# No demo platform admin: a shared one would make every member admin.
# Platform groups are in groups.tf; the CMP adds the project groups of the demo-roles project.
locals {
  demo_accounts = toset([
    "demo-auditor",
    "demo-finops",
    "demo-owner",
    "demo-admin",
    "demo-dev",
    "demo-guest",
  ])
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
  mount = vault_mount.kvv2.path
  name  = "demo-accounts"
  data_json = jsonencode({
    for name in local.demo_accounts : name => random_password.demo[name].result
  })

  lifecycle {
    # TOTP secrets are added by hand after each account's first login.
    ignore_changes = [data_json]
  }
}

resource "vault_policy" "demo_accounts_read" {
  name   = "demo-accounts-read"
  policy = <<-EOT
    path "${vault_mount.kvv2.path}/data/demo-accounts" {
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
