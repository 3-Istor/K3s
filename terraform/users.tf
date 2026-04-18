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

#  DEV USER
resource "keycloak_user" "dev_user" {
  realm_id       = keycloak_realm.kube_lab.id
  username       = "dev"
  enabled        = true
  email          = "dev@kube-lab.local"
  email_verified = true
  first_name     = "Dev"
  last_name      = "User"

  initial_password {
    value     = "Dev12345!"
    temporary = false
  }
}
resource "keycloak_user_groups" "dev_user_groups" {
  realm_id  = keycloak_realm.kube_lab.id
  user_id   = keycloak_user.dev_user.id
  group_ids = [keycloak_group.developer.id]
}

# SRE USER
resource "keycloak_user" "sre_user" {
  realm_id       = keycloak_realm.kube_lab.id
  username       = "sre"
  enabled        = true
  email          = "sre@kube-lab.local"
  email_verified = true
  first_name     = "Sre"
  last_name      = "User"

  initial_password {
    value     = "Sre12345!"
    temporary = false
  }
}
resource "keycloak_user_groups" "sre_user_groups" {
  realm_id  = keycloak_realm.kube_lab.id
  user_id   = keycloak_user.sre_user.id
  group_ids = [keycloak_group.sre.id]
}
