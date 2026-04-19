#  ADMIN USER
# resource "keycloak_user" "admin_user" {
#   realm_id       = keycloak_realm.kube_lab.id
#   username       = "admin"
#   enabled        = true
#   email          = "admin@kube-lab.local"
#   email_verified = true
#   first_name     = "Admin"
#   last_name      = "User"

#   initial_password {
#     value     = "Admin123!"
#     temporary = false
#   }
# }
# resource "keycloak_user_groups" "admin_user_groups" {
#   realm_id  = keycloak_realm.kube_lab.id
#   user_id   = keycloak_user.admin_user.id
#   group_ids = [keycloak_group.admin.id]
# }

# USERS
locals {
  team_members = {
    "hugo.guillet"  = { first = "Hugo", last = "Guillet", is_infra = false }
    "newfel.levrel" = { first = "Newfel", last = "Levrel", is_infra = false }
    "joe.bejjani"   = { first = "Joe", last = "Bejjani", is_infra = false }
    "raphael.ye"    = { first = "Raphael", last = "Ye", is_infra = false }
    "arthur.presle" = { first = "Arthur", last = "Presle", is_infra = false }
    "brian.perret"  = { first = "Brian", last = "Perret", is_infra = true }
  }
}

resource "random_password" "team" {
  for_each = local.team_members

  length  = 16
  special = true
}

resource "keycloak_user" "team" {
  for_each       = local.team_members
  realm_id       = keycloak_realm.kube_lab.id
  username       = each.key
  email          = "${each.key}@epita.fr"
  first_name     = each.value.first
  last_name      = each.value.last
  enabled        = true
  email_verified = true

  initial_password {
    value     = random_password.team[each.key].result
    temporary = true
  }
}

resource "keycloak_user_groups" "team_groups" {
  for_each = local.team_members
  realm_id = keycloak_realm.kube_lab.id
  user_id  = keycloak_user.team[each.key].id

  group_ids = each.value.is_infra ? [
    keycloak_group.member.id,
    keycloak_group.infra.id
    ] : [
    keycloak_group.member.id
  ]
}

output "initial_passwords" {
  value = {
    for k, v in random_password.team :
    k => v.result
  }

  sensitive = true
}
