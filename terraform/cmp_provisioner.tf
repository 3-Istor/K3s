# -----------------------------------------------------------------------------
# CMP provisioner: the CMP's Keycloak identity, in place of the master admin
# -----------------------------------------------------------------------------
# The CMP creates a realm per project (project-bootstrap) and per staging
# environment (k3s-gitops-app/staging-realm), so this client lives in master:
# only a master identity can hold create-realm. Service account only.
#
# Keycloak grants the creator of a realm every role of its master client
# "<realm>-realm" except impersonation: realms the CMP creates from now on need
# nothing here. Realms created before, by the admin user, are listed in
# cmp_provisioner_existing_project_realms.
#
# A master client may map a realm's individual admin roles but not the
# realm-admin composite (403, Keycloak 26.8.1), hence app-templates maps the
# roles one by one to the tenant admins.

variable "cmp_provisioner_existing_project_realms" {
  description = "Project realms (and <project>-staging realms) created by the master admin before cmp-provisioner existed. Remove a realm once its project is deleted: the read of its <realm>-realm client fails once the realm is gone."
  type        = list(string)
  default     = ["iot", "joetest", "self-runner", "self-runner-staging", "test-link"]
}

locals {
  # In 3istor, project-bootstrap creates the project groups, the
  # project-<p>-access realm role, the browser-project-<p> login flow and the
  # broker-<p> client. Keycloak lets each manage-* role stand for its view-* and
  # query-* counterparts.
  cmp_provisioner_platform_roles = toset([
    "manage-clients",
    "manage-realm",
    "manage-users",
  ])

  # The creator's grant: Keycloak only lets the client map to the tenant
  # admins the roles it holds itself.
  cmp_provisioner_project_roles = toset([
    "create-client",
    "manage-authorization",
    "manage-clients",
    "manage-events",
    "manage-identity-providers",
    "manage-organizations",
    "manage-realm",
    "manage-users",
    "query-clients",
    "query-groups",
    "query-organizations",
    "query-realms",
    "query-users",
    "view-authorization",
    "view-clients",
    "view-events",
    "view-identity-providers",
    "view-organizations",
    "view-realm",
    "view-users",
  ])

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

resource "vault_kv_secret_v2" "arcl_cmp_keycloak_provisioner" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/keycloak-provisioner"
  data_json = jsonencode({
    "client-id"     = keycloak_openid_client.cmp_provisioner.client_id
    "client-secret" = keycloak_openid_client.cmp_provisioner.client_secret
  })
}
