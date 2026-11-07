# -----------------------------------------------------------------------------
# CMP provisioner: the CMP's master realm identity, in place of the admin user
# -----------------------------------------------------------------------------
# Service account only. It creates project realms (create-realm), and Keycloak
# grants the creator of a realm every role of the new "<realm>-realm" client:
# realms created from now on need nothing here. In 3istor it manages the
# per-project groups, roles, broker clients and login flows.

variable "cmp_provisioner_existing_project_realms" {
  description = "Project realms created by the master admin before cmp-provisioner existed; it is granted their admin roles once."
  type        = list(string)
  default     = ["iot", "joetest", "self-runner", "self-runner-staging", "test-link"]
}

locals {
  cmp_provisioner_platform_roles = toset([
    "manage-clients",
    "manage-realm",
    "manage-users",
    "query-clients",
    "query-groups",
    "query-users",
    "view-clients",
    "view-realm",
    "view-users",
  ])

  # What the creator of a realm gets, less impersonation.
  cmp_provisioner_project_roles = [
    "create-client",
    "manage-authorization",
    "manage-clients",
    "manage-events",
    "manage-identity-providers",
    "manage-realm",
    "manage-users",
    "query-clients",
    "query-groups",
    "query-realms",
    "query-users",
    "view-authorization",
    "view-clients",
    "view-events",
    "view-identity-providers",
    "view-realm",
    "view-users",
  ]

  cmp_provisioner_project_grants = {
    for pair in setproduct(var.cmp_provisioner_existing_project_realms, local.cmp_provisioner_project_roles) :
    "${pair[0]}/${pair[1]}" => { realm = pair[0], role = pair[1] }
  }
}

resource "keycloak_openid_client" "cmp_provisioner" {
  realm_id  = "master"
  client_id = "cmp-provisioner"
  name      = "CMP provisioner"
  enabled   = true

  access_type                  = "CONFIDENTIAL"
  service_accounts_enabled     = true
  standard_flow_enabled        = false
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
}

resource "keycloak_openid_client_service_account_realm_role" "cmp_provisioner_create_realm" {
  realm_id                = "master"
  service_account_user_id = keycloak_openid_client.cmp_provisioner.service_account_user_id
  role                    = "create-realm"
}

data "keycloak_openid_client" "platform_realm_admin" {
  realm_id = "master"
  # A literal, as for realm_management in clients.tf: a pending realm change
  # would otherwise defer this read and replace every grant below.
  client_id = "3istor-realm"
}

resource "keycloak_openid_client_service_account_role" "cmp_provisioner_platform" {
  for_each                = local.cmp_provisioner_platform_roles
  realm_id                = "master"
  service_account_user_id = keycloak_openid_client.cmp_provisioner.service_account_user_id
  client_id               = data.keycloak_openid_client.platform_realm_admin.id
  role                    = each.value
}

data "keycloak_openid_client" "project_realm_admin" {
  for_each  = toset(var.cmp_provisioner_existing_project_realms)
  realm_id  = "master"
  client_id = "${each.value}-realm"
}

resource "keycloak_openid_client_service_account_role" "cmp_provisioner_project" {
  for_each                = local.cmp_provisioner_project_grants
  realm_id                = "master"
  service_account_user_id = keycloak_openid_client.cmp_provisioner.service_account_user_id
  client_id               = data.keycloak_openid_client.project_realm_admin[each.value.realm].id
  role                    = each.value.role
}
