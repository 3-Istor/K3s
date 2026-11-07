# Shared demo accounts, one per identity of the access matrix (CNP-228). The
# whole team uses them to show the segregation; passwords are in Vault at
# kvv2/demo-accounts, readable by every team member. MFA stays mandatory: the
# first login sets up TOTP, then its secret is stored next to the password.
# No demo platform admin: a shared one would make every member admin.
locals {
  demo_accounts = {
    "demo-auditor" = [keycloak_group.member.id, keycloak_group.security_auditor.id]
    "demo-finops"  = [keycloak_group.member.id, keycloak_group.finops.id]
    "demo-owner"   = [keycloak_group.member.id]
    "demo-admin"   = [keycloak_group.member.id]
    "demo-dev"     = [keycloak_group.member.id]
    "demo-guest"   = [keycloak_group.member.id]
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

# Not exhaustive: the CMP adds the project groups of the demo-roles project.
resource "keycloak_user_groups" "demo" {
  for_each   = local.demo_accounts
  realm_id   = keycloak_realm.kube_lab.id
  user_id    = keycloak_user.demo[each.key].id
  group_ids  = each.value
  exhaustive = false
}

resource "vault_kv_secret_v2" "demo_accounts" {
  mount = vault_mount.kvv2.path
  name  = "demo-accounts"
  data_json = jsonencode({
    for name, _ in local.demo_accounts : name => random_password.demo[name].result
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
